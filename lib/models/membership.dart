import 'package:cloud_firestore/cloud_firestore.dart';

class Membership {
  Membership({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.role,
    required this.balance,
    required this.joinedAt,
    required this.pending,
    required this.lastStatementAt,
    required this.monthlySummary,
    required this.canManageBank,
    required this.balanceVisible,
  });

  final String id;
  final String communityId;
  final String userId;
  final String role; // owner / admin / member / mediator
  final num balance;
  final DateTime? joinedAt;
  final bool pending;
  final DateTime? lastStatementAt;
  final Map<String, dynamic> monthlySummary;
  final bool canManageBank;
  final bool balanceVisible;

  factory Membership.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return Membership.fromMap(id: snap.id, data: data);
  }

  factory Membership.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    return Membership(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      userId: (data['uid'] as String?) ?? '',
      role: (data['role'] as String?) ?? 'member',
      balance: (data['balance'] as num?) ?? 0,
      joinedAt: _toDate(data['joinedAt']),
      pending: data['pending'] == true,
      lastStatementAt: _toDate(data['lastStatementAt']),
      monthlySummary: Map<String, dynamic>.from(
          (data['monthlySummary'] as Map?) ?? const {}),
      canManageBank: data['canManageBank'] == true,
      balanceVisible: data['balanceVisible'] == true,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'uid': userId,
      'role': role,
      'balance': balance,
      'joinedAt': joinedAt == null ? null : Timestamp.fromDate(joinedAt!),
      'pending': pending,
      'lastStatementAt':
          lastStatementAt == null ? null : Timestamp.fromDate(lastStatementAt!),
      'monthlySummary': monthlySummary,
      'canManageBank': canManageBank,
      'balanceVisible': balanceVisible,
    };
  }

  Membership copyWith({
    String? role,
    num? balance,
    DateTime? joinedAt,
    bool? pending,
    DateTime? lastStatementAt,
    Map<String, dynamic>? monthlySummary,
    bool? canManageBank,
    bool? balanceVisible,
  }) {
    return Membership(
      id: id,
      communityId: communityId,
      userId: userId,
      role: role ?? this.role,
      balance: balance ?? this.balance,
      joinedAt: joinedAt ?? this.joinedAt,
      pending: pending ?? this.pending,
      lastStatementAt: lastStatementAt ?? this.lastStatementAt,
      monthlySummary: monthlySummary ?? this.monthlySummary,
      canManageBank: canManageBank ?? this.canManageBank,
      balanceVisible: balanceVisible ?? this.balanceVisible,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
