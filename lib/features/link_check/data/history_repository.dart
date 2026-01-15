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

}
