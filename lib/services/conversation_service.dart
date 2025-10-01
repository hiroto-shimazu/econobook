import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/chat_service.dart';
import '../services/firestore_refs.dart';
import '../services/ledger_service.dart';
import '../services/request_service.dart';
import '../services/task_service.dart';

class ConversationService {
  ConversationService({
    FirebaseFirestore? firestore,
    ChatService? chatService,
    LedgerService? ledgerService,
    RequestService? requestService,
    TaskService? taskService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _chatService = chatService ?? ChatService(firestore: firestore),
        _ledgerService = ledgerService ?? LedgerService(firestore: firestore),
        _refs = FirestoreRefs(firestore ?? FirebaseFirestore.instance) {
    _requestService = requestService ??
        RequestService(
          firestore: firestore,
          ledgerService: _ledgerService,
        );
    _taskService = taskService ??
        TaskService(
          firestore: firestore,
          ledgerService: _ledgerService,
        );
  }

  final FirebaseFirestore _firestore;
  final ChatService _chatService;
  final LedgerService _ledgerService;
  late final RequestService _requestService;
  late final TaskService _taskService;
  final FirestoreRefs _refs;

  ChatService get chat => _chatService;

  Stream<List<ChatMessage>> messageStream({
    required String communityId,
    required String threadId,
  }) {
    return _firestore
        .collection('community_chats')
        .doc(communityId)
        .collection('threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ChatMessage.fromSnapshot(
                  communityId: communityId,
                  threadId: threadId,
                  snapshot: doc,
                ),
              )
              .toList(growable: false),
        );
  }

