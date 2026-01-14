import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/core/config/constants.dart';
import 'package:seogodong/core/utils/text_utils.dart';
import 'package:seogodong/features/link_check/data/history_repository.dart';
import 'package:seogodong/features/link_check/data/safe_browsing_client.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';
import 'package:seogodong/features/link_check/domain/url_check_item.dart';
import 'package:seogodong/features/link_check/presentation/message_detail_page.dart';

class ScanningPage extends StatefulWidget {
  final String textToCheck;

  const ScanningPage({super.key, required this.textToCheck});

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _statusText = '분석 준비 중...';
  double _progress = 0.0;
  final SafeBrowsingClient _safeBrowsingClient = SafeBrowsingClient();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startAnalysis();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    // 1. Checking link format
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _statusText = '링크 형식을 확인하는 중...';
        _progress = 0.3;
      });
    }

    // 2. Checking blacklist
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _statusText = '악성 데이터베이스 대조 중...';
        _progress = 0.6;
      });
    }

    // 3. Safe Browsing
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _statusText = '구글 Safe Browsing 검사 중...';
        _progress = 0.9;
      });
    }

    // 4. Finish + real analysis
    await Future.delayed(const Duration(milliseconds: 1000));
    await _navigateToResult();
  }

  Future<void> _navigateToResult() async {
    // Extract URL
    final List<String> urls = extractUrls(widget.textToCheck);
    if (urls.isEmpty) {
      final MessageCheckItem fallback = MessageCheckItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fullText: widget.textToCheck,
        snippet: buildSnippet(widget.textToCheck),
        url: '',
        status: CheckStatus.error,
        details: '링크를 찾을 수 없습니다.',
      );
      await HistoryRepository().addItem(fallback);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            item: fallback,
            onSummaryUpdate: (s) async {},
          ),
        ),
      );
      return;
    }

    final List<MessageCheckItem> created = [];
    final int baseId = DateTime.now().microsecondsSinceEpoch;
    for (int i = 0; i < urls.length; i++) {
      final urlToUse = urls[i];
      MessageCheckItem item = MessageCheckItem(
        id: '${baseId}_$i',
        fullText: widget.textToCheck,
        snippet: buildSnippet(widget.textToCheck),
        url: urlToUse,
        status: CheckStatus.pending,
        analysisStatus: 'PENDING',
      );
      await HistoryRepository().addItem(item);
      created.add(item);

      final UrlCheckItem safeBrowsingResult = await _safeBrowsingClient.checkUrl(
        urlToUse,
      );
      item = item.copyWith(
        status: safeBrowsingResult.status,
        threatType: safeBrowsingResult.threatType,
        details: safeBrowsingResult.details,
      );
      if (safeBrowsingResult.status == CheckStatus.unsafe) {
        item = item.copyWith(analysisStatus: 'DONE');
        await HistoryRepository().updateItem(item);
        continue;
      }
      if (safeBrowsingResult.status == CheckStatus.safe) {
        item = await _requestSearchServer(item);
      } else {
        await HistoryRepository().updateItem(item);
      }
      created[created.indexWhere((e) => e.id == item.id)] = item;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          item: created.first,
          onSummaryUpdate: (s) async {
            await HistoryRepository().updateItem(
              created.first.copyWith(llmSummary: s),
            );
          },
        ),
      ),
    );
  }

  Future<MessageCheckItem> _requestSearchServer(MessageCheckItem item) async {
    if (searchServerBaseUrl.isEmpty) {
      return item;
    }
    final firebase_auth.User? user =
        firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return item;
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      return item;
    }
    final String tokenTail =
        idToken.length >= 4 ? idToken.substring(idToken.length - 4) : idToken;
    debugPrint('SearchServer: Firebase ID token(last4)=$tokenTail');
    final Uri endpoint = Uri.parse(
      searchServerBaseUrl,
    ).resolve('api/whitelist/check');
    final Map<String, dynamic> payload = {
      'userId': user.uid,
      'originalUrl': item.url,
    };
    debugPrint(
      'SearchServer: Request GET $endpoint headers={Authorization: Bearer ****$tokenTail, Content-Type: application/json} body=${jsonEncode(payload)}',
    );
    MessageCheckItem current = item;
    final http.Client client = http.Client();
    try {
      while (true) {
        final http.Request request = http.Request('GET', endpoint);
        request.headers['Authorization'] = 'Bearer $idToken';
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(payload);
        final http.StreamedResponse streamedResponse = await client.send(
          request,
        );
        final http.Response response =
            await http.Response.fromStream(streamedResponse);
      debugPrint(
        'SearchServer: Response ${response.statusCode} ${response.body}',
      );
      if (response.statusCode != 200) {
        return current;
      }
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? status = body['status'] as String?;
      current = current.copyWith(
        searchId: (body['result_id'] ?? body['id'])?.toString(),
        analysisStatus: status,
        riskScore: body['riskScore'] as int?,
        finalUrl: body['finalUrl'] as String?,
        messageText: body['messageText'] as String?,
        screenshotPath: body['screenshotPath'] as String?,
        llmSummary: body['llmSummary'] as String?,
        detailsJson: body['details'] as String?,
      );
      await HistoryRepository().updateItem(current);
      if (status != null && status != 'PENDING') {
        return current;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Radar/Shield Icon
            Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _controller,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.blue.shade100.withValues(alpha: 0.1),
                          Colors.blue.shade400,
                          Colors.blue.shade100.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.travel_explore, // or find_in_page, or search
                    size: 40,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                widget.textToCheck,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _statusText,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                color: Colors.blue.shade600,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 60),
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소', style: TextStyle(color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
    );
  }
}
