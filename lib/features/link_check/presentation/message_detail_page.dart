import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/core/config/constants.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({
    super.key,
    required this.item,
    required this.onSummaryUpdate,
  });

  final MessageCheckItem item;
  final Future<void> Function(String summary) onSummaryUpdate;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  final http.Client _httpClient = http.Client();
  String _analysisText = '';
  bool _isStreaming = false;
  bool _messageExpanded = false;

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _analysisText = widget.item.llmSummary ?? '';
    if (widget.item.isSearchComplete && _analysisText.isEmpty) {
      _startAnalysisStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('분석 결과 상세'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Message Content (Top)
            _buildMessageContextSection(item),

            const SizedBox(height: 12),

            // 2. Risk Verdict Banner
            _buildRiskVerdictBanner(item),

            const SizedBox(height: 12),

            // 3. AI Overview (Primary)
            _buildAIAnalysisSection(item),

            const SizedBox(height: 24),

            // 4. Detailed Info
            _buildDetailsSection(item),

            const SizedBox(height: 24),

            // 5. Screenshot
            _buildScreenshotSection(item),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContextSection(MessageCheckItem item) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.message_outlined,
                size: 20,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                '확인 요청된 메시지',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fullText,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                    maxLines: _messageExpanded ? null : 4,
                    overflow: _messageExpanded
                        ? TextOverflow.visible
                        : TextOverflow.clip,
                  ),
                  if (_messageExpanded) const SizedBox(height: 8),
                ],
              ),
              if (!_messageExpanded && item.fullText.length > 100)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0),
                          Colors.white.withOpacity(0.9),
                          Colors.white,
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (item.fullText.length > 100)
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _messageExpanded = !_messageExpanded;
                  });
                },
                icon: Icon(
                  _messageExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
                label: Text(_messageExpanded ? '접기' : '더보기'),
                style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRiskVerdictBanner(MessageCheckItem item) {
    if (!item.isSearchComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '정밀 분석 중입니다...',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  '잠시만 기다려 주세요.',
                  style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final Color color = item.resultColor;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.riskEmoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 12),
              Text(
                item.riskLabel,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.riskDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIAnalysisSection(MessageCheckItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI 인공지능 분석 요약',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _analysisText.isEmpty && _isStreaming
                ? const Center(child: CircularProgressIndicator())
                : Text(
                    _analysisText.isEmpty ? '분석 내용이 아직 없습니다.' : _analysisText,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(MessageCheckItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상세 분석 정보',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildInfoTile(
            icon: Icons.speed,
            title: '위험 점수',
            value: '${item.riskScore ?? 0} / 100',
            subtitle: '점수가 높을수록 위험합니다.',
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            icon: Icons.link,
            title: '분석된 링크',
            value: item.url,
            isLong: true,
          ),
          if (item.finalUrl != null && item.finalUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoTile(
              icon: Icons.launch,
              title: '최종 연결 주소',
              value: item.finalUrl!,
              isLong: true,
              color: Colors.blueGrey,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    bool isLong = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: isLong
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (color ?? Colors.blue).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color ?? Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: isLong ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotSection(MessageCheckItem item) {
    final String? path = item.screenshotPath;
    if (path == null || path.isEmpty) return const SizedBox.shrink();

    // S3 path to HTTP URL conversion logic might be needed here,
    // but assuming for now it's a URL or handled by the image component.
    String displayUrl = path;
    if (path.startsWith('s3://')) {
      // Temporary placeholder if direct S3 access isn't configured in frontend
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '분석 증거 (스크린샷)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '스크린샷을 불러올 수 없습니다.\nS3 권한 확인이 필요합니다.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '분석 증거 (스크린샷)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              displayUrl,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey.shade400,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '이미지를 불러오지 못했습니다.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAnalysisStream() async {
    if (_isStreaming) {
      return;
    }
    if (sseBaseUrl.isEmpty) {
      return;
    }
    final Uri endpoint = Uri.parse(
      sseBaseUrl,
    ).resolve('v1/explain/uuid/stream');
    try {
      final firebase_auth.User? user =
          firebase_auth.FirebaseAuth.instance.currentUser;
      final String? idToken = await user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return;
      }
      setState(() {
        _isStreaming = true;
      });
      final http.Request request = http.Request('GET', endpoint);
      request.headers['Authorization'] = 'Bearer $idToken';
      final http.StreamedResponse response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        setState(() {
          _isStreaming = false;
        });
        return;
      }
      String currentEvent = '';
      await for (final String line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!mounted) return;
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          continue;
        }
        if (!line.startsWith('data:')) {
          continue;
        }
        final String data = line.substring(5).trim();
        if (currentEvent == 'delta') {
          final Map<String, dynamic> payload =
              jsonDecode(data) as Map<String, dynamic>;
          final String text = payload['text'] as String? ?? '';
          if (text.isNotEmpty) {
            setState(() {
              _analysisText = '$_analysisText$text';
            });
          }
        } else if (currentEvent == 'done') {
          break;
        }
      }
      if (_analysisText.isNotEmpty) {
        await widget.onSummaryUpdate(_analysisText);
      }
    } catch (error) {
      debugPrint('SSE stream error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
        });
      }
    }
    return;
  }
}
