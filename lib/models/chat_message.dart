import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatMessageType {
  text,
  transfer,
  request,
  split,
  task,
  system,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.communityId,
    required this.threadId,
    required this.type,
    required this.senderUid,
    required this.receiverUid,
    required this.createdAt,
    this.text,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.unmodifiable(metadata);

  final String id;
  final String communityId;
  final String threadId;
  final ChatMessageType type;
  final String senderUid;
  final String receiverUid;
  final DateTime? createdAt;
  final String? text;
  final Map<String, dynamic> metadata;

  bool get isText => type == ChatMessageType.text;
  bool get isTransfer => type == ChatMessageType.transfer;
  bool get isRequest => type == ChatMessageType.request;
  bool get isSplit => type == ChatMessageType.split;
  bool get isTask => type == ChatMessageType.task;
  bool get isSystem => type == ChatMessageType.system;

  num? get amount {
    final value = metadata['amount'];
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  String? get currencyCode {
    final value = metadata['currency'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  String? get memo {
    final value = metadata['memo'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  String? get ledgerEntryId {
    final value = metadata['ledgerEntryId'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  String? get requestId {
    final value = metadata['requestId'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  String? get taskId {
    final value = metadata['taskId'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  String? get status {
    final value = metadata['status'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  factory ChatMessage.fromSnapshot({
    required String communityId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
  }) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ChatMessage.fromMap(
      id: snapshot.id,
      communityId: communityId,
      threadId: threadId,
      data: data,
    );
  }

  factory ChatMessage.fromMap({
    required String id,
    required String communityId,
    required String threadId,
    required Map<String, dynamic> data,
  }) {
    return ChatMessage(
      id: id,
      communityId: communityId,
      threadId: threadId,
      type: _parseType(data['type'] as String?),
      senderUid: (data['senderUid'] as String?) ?? '',
      receiverUid: (data['receiverUid'] as String?) ?? '',
      createdAt: _toDate(data['createdAt']),
      text: (data['text'] as String?)?.trim(),
      metadata: Map<String, dynamic>.from(
        (data['metadata'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'text': text,
      'senderUid': senderUid,
      'receiverUid': receiverUid,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'metadata': metadata,
    };
  }

  static ChatMessageType _parseType(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'transfer':
        return ChatMessageType.transfer;
      case 'request':
        return ChatMessageType.request;
      case 'split':
        return ChatMessageType.split;
      case 'task':
        return ChatMessageType.task;
      case 'system':
        return ChatMessageType.system;
      default:
        return ChatMessageType.text;
    }
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
