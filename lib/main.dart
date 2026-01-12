import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String safeBrowsingApiKey =
    String.fromEnvironment('SAFE_BROWSING_API_KEY');
const String kakaoNativeAppKey =
    String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
const String sseBaseUrl = String.fromEnvironment('SSE_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }

  runApp(const SeogodongApp());
  _printKakaoKeyHash();
}

Future<void> _printKakaoKeyHash() async {
  try {
    String keyHash = await KakaoSdk.origin;
    print('현재 앱의 Kakao Key Hash: $keyHash');
  } catch (e) {
    print('Kakao Key Hash를 가져오는 중 오류 발생: $e');
  }
}

class SeogodongApp extends StatelessWidget {
  const SeogodongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seogodong Link Check',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool _isReady = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadLoginState();
  }

  Future<void> _loadLoginState() async {
    final firebase_auth.User? user =
        firebase_auth.FirebaseAuth.instance.currentUser;
    bool isValid = false;
    if (user != null) {
      try {
        await user.getIdToken();
        isValid = true;
      } catch (_) {
        await firebase_auth.FirebaseAuth.instance.signOut();
      }
    }
    setState(() {
      _isLoggedIn = isValid;
      _isReady = true;
    });
  }

  Future<void> _markLoggedIn() async {
    if (!mounted) return;
    setState(() {
      _isLoggedIn = true;
    });
  }

  Future<void> _logout() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {}
    await firebase_auth.FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isLoggedIn) {
      return ShareCheckPage(onLogout: _logout);
    }
    return LoginPage(onLoginSuccess: _markLoggedIn);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});

  final Future<void> Function() onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoggingIn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SKD',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isLoggingIn ? null : _handleKakaoLogin,
              child: Opacity(
                opacity: _isLoggingIn ? 0.6 : 1,
                child: Image.asset(
                  'kakao_login_large_wide.png',
                  height: 56,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleKakaoLogin() async {
    if (kakaoNativeAppKey.isEmpty) {
      _showSnack('KAKAO_NATIVE_APP_KEY가 필요합니다.');
      return;
    }
    setState(() {
      _isLoggingIn = true;
    });
    try {
      final bool installed = await isKakaoTalkInstalled();
      final OAuthToken token = installed
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      final String? idToken = token.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Kakao idToken이 없습니다.');
      }
      final firebase_auth.OAuthProvider provider =
          firebase_auth.OAuthProvider('oidc.seogodong');
      final firebase_auth.OAuthCredential credential = provider.credential(
        idToken: idToken,
        accessToken: token.accessToken,
      );
      await firebase_auth.FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      await widget.onLoginSuccess();
      if (!mounted) return;
      _showSnack('카카오 로그인 성공');
    } catch (error) {
      _showSnack('카카오 로그인 실패: $error');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoggingIn = false;
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class ShareCheckPage extends StatefulWidget {
  const ShareCheckPage({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<ShareCheckPage> createState() => _ShareCheckPageState();
}

class _ShareCheckPageState extends State<ShareCheckPage> {
  final SafeBrowsingClient _client = SafeBrowsingClient();
  StreamSubscription<List<SharedMediaFile>>? _mediaStreamSubscription;
  final List<MessageCheckItem> _items = [];
  int _activeChecks = 0;
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _showSettings = false;

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
    final List<SharedMediaFile> initialMedia =
        await ReceiveSharingIntent.instance.getInitialMedia();
    final String? initialText = _extractText(initialMedia);
    if (initialText != null && initialText.isNotEmpty) {
      _handleSharedText(initialText);
    }
    _mediaStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((media) {
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
      ),
      MessageCheckItem(
        id: '${baseId}_sample_warn',
        snippet: '예시 메시지: 계정 확인이 필요합니다',
        fullText: '예시 메시지: 계정 확인이 필요합니다',
        url: 'http://example.com/login',
        status: CheckStatus.pending,
      ),
      MessageCheckItem(
        id: '${baseId}_sample_danger',
        snippet: '예시 메시지: 긴급 보안 업데이트 필요',
        fullText: '예시 메시지: 긴급 보안 업데이트 필요',
        url: 'http://phishing.example.com',
        status: CheckStatus.unsafe,
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
          _updateItem(
            target.id,
            status: CheckStatus.missingKey,
          );
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
    _showSettings = _selectedIndex == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showSettings ? '설정' : '검사 기록'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: '검사 기록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _showSettings
                ? _buildSettings(context)
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
                          if (isChecking)
                            const CircularProgressIndicator(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: hasItems
                            ? ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 20),
                                itemBuilder: (context, index) =>
                                    _buildSlidableRow(
                                      context,
                                      _items[index],
                                    ),
                              )
                            : _buildEmptyState(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '계정',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _confirmLogout,
            child: const Text('로그아웃'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '앱에서 로그아웃하시겠습니까?',
            style: TextStyle(fontSize: 18),
          ),
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
    if (result == true) {
      await widget.onLogout();
    }
  }

  Widget _buildMessageRow(BuildContext context, MessageCheckItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessageDetailPage(item: item),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.riskColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.riskColor.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: item.riskColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: item.riskColor.withOpacity(0.4)),
              ),
              child: Text(
                item.riskLabel,
                style: TextStyle(
                  color: item.riskColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlidableRow(BuildContext context, MessageCheckItem item) {
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
      child: _buildMessageRow(context, item),
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
  }) {
    final int index = _items.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    _items[index] = _items[index].copyWith(
      status: status,
      threatType: threatType,
      details: details,
    );
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

enum CheckStatus { pending, safe, unsafe, error, missingKey }

class MessageCheckItem {
  MessageCheckItem({
    required this.id,
    required this.snippet,
    required this.fullText,
    required this.url,
    required this.status,
    this.threatType,
    this.details,
  });

  final String id;
  final String snippet;
  final String fullText;
  final String url;
  final CheckStatus status;
  final String? threatType;
  final String? details;

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
  }) {
    return MessageCheckItem(
      id: id,
      snippet: snippet,
      fullText: fullText,
      url: url,
      status: status ?? this.status,
      threatType: threatType ?? this.threatType,
      details: details ?? this.details,
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
    };
  }

  factory MessageCheckItem.fromJson(Map<String, dynamic> json) {
    return MessageCheckItem(
      id: json['id'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      fullText: json['fullText'] as String? ??
          (json['snippet'] as String? ?? ''),
      url: json['url'] as String? ?? '',
      status: CheckStatus.values[(json['status'] as int?) ?? 0],
      threatType: json['threatType'] as String?,
      details: json['details'] as String?,
    );
  }
}

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
        return threatType != null
            ? '위험 감지: $threatType'
            : '위험 신호가 감지되었습니다.';
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
      'client': {
        'clientId': 'seogodong',
        'clientVersion': '1.0.0',
      },
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
          {'url': url}
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

    final Map<String, dynamic> first =
        matches.first as Map<String, dynamic>;
    final String? threatType = first['threatType'] as String?;
    return UrlCheckItem(
      url: url,
      status: CheckStatus.unsafe,
      threatType: threatType,
    );
  }
}

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
  if (trimmed.startsWith('www.')) {
    return 'https://$trimmed';
  }
  return 'https://$trimmed';
}

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({super.key, required this.item});

  final MessageCheckItem item;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final http.Client _httpClient = http.Client();
  bool _messageExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 상세'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildHeader(context);
                }
                final ChatMessage message = _messages[index - 1];
                return _buildChatBubble(message);
              },
            ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final MessageCheckItem item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('메시지 내용'),
        const SizedBox(height: 8),
        _buildMessageContent(item.fullText),
        const SizedBox(height: 20),
        _sectionLabel('메시지에서 분석한 링크'),
        const SizedBox(height: 8),
        _sectionBody(item.url),
        const SizedBox(height: 20),
        _sectionLabel('분석 결과'),
        const SizedBox(height: 8),
        Text(
          item.riskLabel,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: item.riskColor,
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('분석 설명'),
        const SizedBox(height: 8),
        _sectionBody(item.riskDescription),
        const SizedBox(height: 24),
        _sectionLabel('질문하기'),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _sectionBody(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16),
    );
  }

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

  Widget _buildChatBubble(ChatMessage message) {
    final bool isUser = message.isUser;
    final Alignment alignment =
        isUser ? Alignment.centerRight : Alignment.centerLeft;
    final Color bubbleColor =
        isUser ? Colors.teal.shade100 : Colors.grey.shade200;
    final BorderRadius borderRadius = BorderRadius.circular(16).copyWith(
      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
    );
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: const InputDecoration(
                  hintText: '질문을 입력하세요',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _handleSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSend() {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(const ChatMessage(text: '', isUser: false));
    });
    final int assistantIndex = _messages.length - 1;
    _controller.clear();
    _focusNode.requestFocus();
    _startSseStream(assistantIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _startSseStream(int assistantIndex) async {
    if (sseBaseUrl.isEmpty) {
      _replaceMessage(assistantIndex, 'Server not connected');
      return;
    }
    final Uri endpoint = Uri.parse(sseBaseUrl)
        .resolve('v1/explain/uuid/stream');
    try {
      final firebase_auth.User? user =
          firebase_auth.FirebaseAuth.instance.currentUser;
      final String? idToken = await user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        _replaceMessage(assistantIndex, '로그인이 필요합니다.');
        return;
      }
      final http.Request request = http.Request('GET', endpoint);
      request.headers['Authorization'] = 'Bearer $idToken';
      final http.StreamedResponse response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        _replaceMessage(
          assistantIndex,
          'Server not connected (${response.statusCode})',
        );
        return;
      }
      String currentEvent = '';
      await for (final String line
          in response.stream.transform(utf8.decoder).transform(
                const LineSplitter(),
              )) {
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
          _appendToMessage(assistantIndex, text);
        } else if (currentEvent == 'done') {
          return;
        }
      }
    } catch (error) {
      _replaceMessage(assistantIndex, 'Server not connected');
    }
  }

  void _appendToMessage(int index, String text) {
    if (text.isEmpty || index >= _messages.length) {
      return;
    }
    setState(() {
      final ChatMessage current = _messages[index];
      _messages[index] = ChatMessage(
        text: '${current.text}$text',
        isUser: current.isUser,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _replaceMessage(int index, String text) {
    if (index >= _messages.length) {
      return;
    }
    setState(() {
      _messages[index] = ChatMessage(text: text, isUser: false);
    });
  }
}

class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
