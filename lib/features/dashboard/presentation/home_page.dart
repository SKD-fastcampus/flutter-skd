import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';
import 'package:seogodong/features/authentication/presentation/login_page.dart';
import 'package:seogodong/features/link_check/presentation/message_detail_page.dart';
import 'package:seogodong/features/link_check/presentation/history_page.dart';
import 'package:seogodong/features/link_check/data/history_repository.dart';
import 'package:seogodong/features/settings/presentation/settings_page.dart';
import 'package:seogodong/features/link_check/presentation/widgets/message_card.dart';
import 'package:seogodong/features/link_check/presentation/scanning_page.dart';
import 'package:seogodong/app/route_observer.dart';
import 'package:seogodong/features/link_check/data/pending_polling_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with RouteAware, WidgetsBindingObserver {
  int _selectedIndex = 0;
  final List<MessageCheckItem> _recentItems = [];
  StreamSubscription<List<SharedMediaFile>>? _mediaStreamSubscription;
  final TextEditingController _webInputController = TextEditingController();

  // We reuse logic from ShareCheckPage, but ideally this should be in a Provider
  // For now, we will duplicate/manage state here for the Dashboard view
  // and sync with the full list page.

  @override
  void initState() {
    super.initState();
    _loadRecentItems();
    _setupSharing();
    PendingPollingService().start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _mediaStreamSubscription?.cancel();
    _webInputController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _loadRecentItems();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecentItems();
    }
  }

  Future<void> _setupSharing() async {
    if (kIsWeb) {
      return;
    }
    // 1. Initial share (app closed)
    final List<SharedMediaFile> initialMedia = await ReceiveSharingIntent
        .instance
        .getInitialMedia();
    final String? initialText = _extractText(initialMedia);
    if (initialText != null && initialText.isNotEmpty) {
      _handleSharedText(initialText);
    }

    // 2. Stream share (app open)
    _mediaStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((media) {
          final String? sharedText = _extractText(media);
          if (sharedText != null && sharedText.isNotEmpty) {
            _handleSharedText(sharedText);
          }
        });
  }

  String? _extractText(List<SharedMediaFile> media) {
    if (media.isEmpty) return null;
    final List<String> parts = [];
    for (final item in media) {
      if (item.type == SharedMediaType.text ||
          item.type == SharedMediaType.url) {
        parts.add(item.path);
      } else if (item.message != null && item.message!.isNotEmpty) {
        parts.add(item.message!);
      }
    }
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  void _handleSharedText(String text) {
    // Navigate to scanning page immediately
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanningPage(textToCheck: text)),
    );
  }

  Future<void> _loadRecentItems() async {
    final List<MessageCheckItem> loaded =
        await HistoryRepository().getAllItems();

    if (mounted) {
      setState(() {
        _recentItems.clear();
        _recentItems.addAll(loaded);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine overall status
    // safe, warning, or danger based on the most recent item or aggregated stats
    final CheckStatus overallStatus = _recentItems.isNotEmpty
        ? _recentItems.first.status
        : CheckStatus.safe;

    Widget bodyContent;
    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildDashboard(context, overallStatus);
        break;
      case 1:
        bodyContent = const ShareCheckPage();
        break;
      case 2:
        bodyContent = const SettingsPage();
        break;
      default:
        bodyContent = _buildDashboard(context, overallStatus);
    }

    return Scaffold(
      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            if (index == 0) {
              _loadRecentItems(); // Refresh dashboard when returning home
            }
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: '기록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: '설정',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, CheckStatus status) {
    final bool hasUnreadAlert = _recentItems.any(
      (item) =>
          item.isSearchComplete &&
          !item.isRead &&
          item.status != CheckStatus.safe,
    );
    final bool isSafe = !hasUnreadAlert;
    final Color statusColor = isSafe
        ? Colors.green.shade700
        : Colors.red.shade700;
    final Color bgColor = isSafe ? Colors.green.shade50 : Colors.red.shade50;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Icon(
                    isSafe ? Icons.shield_rounded : Icons.warning_rounded,
                    size: 64,
                    color: statusColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isSafe ? '감지된 위험 링크가 없습니다.' : '위험한 링크를 감지했어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '오늘 검사한 링크: ${_recentItems.length}건',
                    style: TextStyle(
                      color: statusColor.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '웹에서는 공유 기능이 지원되지 않습니다.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webInputController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '검사할 메시지를 붙여넣기',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        final String text = _webInputController.text.trim();
                        if (text.isEmpty) {
                          return;
                        }
                        _webInputController.clear();
                        _handleSharedText(text);
                      },
                      child: const Text('메시지 검사'),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // 2. Action Zone
            const Text(
              '빠른 실행',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: '복사한 문자\n검사하기',
                    icon: Icons.paste_rounded,
                    color: Colors.blue.shade600,
                    onTap: _checkClipboard,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: '검사 방법\n알아보기',
                    icon: Icons.help_outline_rounded,
                    color: Colors.grey.shade700,
                    onTap: _showTutorial,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // 3. Recent History
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '최근 검사 기록',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIndex = 1; // Go to History Tab
                    });
                  },
                  child: const Text('전체보기'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRecentList(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: color),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentList() {
    if (_recentItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            '아직 검사한 기록이 없습니다.\n문자를 복사해서 검사해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Show top 3 items
    return Column(
      children: _recentItems.take(3).map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MessageCard(item: item, onTap: () => _onItemTap(item)),
        );
      }).toList(),
    );
  }

  Future<void> _checkClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final String? text = data?.text;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('클립보드에 복사된 텍스트가 없습니다.')));
      return;
    }
    // Navigate to ScanningPage
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanningPage(textToCheck: text)),
    );
  }

  void _showTutorial() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('검사 방법'),
        content: const Text(
          '1. 문자나 카카오톡에서 의심되는 메시지를 꾹 누르세요.\n'
          '2. "공유" 버튼을 찾아서 누르세요.\n'
          '3. 앱 목록에서 "게섯거라"를 선택하세요.\n\n'
          '또는 메시지를 복사한 후 앱에서 "복사한 문자 검사하기"를 누르세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _onItemTap(MessageCheckItem item) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Show Login Modal
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('로그인이 필요합니다'),
          content: const Text('AI 정밀 분석 결과를 보려면 로그인이 필요합니다.\n로그인 하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LoginPage(
                      onLoginSuccess: () async {
                        Navigator.pop(context); // Close Login Page
                        // Refresh auth state?
                      },
                    ),
                  ),
                );
              },
              child: const Text('로그인하기'),
            ),
          ],
        ),
      );
    } else {
      _markItemRead(item);
      // Go to detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            item: item,
            onSummaryUpdate: (summary) async {
              // Stub for now, logic needs to be connected
            },
          ),
        ),
      );
    }
  }

  Future<void> _markItemRead(MessageCheckItem item) async {
    if (!item.isSearchComplete || item.isRead) {
      return;
    }
    final int index = _recentItems.indexWhere((e) => e.id == item.id);
    if (index == -1) {
      return;
    }
    final MessageCheckItem updated = item.copyWith(isRead: true);
    await HistoryRepository().updateItem(updated);
    if (!mounted) return;
    setState(() {
      _recentItems[index] = updated;
    });
  }
}
