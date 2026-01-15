import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/core/config/constants.dart';
import 'package:seogodong/features/link_check/data/history_repository.dart';
import 'package:seogodong/features/link_check/domain/check_status.dart';
import 'package:seogodong/features/link_check/domain/message_check_item.dart';

class PendingPollingService {
  PendingPollingService._internal();

  static final PendingPollingService _instance =
      PendingPollingService._internal();

  factory PendingPollingService() => _instance;

  Timer? _timer;
  bool _isRunning = false;

  void start() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollPendingItems();
    });
    _pollPendingItems();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _pollPendingItems() async {
    if (_isRunning) {
      return;
    }
    _isRunning = true;
    try {
      if (searchServerBaseUrl.isEmpty) {
        return;
      }
      final firebase_auth.User? user =
          firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }
      final String? idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return;
      }
      final List<MessageCheckItem> items =
          await HistoryRepository().getAllItems();
      final List<MessageCheckItem> pending = items
          .where(
            (item) =>
                item.status == CheckStatus.safe &&
                item.analysisStatus == 'PENDING',
          )
          .toList(growable: false);
      if (pending.isEmpty) {
        return;
      }
      final Uri endpoint = Uri.parse(
        searchServerBaseUrl,
      ).resolve('api/whitelist/check');
      for (final item in pending) {
        await _pollSingle(
          endpoint: endpoint,
          idToken: idToken,
          userId: user.uid,
          item: item,
        );
      }
    } catch (e) {
      debugPrint('SearchServer: Background polling failed $e');
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _pollSingle({
    required Uri endpoint,
    required String idToken,
    required String userId,
    required MessageCheckItem item,
  }) async {
    final Map<String, dynamic> payload = {
      'userId': userId,
      'originalUrl': item.url,
    };
    final http.Response response = await http.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      return;
    }
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final Map<String, dynamic>? data = body['data'] as Map<String, dynamic>?;
    final Map<String, dynamic> source = data ?? body;
    final String? status = source['status'] as String?;
    final MessageCheckItem updated = item.copyWith(
      searchId: (source['result_id'] ?? source['id'])?.toString(),
      analysisStatus: status,
      riskScore: source['riskScore'] as int?,
      finalUrl: source['finalUrl'] as String?,
      messageText: source['messageText'] as String?,
      screenshotPath: source['screenshotPath'] as String?,
      llmSummary: source['llmSummary'] as String?,
      detailsJson: source['details'] as String?,
    );
    await HistoryRepository().updateItem(updated);
  }
}
