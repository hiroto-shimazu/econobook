import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentRequest {
  PaymentRequest({
    required this.id,
    required this.communityId,
    required this.fromUid,
    required this.toUid,
    required this.amount,
    required this.memo,
    required this.status,
    required this.expireAt,
    required this.createdAt,
    required this.createdBy,
    required this.visibility,
  });

  final String id;
  final String communityId;
  final String fromUid;
  final String toUid;
  final num amount;
  final String? memo;
  final String status; // pending | approved | rejected | cancelled | expired
  final DateTime? expireAt;
  final DateTime? createdAt;
  final String createdBy;
  final String visibility;

  factory PaymentRequest.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return PaymentRequest.fromMap(id: snap.id, data: data);
  }

  factory PaymentRequest.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    return PaymentRequest(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      fromUid: (data['fromUid'] as String?) ?? '',
      toUid: (data['toUid'] as String?) ?? '',
      amount: (data['amount'] as num?) ?? 0,
      memo: (data['memo'] as String?)?.trim(),
      status: (data['status'] as String?) ?? 'pending',
      expireAt: _toDate(data['expireAt']),
      createdAt: _toDate(data['createdAt']),
      createdBy: (data['createdBy'] as String?) ?? '',
      visibility: (data['visibility'] as String?) ?? 'community',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'fromUid': fromUid,
      'toUid': toUid,
      'amount': amount,
      'memo': memo,
      'status': status,
      'expireAt': expireAt == null ? null : Timestamp.fromDate(expireAt!),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'createdBy': createdBy,
      'visibility': visibility,
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
