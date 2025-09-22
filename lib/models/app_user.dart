import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore `users/{uid}` document representation.
class AppUser {
  AppUser({
    required this.id,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    required this.communityIds,
    required this.dateOfBirth,
    required this.trustScore,
    required this.completionRate,
    required this.disputeRate,
    required this.lastScoreCalculatedAt,
    required this.minor,
  });

  final String id;
  final String displayName;
  final String? photoUrl;
  final String role;
  final List<String> communityIds;
  final DateTime? dateOfBirth;
  final double trustScore;
  final double completionRate;
  final double disputeRate;
  final DateTime? lastScoreCalculatedAt;
  final bool minor;

  factory AppUser.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return AppUser.fromMap(snap.id, data);
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    return AppUser(
      id: id,
      displayName: (data['displayName'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim(),
      role: (data['role'] as String?) ?? 'member',
      communityIds:
          List<String>.from((data['communityIds'] as List?) ?? const []),
      dateOfBirth: _toDate(data['dob']),
      trustScore: _toDouble(data['score']?['trust']),
      completionRate: _toDouble(data['score']?['completionRate']),
      disputeRate: _toDouble(data['score']?['disputeRate']),
      lastScoreCalculatedAt: _toDate(data['score']?['lastCalcAt']),
      minor: data['minor'] == true,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role,
      'communityIds': communityIds,
      'dob': dateOfBirth == null ? null : Timestamp.fromDate(dateOfBirth!),
      'minor': minor,
      'score': {
        'trust': trustScore,
        'completionRate': completionRate,
        'disputeRate': disputeRate,
        'lastCalcAt': lastScoreCalculatedAt == null
            ? null
            : Timestamp.fromDate(lastScoreCalculatedAt!),
      },
    };
  }

  AppUser copyWith({
    String? displayName,
    String? photoUrl,
    String? role,
    List<String>? communityIds,
    DateTime? dateOfBirth,
    double? trustScore,
    double? completionRate,
    double? disputeRate,
    DateTime? lastScoreCalculatedAt,
    bool? minor,
  }) {
    return AppUser(
      id: id,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      communityIds: communityIds ?? this.communityIds,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      trustScore: trustScore ?? this.trustScore,
      completionRate: completionRate ?? this.completionRate,
      disputeRate: disputeRate ?? this.disputeRate,
      lastScoreCalculatedAt:
          lastScoreCalculatedAt ?? this.lastScoreCalculatedAt,
      minor: minor ?? this.minor,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      // Assume seconds since epoch when int.
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return 0;
  }
}
