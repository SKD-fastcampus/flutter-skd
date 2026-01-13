import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/config/constants.dart';
import 'package:seogodong/models/message_check_item.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 상세'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildHeader(context),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final MessageCheckItem item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('분석 결과'),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              item.resultLabel,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: item.resultColor,
              ),
            ),
            const Spacer(),
            Text(
              '위험 수준: ${item.isSearchComplete ? (item.riskScore ?? 0) : '?'}'
              '/100',
              style: TextStyle(
                fontSize: 13,
                color: item.resultColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildRiskBar(item),
        const SizedBox(height: 36),
        _sectionLabel('메시지 내용'),
        const SizedBox(height: 8),
        _buildMessageContent(item.fullText),
        const SizedBox(height: 36),
        _sectionLabel('메시지에서 분석한 링크'),
        const SizedBox(height: 8),
        _buildMessageContent(item.url),
        const SizedBox(height: 36),
        _sectionLabel('분석 설명'),
        const SizedBox(height: 8),
        if (item.isSearchComplete && _analysisText.isNotEmpty)
          _buildAssistantBubble(_analysisText),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.yellow.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // Widget _sectionBody(String text) {
  //   return Text(
  //     text,
  //     style: const TextStyle(fontSize: 16),
  //   );
  // }

  Widget _buildMessageContent(String text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const TextStyle style = TextStyle(fontSize: 16);
        const double toggleWidth = 28;
        final TextPainter painter = TextPainter(
          text: const TextSpan(text: '', style: style),
          textDirection: TextDirection.ltr,
          maxLines: 3,
        )..text = TextSpan(text: text, style: style);
        painter.layout(maxWidth: constraints.maxWidth - toggleWidth);
        final bool exceeds = painter.didExceedMaxLines;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: _messageExpanded ? null : 3,
                overflow: _messageExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (exceeds) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _messageExpanded = !_messageExpanded;
                  });
                },
                child: Icon(
                  _messageExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRiskBar(MessageCheckItem item) {
    final int score = item.riskScore ?? 0;
    final double ratio = (score.clamp(0, 100)) / 100;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * ratio,
              decoration: BoxDecoration(
                color: item.resultColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAssistantBubble(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(
            16,
          ).copyWith(bottomLeft: Radius.zero),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15)),
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
      if (!mounted) return;
      setState(() {
        _isStreaming = false;
      });
    }
    return;
  }
}
