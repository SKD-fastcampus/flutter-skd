import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:seogodong/features/link_check/data/history_repository.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';
import 'package:seogodong/features/link_check/presentation/widgets/message_card.dart';
import 'package:seogodong/features/link_check/presentation/message_detail_page.dart';

class ShareCheckPage extends StatefulWidget {
  const ShareCheckPage({super.key});

  @override
  State<ShareCheckPage> createState() => _ShareCheckPageState();
}

class _ShareCheckPageState extends State<ShareCheckPage> {
  final List<MessageCheckItem> _items = [];
  final Set<String> _selectedIds = {};
  final int _activeChecks = 0;
  bool _isLoading = true;
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasItems = _items.isNotEmpty;
    final bool isChecking = _activeChecks > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('검사 기록'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _buildSlidableRow(context, _items[index]),
                          )
                        : _buildEmptyState(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSlidableRow(BuildContext context, MessageCheckItem item) {
    if (_selectionMode) {
      return MessageCard(
        item: item,
        selected: _selectedIds.contains(item.id),
        selectionMode: _selectionMode,
        onTap: () {
          _toggleSelection(item.id);
        },
        onLongPress: () {
          _toggleSelection(item.id, forceOn: true);
        },
      );
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
      child: MessageCard(
        item: item,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MessageDetailPage(
                item: item,
                onSummaryUpdate: (summary) async {
                  _updateItem(item.id, llmSummary: summary);
                },
              ),
            ),
          );
        },
        onLongPress: () {
          _toggleSelection(item.id, forceOn: true);
        },
      ),
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
    HistoryRepository().updateItem(_items[index]);
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

  Future<void> _removeItem(String id) async {
    await HistoryRepository().removeItem(id);
    _loadItems();
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

  void _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    // Delete from repo
    for (final id in _selectedIds) {
      HistoryRepository().removeItem(id);
    }
    setState(() {
      _items.removeWhere((item) => _selectedIds.contains(item.id));
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });
    final items = await HistoryRepository().getAllItems();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
      _isLoading = false;
    });
  }
}
