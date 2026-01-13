import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:seogodong/config/constants.dart';
import 'package:seogodong/models/check_status.dart';
import 'package:seogodong/models/url_check_item.dart';

class SafeBrowsingClient {
  SafeBrowsingClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<UrlCheckItem> checkUrl(String url) async {
    debugPrint('SafeBrowsing request: $url');
    final Uri endpoint = Uri.parse(
      'https://safebrowsing.googleapis.com/v4/threatMatches:find?key='
      '$safeBrowsingApiKey',
    );
    final Map<String, dynamic> payload = {
      'client': {'clientId': 'seogodong', 'clientVersion': '1.0.0'},
      'threatInfo': {
        'threatTypes': [
          'MALWARE',
          'SOCIAL_ENGINEERING',
          'UNWANTED_SOFTWARE',
          'POTENTIALLY_HARMFUL_APPLICATION',
        ],
        'platformTypes': ['ANY_PLATFORM'],
        'threatEntryTypes': ['URL'],
        'threatEntries': [
          {'url': url},
        ],
      },
    };

    final http.Response response = await _httpClient.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    debugPrint(
      'SafeBrowsing response: ${response.statusCode} ${response.body}',
    );

    if (response.statusCode != 200) {
      return UrlCheckItem(
        url: url,
        status: CheckStatus.error,
        details: 'HTTP ${response.statusCode}',
      );
    }

    final Map<String, dynamic> body = jsonDecode(response.body);
    final List<dynamic>? matches = body['matches'] as List<dynamic>?;
    if (matches == null || matches.isEmpty) {
      return UrlCheckItem(url: url, status: CheckStatus.safe);
    }

    final Map<String, dynamic> first = matches.first as Map<String, dynamic>;
    final String? threatType = first['threatType'] as String?;
    return UrlCheckItem(
      url: url,
      status: CheckStatus.unsafe,
      threatType: threatType,
    );
  }
}
