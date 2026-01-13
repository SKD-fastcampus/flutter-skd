import 'package:flutter/material.dart';
import 'package:seogodong/core/utils/text_utils.dart';
import 'package:seogodong/features/link_check/data/history_repository.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startMockAnalysis();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startMockAnalysis() async {
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

    // 3. AI Analysis
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _statusText = 'AI 정밀 분석 중...';
        _progress = 0.9;
      });
    }

    // 4. Finish
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      setState(() {
        _statusText = '분석 완료!';
        _progress = 1.0;
      });
      _navigateToResult();
    }
  }

  Future<void> _navigateToResult() async {
    // Extract URL
    final List<String> urls = extractUrls(widget.textToCheck);
    final String urlToUse = urls.isNotEmpty
        ? urls.first
        : 'https://example.com'; // Fallback if no URL

    // Determine a mock result
    final bool isSuspicious = widget.textToCheck.contains('http');
    final resultItem = MessageCheckItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullText: widget.textToCheck,
      snippet: buildSnippet(widget.textToCheck),
      url: urlToUse,
      status: isSuspicious ? CheckStatus.unsafe : CheckStatus.safe,
      llmSummary: isSuspicious
          ? '의심스러운 링크가 포함되어 있습니다. 주의가 필요합니다.'
          : '특별한 위협이 감지되지 않았습니다.',
    );

    // Save to History via Repository
    await HistoryRepository().addItem(resultItem);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MessageDetailPage(item: resultItem, onSummaryUpdate: (s) async {}),
      ),
    );
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
