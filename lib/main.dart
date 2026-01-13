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
const String searchServerBaseUrl =
    String.fromEnvironment('SEARCH_SERVER_BASE_URL');
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
              '게섯거라',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 84),
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
            const SizedBox(height: 56),
            RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      height: 3.6,
                    ),
                children: [
                  const TextSpan(text: '😈 메시지에 있는 수상한 링크, '),
                  const TextSpan(
                    text: '게섯거라',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '로 '),
                  const TextSpan(
                    text: '공유',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '하세요\n'),
                  const TextSpan(text: '🔍 '),
                  const TextSpan(
                    text: '게섯거라',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '가 위험한 링크인지 '),
                  const TextSpan(
                    text: '검사',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '해 드려요'),
                ],
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
      _showSnack('카카오 로그인 성공!');
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
  final Set<String> _selectedIds = {};
  int _activeChecks = 0;
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _showSettings = false;
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
    final bool selected = _selectedIds.contains(item.id);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(item.id);
          return;
        }
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.resultColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.black
                : item.resultColor.withOpacity(0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectionMode) ...[
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? Colors.black : Colors.grey.shade500,
              ),
              const SizedBox(width: 12),
            ],
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
                color: item.resultColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: item.resultColor.withOpacity(0.4)),
              ),
              child: Text(
                item.resultLabel,
                style: TextStyle(
                  color: item.resultColor,
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
    if (_selectionMode) {
      return _buildMessageRow(context, item);
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
    final Uri endpoint =
        Uri.parse(searchServerBaseUrl).resolve('api/whitelist/check');
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
          headers: {
            'Authorization': 'Bearer $idToken',
          },
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
      fullText: json['fullText'] as String? ??
          (json['snippet'] as String? ?? ''),
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
          child: Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
          ),
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
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: Radius.zero,
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15),
        ),
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
    final Uri endpoint = Uri.parse(sseBaseUrl)
        .resolve('v1/explain/uuid/stream');
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
