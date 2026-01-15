import 'package:seogodong/features/link_check/domain/check_status.dart';

class UrlCheckItem {
  UrlCheckItem({
    required this.url,
    required this.status,
    this.threatType,
    this.details,
  });

  final String url;
  final CheckStatus status;
  final String? threatType;
  final String? details;

  String get description {
    switch (status) {
      case CheckStatus.safe:
        return '위험 신호가 감지되지 않았습니다.';
      case CheckStatus.unsafe:
        return threatType != null ? '위험 감지: $threatType' : '위험 신호가 감지되었습니다.';
      case CheckStatus.error:
        return '검사 중 오류가 발생했습니다.';
      case CheckStatus.missingKey:
        return 'SAFE_BROWSING_API_KEY가 필요합니다.';
      case CheckStatus.pending:
        return '검사 대기 중입니다.';
    }
  }

  UrlCheckItem copyWith({
    CheckStatus? status,
    String? threatType,
    String? details,
  }) {
    return UrlCheckItem(
      url: url,
      status: status ?? this.status,
      threatType: threatType ?? this.threatType,
      details: details ?? this.details,
    );
  }
}
