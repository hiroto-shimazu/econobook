import 'package:cloud_firestore/cloud_firestore.dart';

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.communityId,
    required this.type,
    required this.fromUid,
    required this.toUid,
    required this.amount,
    required this.memo,
    required this.status,
    required this.lines,
    required this.createdBy,
    required this.createdAt,
    required this.postedAt,
    required this.idempotencyKey,
    required this.linkedRequestId,
    required this.linkedTaskId,
    required this.splitGroupId,
    required this.visibility,
  });

  final String id;
  final String communityId;
  final String type; // transfer | request | split | task | adjustment
  final String? fromUid;
  final String? toUid;
  final num amount;
  final String? memo;
  final String status; // pending | posted | reversed
  final List<LedgerLine> lines;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? postedAt;
  final String? idempotencyKey;
  final String? linkedRequestId;
  final String? linkedTaskId;
  final String? splitGroupId;
  final String visibility; // self | community | public

  factory LedgerEntry.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return LedgerEntry.fromMap(id: snap.id, data: data);
  }

  factory LedgerEntry.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    final lines = (data['lines'] as List?) ?? const [];
    return LedgerEntry(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'transfer',
      fromUid: data['fromUid'] as String?,
      toUid: data['toUid'] as String?,
      amount: (data['amount'] as num?) ?? 0,
      memo: (data['memo'] as String?)?.trim(),
      status: (data['status'] as String?) ?? 'pending',
      lines: [
        for (final l in lines)
          if (l is Map<String, dynamic>)
            LedgerLine.fromMap(Map<String, dynamic>.from(l))
      ],
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: _toDate(data['createdAt']),
      postedAt: _toDate(data['postedAt']),
      idempotencyKey: (data['idempotencyKey'] as String?)?.trim(),
      linkedRequestId: (data['requestRef'] as String?)?.trim(),
      linkedTaskId: (data['taskRef'] as String?)?.trim(),
      splitGroupId: (data['splitGroupId'] as String?)?.trim(),
      visibility: (data['visibility'] as String?) ?? 'community',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'type': type,
      'fromUid': fromUid,
      'toUid': toUid,
      'amount': amount,
      'memo': memo,
      'status': status,
      'lines': [for (final l in lines) l.toMap()],
      'createdBy': createdBy,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'postedAt': postedAt == null ? null : Timestamp.fromDate(postedAt!),
      'idempotencyKey': idempotencyKey,
      'requestRef': linkedRequestId,
      'taskRef': linkedTaskId,
      'splitGroupId': splitGroupId,
      'visibility': visibility,
    };
  }
}

class LedgerLine {
  const LedgerLine(
      {required this.uid, required this.delta, required this.role});

  final String uid;
  final num delta;
  final String role; // debit | credit

  factory LedgerLine.fromMap(Map<String, dynamic> map) {
    return LedgerLine(
      uid: (map['uid'] as String?) ?? '',
      delta: (map['delta'] as num?) ?? 0,
      role: (map['role'] as String?) ??
          ((map['delta'] as num? ?? 0) >= 0 ? 'credit' : 'debit'),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'delta': delta,
      'role': role,
    };
  }
}

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
