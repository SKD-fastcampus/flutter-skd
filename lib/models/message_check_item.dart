import 'package:flutter/material.dart';
import 'package:seogodong/models/check_status.dart';

class MessageCheckItem {
  MessageCheckItem({
    required this.id,
    required this.snippet,
    required this.fullText,
    required this.url,
    required this.status,
    this.threatType,
    this.details,
    this.searchId,
    this.analysisStatus,
    this.riskScore,
    this.finalUrl,
    this.messageText,
    this.screenshotPath,
    this.llmSummary,
    this.detailsJson,
  });

  final String id;
  final String snippet;
  final String fullText;
  final String url;
  final CheckStatus status;
  final String? threatType;
  final String? details;
  final String? searchId;
  final String? analysisStatus;
  final int? riskScore;
  final String? finalUrl;
  final String? messageText;
  final String? screenshotPath;
  final String? llmSummary;
  final String? detailsJson;

  String get riskLabel {
    switch (status) {
      case CheckStatus.unsafe:
        return '위험';
      case CheckStatus.safe:
        return '안전';
      case CheckStatus.pending:
      case CheckStatus.error:
      case CheckStatus.missingKey:
        return '주의';
    }
  }

  Color get riskColor {
    switch (status) {
      case CheckStatus.unsafe:
        return Colors.red;
      case CheckStatus.safe:
        return Colors.green;
      case CheckStatus.pending:
      case CheckStatus.error:
      case CheckStatus.missingKey:
        return Colors.orange;
    }
  }

  bool get isSearchComplete {
    if (status == CheckStatus.unsafe) {
      return true;
    }
    if (analysisStatus == null) {
      return false;
    }
    return analysisStatus != 'PENDING';
  }

  String get resultLabel {
    if (!isSearchComplete) {
      return '분석 중';
    }
    return '${riskLabel} ${riskEmoji}';
  }

  String get resultLabelWithScore {
    if (!isSearchComplete) {
      return resultLabel;
    }
    if (riskScore == null) {
      return riskLabel;
    }
    return '${riskLabel}(${riskScore})';
  }

  Color get resultColor {
    if (!isSearchComplete) {
      return Colors.black;
    }
    return riskColor;
  }

  String get riskEmoji {
    switch (status) {
      case CheckStatus.safe:
        return '🙂';
      case CheckStatus.pending:
      case CheckStatus.error:
      case CheckStatus.missingKey:
        return '😐';
      case CheckStatus.unsafe:
        return '😠';
    }
  }

  String get riskDescription {
    switch (status) {
      case CheckStatus.unsafe:
        return '이 링크는 위험 신호가 감지되었습니다. '
            '출처가 불분명하거나 로그인/결제 요청이 있다면 절대 입력하지 마세요.';
      case CheckStatus.safe:
        return '현재까지 확인된 위험 신호가 없습니다. '
            '그래도 개인정보 입력은 신중히 진행하세요.';
      case CheckStatus.pending:
      case CheckStatus.error:
      case CheckStatus.missingKey:
        return '확인 중이거나 정보가 충분하지 않습니다. '
            '가능하면 직접 방문을 피하고 추가 확인을 권장합니다.';
    }
  }

  MessageCheckItem copyWith({
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
    return MessageCheckItem(
      id: id,
      snippet: snippet,
      fullText: fullText,
      url: url,
      status: status ?? this.status,
      threatType: threatType ?? this.threatType,
      details: details ?? this.details,
      searchId: searchId ?? this.searchId,
      analysisStatus: analysisStatus ?? this.analysisStatus,
      riskScore: riskScore ?? this.riskScore,
      finalUrl: finalUrl ?? this.finalUrl,
      messageText: messageText ?? this.messageText,
      screenshotPath: screenshotPath ?? this.screenshotPath,
      llmSummary: llmSummary ?? this.llmSummary,
      detailsJson: detailsJson ?? this.detailsJson,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'snippet': snippet,
      'fullText': fullText,
      'url': url,
      'status': status.index,
      'threatType': threatType,
      'details': details,
      'searchId': searchId,
      'analysisStatus': analysisStatus,
      'riskScore': riskScore,
      'finalUrl': finalUrl,
      'messageText': messageText,
      'screenshotPath': screenshotPath,
      'llmSummary': llmSummary,
      'detailsJson': detailsJson,
    };
  }

  factory MessageCheckItem.fromJson(Map<String, dynamic> json) {
    return MessageCheckItem(
      id: json['id'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      fullText:
          json['fullText'] as String? ?? (json['snippet'] as String? ?? ''),
      url: json['url'] as String? ?? '',
      status: CheckStatus.values[(json['status'] as int?) ?? 0],
      threatType: json['threatType'] as String?,
      details: json['details'] as String?,
      searchId: json['searchId'] as String?,
      analysisStatus: json['analysisStatus'] as String?,
      riskScore: json['riskScore'] as int?,
      finalUrl: json['finalUrl'] as String?,
      messageText: json['messageText'] as String?,
      screenshotPath: json['screenshotPath'] as String?,
      llmSummary: json['llmSummary'] as String?,
      detailsJson: json['detailsJson'] as String?,
    );
  }
}
