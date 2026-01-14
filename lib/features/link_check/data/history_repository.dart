import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';

class HistoryRepository {
  static const String _storageKey = 'history';

  // Singleton instance
  static final HistoryRepository _instance = HistoryRepository._internal();
  factory HistoryRepository() => _instance;
  HistoryRepository._internal();

  Future<List<MessageCheckItem>> getAllItems() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> rawItems = prefs.getStringList(_storageKey) ?? [];

    // Forced update / Seeding logic could reside here or in a separate seeding manager.
    // For now, let's keep it clean: simple fetch. The seeding logic in HistoryPage might be moved here later
    // or kept as a UI-side "demo data" seeding.
    // Ideally, for this demo app, we can put seeding here.

    if (rawItems.length <= 3) {
      // Auto-seed if empty or small (demo purpose)
      await _seedSamples(prefs);
      return _itemsFromPrefs(prefs);
    }

    return _itemsFromPrefs(prefs);
  }

  Future<void> addItem(MessageCheckItem item) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<MessageCheckItem> currentItems = await getAllItems();

    // Check if ID exists (though rare for new items)
    final index = currentItems.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      currentItems[index] = item;
    } else {
      currentItems.insert(0, item); // Add to top
    }

    await _saveAll(prefs, currentItems);
  }

  Future<void> updateItem(MessageCheckItem item) async {
    await addItem(item); // Same logic
  }

  Future<void> removeItem(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<MessageCheckItem> currentItems = await getAllItems();

    currentItems.removeWhere((item) => item.id == id);
    await _saveAll(prefs, currentItems);
  }

  Future<void> _saveAll(
    SharedPreferences prefs,
    List<MessageCheckItem> items,
  ) async {
    final List<String> rawItems = items
        .map((item) => jsonEncode(item.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_storageKey, rawItems);
  }

  List<MessageCheckItem> _itemsFromPrefs(SharedPreferences prefs) {
    final List<String> rawItems = prefs.getStringList(_storageKey) ?? [];
    final List<MessageCheckItem> loaded = [];
    for (final raw in rawItems) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(raw) as Map<String, dynamic>;
        loaded.add(MessageCheckItem.fromJson(json));
      } catch (_) {}
    }
    return loaded;
  }

  Future<void> _seedSamples(SharedPreferences prefs) async {
    final int baseId = DateTime.now().microsecondsSinceEpoch;
    final samples = [
      MessageCheckItem(
        id: '${baseId}_safe_1',
        snippet: '택배 배송 조회: 고객님의 상품이 배송중입니다.',
        fullText:
            '택배 배송 조회: 고객님의 상품이 배송중입니다. 배송조회: https://safe-delivery.com/track',
        url: 'https://safe-delivery.com/track',
        status: CheckStatus.safe,
        analysisStatus: 'DONE',
        riskScore: 5,
        searchId: 'uuid',
        llmSummary: null,
      ),
      MessageCheckItem(
        id: '${baseId}_danger_1',
        snippet: '긴급: 보안 승인이 필요합니다. 즉시 확인하세요.',
        fullText: '긴급: 보안 승인이 필요합니다. 즉시 확인하세요. http://phishing-bank-login.com',
        url: 'http://phishing-bank-login.com',
        status: CheckStatus.unsafe,
        analysisStatus: 'DONE',
        riskScore: 92,
        searchId: 'uuid',
        llmSummary: null,
      ),
      MessageCheckItem(
        id: '${baseId}_warning_1',
        snippet: '무료 쿠폰 당첨! 지금 바로 수령하세요.',
        fullText: '무료 쿠폰 당첨! 지금 바로 수령하세요. http://unknown-promo.xyz',
        url: 'http://unknown-promo.xyz',
        status: CheckStatus.pending,
        analysisStatus: 'PENDING',
        riskScore: 45,
        llmSummary: '분석이 진행 중입니다. 출처가 불분명하니 주의하세요.',
      ),
      MessageCheckItem(
        id: '${baseId}_analyzing',
        snippet: '친구 초대 이벤트, 5000포인트 증정',
        fullText: '친구 초대 이벤트, 5000포인트 증정 https://invite-friend.event',
        url: 'https://invite-friend.event',
        status: CheckStatus.safe,
        analysisStatus: 'PENDING',
        riskScore: 10,
        llmSummary: null,
      ),
      MessageCheckItem(
        id: '${baseId}_error',
        snippet: '알 수 없는 링크가 포함된 메시지',
        fullText: '알 수 없는 링크가 포함된 메시지 https://broken-link.com',
        url: 'https://broken-link.com',
        status: CheckStatus.error,
        details: '접속 불가: 서버 응답 없음',
        riskScore: 0,
        llmSummary: '링크에 접속할 수 없어 분석할 수 없습니다.',
      ),
    ];
    await _saveAll(prefs, samples);
  }
}