  Future<ConversationSummary> loadMonthlySummary({
    required String communityId,
    required String currentUid,
    required String partnerUid,
    required String currencyCode,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final startOfMonth = DateTime(clock.year, clock.month, 1);
    final timestamp = Timestamp.fromDate(startOfMonth);

    final entries = await Future.wait([
      _refs
          .ledgerEntries(communityId)
          .where('fromUid', isEqualTo: currentUid)
          .where('toUid', isEqualTo: partnerUid)
          .where('createdAt', isGreaterThanOrEqualTo: timestamp)
          .get(),
      _refs
          .ledgerEntries(communityId)
          .where('fromUid', isEqualTo: partnerUid)
          .where('toUid', isEqualTo: currentUid)
          .where('createdAt', isGreaterThanOrEqualTo: timestamp)
          .get(),
    ]);

    num outgoing = 0;
    num incoming = 0;
    for (final snap in entries[0].docs) {
      final amount = (snap.data().amount);
      outgoing += amount;
    }
    for (final snap in entries[1].docs) {
      final amount = (snap.data().amount);
      incoming += amount;
    }

    final pendingRequests = await Future.wait([
      _refs
          .paymentRequests(communityId)
          .where('status', isEqualTo: 'pending')
          .where('fromUid', isEqualTo: currentUid)
          .where('toUid', isEqualTo: partnerUid)
          .get(),
      _refs
          .paymentRequests(communityId)
          .where('status', isEqualTo: 'pending')
          .where('fromUid', isEqualTo: partnerUid)
          .where('toUid', isEqualTo: currentUid)
          .get(),
    ]);

    final pendingCount =
        pendingRequests.fold<int>(0, (sum, snap) => sum + snap.docs.length);

    final pendingTasks = await Future.wait([
      _refs
          .tasks(communityId)
          .where('createdBy', isEqualTo: currentUid)
          .where('assigneeUid', isEqualTo: partnerUid)
          .where('status', whereIn: const ['open', 'taken', 'submitted'])
          .get(),
      _refs
          .tasks(communityId)
          .where('createdBy', isEqualTo: partnerUid)
          .where('assigneeUid', isEqualTo: currentUid)
          .where('status', whereIn: const ['open', 'taken', 'submitted'])
          .get(),
    ]);

    final pendingTaskCount =
        pendingTasks.fold<int>(0, (sum, snap) => sum + snap.docs.length);

    final periodLabel = '${clock.year}年${clock.month}月';
    return ConversationSummary(
      incoming: incoming,
      outgoing: outgoing,
      currencyCode: currencyCode,
      pendingRequestCount: pendingCount,
      pendingTaskCount: pendingTaskCount,
      periodLabel: periodLabel,
    );
  }

  Future<void> sendText({
    required String communityId,
    required String senderUid,
    required String receiverUid,
    required String text,
  }) {
    return _chatService.sendMessage(
      communityId: communityId,
      senderUid: senderUid,
      receiverUid: receiverUid,
      message: text,
    );
  }

  Future<void> sendTransfer({
    required String communityId,
    required String senderUid,
    required String receiverUid,
    required num amount,
    required String currencyCode,
    String? memo,
    bool enforceSufficientFunds = false,
  }) async {
    final entry = await _ledgerService.recordTransfer(
      communityId: communityId,
      fromUid: senderUid,
      toUid: receiverUid,
      amount: amount,
      memo: memo,
      createdBy: senderUid,
      enforceSufficientFunds: enforceSufficientFunds,
      visibility: 'community',
    );

    await _chatService.sendTypedMessage(
      communityId: communityId,
      senderUid: senderUid,
      receiverUid: receiverUid,
      type: ChatMessageType.transfer,
      text: memo,
      metadata: {
        'amount': amount,
        'currency': currencyCode,
        'memo': memo,
        'ledgerEntryId': entry.id,
      },
    );
  }

  Future<void> sendRequest({
    required String communityId,
    required String requesterUid,
    required String targetUid,
    required num amount,
    required String currencyCode,
    String? memo,
  }) async {
    final request = await _requestService.createRequest(
      communityId: communityId,
      fromUid: requesterUid,
      toUid: targetUid,
      amount: amount,
      memo: memo,
      createdBy: requesterUid,
    );

    await _chatService.sendTypedMessage(
      communityId: communityId,
      senderUid: requesterUid,
      receiverUid: targetUid,
      type: ChatMessageType.request,
      text: memo,
      metadata: {
        'amount': amount,
        'currency': currencyCode,
        'memo': memo,
        'requestId': request.id,
        'status': request.status,
      },
    );
  }

  Future<void> sendSplitRequest({
    required String communityId,
    required String requesterUid,
    required String targetUid,
    required num totalAmount,
    required String currencyCode,
    String? memo,
  }) async {
    final share = totalAmount / 2;
    final request = await _requestService.createRequest(
      communityId: communityId,
      fromUid: requesterUid,
      toUid: targetUid,
      amount: share,
      memo: memo ?? '割り勘 (${totalAmount.toStringAsFixed(2)})',
      createdBy: requesterUid,
    );

    await _chatService.sendTypedMessage(
      communityId: communityId,
      senderUid: requesterUid,
      receiverUid: targetUid,
      type: ChatMessageType.split,
      text: memo,
      metadata: {
        'amount': share,
        'currency': currencyCode,
        'memo': memo,
        'requestId': request.id,
        'status': request.status,
        'totalAmount': totalAmount,
      },
    );
  }

  Future<void> sendTask({
    required String communityId,
    required String creatorUid,
    required String assigneeUid,
    required String title,
    required num reward,
    required String currencyCode,
    String? description,
  }) async {
    final task = await _taskService.createTask(
      communityId: communityId,
      title: title,
      description: description,
      reward: reward,
      createdBy: creatorUid,
    );

    await _chatService.sendTypedMessage(
      communityId: communityId,
      senderUid: creatorUid,
      receiverUid: assigneeUid,
      type: ChatMessageType.task,
      text: description ?? title,
      metadata: {
        'taskId': task.id,
        'title': title,
        'reward': reward,
        'currency': currencyCode,
        'description': description,
        'status': task.status,
      },
    );
  }
}
