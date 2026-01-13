import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/core/config/constants.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';
import 'package:seogodong/features/link_check/domain/url_check_item.dart';
import 'package:seogodong/features/link_check/presentation/message_detail_page.dart';
import 'package:seogodong/features/link_check/data/safe_browsing_client.dart';
import 'package:seogodong/core/utils/text_utils.dart';
import 'package:seogodong/features/link_check/presentation/widgets/message_card.dart';

class ShareCheckPage extends StatefulWidget {
  const ShareCheckPage({super.key});

  @override
  State<ShareCheckPage> createState() => _ShareCheckPageState();
}

class _ShareCheckPageState extends State<ShareCheckPage> {
  final SafeBrowsingClient _client = SafeBrowsingClient();
  StreamSubscription<List<SharedMediaFile>>? _mediaStreamSubscription;
  final List<MessageCheckItem> _items = [];
  final Set<String> _selectedIds = {};
  int _activeChecks = 0;
  bool _isLoading = true;
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _mediaStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadItems();
    if (!mounted) return;
    _setupSharing();
  }

  Future<void> _setupSharing() async {
    final List<SharedMediaFile> initialMedia = await ReceiveSharingIntent
        .instance
        .getInitialMedia();
    final String? initialText = _extractText(initialMedia);
    if (initialText != null && initialText.isNotEmpty) {
      _handleSharedText(initialText);
    }
    _mediaStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((media) {
          final String? sharedText = _extractText(media);
          if (sharedText != null && sharedText.isNotEmpty) {
            _handleSharedText(sharedText);
          }
        });
  }

  void _handleSharedText(String text) {
    developer.log('Shared text received: $text', name: 'Share');
    final List<String> urls = extractUrls(text);
    developer.log('Extracted URLs: ${urls.join(', ')}', name: 'Share');
    if (urls.isEmpty) {
      return;
    }
    final String snippet = buildSnippet(text);
    final int baseId = DateTime.now().microsecondsSinceEpoch;
    final List<MessageCheckItem> newItems = [];
    for (int i = 0; i < urls.length; i++) {
      newItems.add(
        MessageCheckItem(
          id: '${baseId}_$i',
          snippet: snippet,
          fullText: text,
          url: urls[i],
          status: CheckStatus.pending,
        ),
      );
    }
    setState(() {
      _items.insertAll(0, newItems);
    });
    _saveItems();
    _checkUrls(newItems);
  }

  void _seedSamples() {
    final int baseId = DateTime.now().microsecondsSinceEpoch;
    _items.addAll([
      MessageCheckItem(
        id: '${baseId}_sample_safe',
        snippet: '예시 메시지: 배송 조회 링크를 확인하세요',
        fullText: '예시 메시지: 배송 조회 링크를 확인하세요',
        url: 'https://example.com/track',
        status: CheckStatus.safe,
        analysisStatus: 'DONE',
        riskScore: 5,
      ),
      MessageCheckItem(
        id: '${baseId}_sample_warn',
        snippet: '예시 메시지: 계정 확인이 필요합니다',
        fullText: '예시 메시지: 계정 확인이 필요합니다',
        url: 'http://example.com/login',
        status: CheckStatus.pending,
        analysisStatus: 'DONE',
        riskScore: 45,
      ),
      MessageCheckItem(
        id: '${baseId}_sample_danger',
        snippet: '예시 메시지: 긴급 보안 업데이트 필요',
        fullText: '예시 메시지: 긴급 보안 업데이트 필요',
        url: 'http://phishing.example.com',
        status: CheckStatus.unsafe,
        analysisStatus: 'DONE',
        riskScore: 90,
      ),
    ]);
  }

  String? _extractText(List<SharedMediaFile> media) {
    if (media.isEmpty) {
      return null;
    }
    final List<String> parts = [];
    for (final item in media) {
      if (item.type == SharedMediaType.text ||
          item.type == SharedMediaType.url) {
        parts.add(item.path);
      } else if (item.message != null && item.message!.isNotEmpty) {
        parts.add(item.message!);
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n');
  }

  Future<void> _checkUrls(List<MessageCheckItem> targets) async {
    developer.log(
      'Checking ${targets.length} urls, apiKeyEmpty=${safeBrowsingApiKey.isEmpty}',
      name: 'SafeBrowsing',
    );
    if (safeBrowsingApiKey.isEmpty) {
      setState(() {
        for (final target in targets) {
          _updateItem(target.id, status: CheckStatus.missingKey);
        }
      });
      return;
    }
    if (targets.isEmpty) {
      return;
    }
    setState(() {
      _activeChecks += targets.length;
    });

    for (final item in targets) {
      try {
        final UrlCheckItem result = await _client.checkUrl(item.url);
        if (!mounted) return;
        setState(() {
          _updateItem(
            item.id,
            status: result.status,
            threatType: result.threatType,
            details: result.details,
          );
        });
        if (result.status == CheckStatus.safe) {
          await _requestSearchServer(item.id, item.url);
        }
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _updateItem(
            item.id,
            status: CheckStatus.error,
            details: error.toString(),
          );
        });
      }
    }

    setState(() {
      _activeChecks -= targets.length;
    });
    _saveItems();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasItems = _items.isNotEmpty;
    final bool isChecking = _activeChecks > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('검사 기록'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '검사한 메시지',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (_selectionMode && _selectedIds.isNotEmpty)
                        IconButton(
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete),
                          color: Colors.red.shade400,
                        )
                      else if (isChecking)
                        const CircularProgressIndicator(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: hasItems
                        ? ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _buildSlidableRow(context, _items[index]),
                          )
                        : _buildEmptyState(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSlidableRow(BuildContext context, MessageCheckItem item) {
    if (_selectionMode) {
      return MessageCard(
        item: item,
        selected: _selectedIds.contains(item.id),
        selectionMode: _selectionMode,
        onTap: () {
          _toggleSelection(item.id);
        },
        onLongPress: () {
          _toggleSelection(item.id, forceOn: true);
        },
      );
    }
    return Slidable(
      key: ValueKey(item.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) async {
              final bool confirmed = await _confirmDelete(context);
              if (confirmed) {
                _removeItem(item.id);
              }
            },
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '삭제',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: MessageCard(
        item: item,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MessageDetailPage(
                item: item,
                onSummaryUpdate: (summary) async {
                  _updateItem(item.id, llmSummary: summary);
                  await _saveItems();
                },
              ),
            ),
          );
        },
        onLongPress: () {
          _toggleSelection(item.id, forceOn: true);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        '메시지나 채팅을 공유하면 자동으로 링크를 추출합니다.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  void _updateItem(
    String id, {
    CheckStatus? status,
    String? threatType,
    String? details,
    String? searchId,
    String? analysisStatus,
    int? riskScore,
    String? finalUrl,
    String? messageText,
    String? screenshotPath,
    String? llmSummary,
    String? detailsJson,
  }) {
    final int index = _items.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    _items[index] = _items[index].copyWith(
      status: status,
      threatType: threatType,
      details: details,
      searchId: searchId,
      analysisStatus: analysisStatus,
      riskScore: riskScore,
      finalUrl: finalUrl,
      messageText: messageText,
      screenshotPath: screenshotPath,
      llmSummary: llmSummary,
      detailsJson: detailsJson,
    );
  }

  Future<void> _requestSearchServer(String id, String url) async {
    if (searchServerBaseUrl.isEmpty) {
      debugPrint('SearchServer: SEARCH_SERVER_BASE_URL is empty');
      return;
    }
    final firebase_auth.User? user =
        firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('SearchServer: Firebase user is null');
      return;
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      debugPrint('SearchServer: Firebase idToken is empty');
      return;
    }
    final Uri endpoint = Uri.parse(
      searchServerBaseUrl,
    ).resolve('api/whitelist/check');
    final Map<String, dynamic> payload = {
      'userId': user.uid,
      'originalUrl': url,
    };
    debugPrint('SearchServer: POST $endpoint');
    debugPrint('SearchServer: headers Authorization: Bearer $idToken');
    debugPrint('SearchServer: body ${jsonEncode(payload)}');
    try {
      http.Response response;
      while (true) {
        response = await http.post(
          endpoint,
          headers: {'Authorization': 'Bearer $idToken'},
          body: jsonEncode(payload),
        );
        debugPrint(
          'SearchServer: Response ${response.statusCode}: ${response.body}',
        );
        if (response.statusCode != 200) {
          return;
        }
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String? status = body['status'] as String?;
        if (!mounted) return;
        setState(() {
          _updateItem(
            id,
            searchId: body['id']?.toString(),
            analysisStatus: status,
            riskScore: body['riskScore'] as int?,
            finalUrl: body['finalUrl'] as String?,
            messageText: body['messageText'] as String?,
            screenshotPath: body['screenshotPath'] as String?,
            llmSummary: body['llmSummary'] as String?,
            detailsJson: body['details'] as String?,
          );
        });
        _saveItems();
        if (status != null && status != 'PENDING') {
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (error) {
      debugPrint('SearchServer: error $error');
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('이 결과를 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _removeItem(String id) {
    setState(() {
      _items.removeWhere((item) => item.id == id);
    });
    _saveItems();
  }

  void _toggleSelection(String id, {bool forceOn = false}) {
    setState(() {
      if (forceOn) {
        _selectionMode = true;
        _selectedIds.add(id);
        return;
      }
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectionMode = _selectedIds.isNotEmpty;
    });
  }

  void _deleteSelected() {
    if (_selectedIds.isEmpty) {
      return;
    }
    setState(() {
      _items.removeWhere((item) => _selectedIds.contains(item.id));
      _selectedIds.clear();
      _selectionMode = false;
    });
    _saveItems();
  }

  Future<void> _loadItems() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> rawItems = prefs.getStringList('history') ?? [];
    if (rawItems.isEmpty) {
      _seedSamples();
      setState(() {
        _isLoading = false;
      });
      _saveItems();
      return;
    }
    final List<MessageCheckItem> loaded = [];
    for (final raw in rawItems) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(raw) as Map<String, dynamic>;
        loaded.add(MessageCheckItem.fromJson(json));
      } catch (_) {}
    }
    setState(() {
      _items
        ..clear()
        ..addAll(loaded);
      _isLoading = false;
    });
  }

  Future<void> _saveItems() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> rawItems = _items
        .map((item) => jsonEncode(item.toJson()))
        .toList(growable: false);
    await prefs.setStringList('history', rawItems);
  }
}
