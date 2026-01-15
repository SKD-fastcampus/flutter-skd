List<String> extractUrls(String text) {
  final RegExp regex = RegExp(
    r'((?:https?:\/\/|www\.)[^\s]+|(?:[a-z0-9-]+\.)+[a-z]{2,}(?:\/[^\s]*)?)',
    caseSensitive: false,
  );
  return regex
      .allMatches(text)
      .map((match) => match.group(0))
      .whereType<String>()
      .map(_normalizeUrl)
      .whereType<String>()
      .toSet()
      .toList();
}

String buildSnippet(String text) {
  final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '공유된 메시지';
  }
  const int maxLength = 48;
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}…';
}

String? _normalizeUrl(String raw) {
  final String trimmed = raw.replaceAll(RegExp(r'[)\],.!?]+$'), '');
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    return trimmed;
  }
  return trimmed;
}
