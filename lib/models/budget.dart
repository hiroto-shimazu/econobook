import 'package:cloud_firestore/cloud_firestore.dart';

class Budget {
  Budget({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.category,
    required this.cap,
    required this.period,
    required this.alerted,
    required this.createdAt,
  });

  final String id;
  final String communityId;
  final String userId;
  final String category;
  final num cap;
  final String period; // monthly | weekly | custom
  final bool alerted;
  final DateTime? createdAt;

  factory Budget.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return Budget.fromMap(id: snap.id, data: data);
  }

  factory Budget.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    return Budget(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      userId: (data['uid'] as String?) ?? '',
      category: (data['category'] as String?) ?? 'general',
      cap: (data['cap'] as num?) ?? 0,
      period: (data['period'] as String?) ?? 'monthly',
      alerted: data['alerted'] == true,
      createdAt: _toDate(data['createdAt']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'uid': userId,
      'category': category,
      'cap': cap,
      'period': period,
      'alerted': alerted,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
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
