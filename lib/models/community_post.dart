import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.communityId,
    required this.category,
    required this.body,
    required this.visibility,
    required this.reports,
    required this.commentsCount,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String communityId;
  final String category; // lesson | trouble | mediator | announcement
  final String body;
  final String visibility; // self | community | public
  final List<String> reports;
  final int commentsCount;
  final String createdBy;
  final DateTime? createdAt;

  factory CommunityPost.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return CommunityPost.fromMap(id: snap.id, data: data);
  }

  factory CommunityPost.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    return CommunityPost(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      category: (data['category'] as String?) ?? 'lesson',
      body: (data['body'] as String?) ?? '',
      visibility: (data['visibility'] as String?) ?? 'community',
      reports: List<String>.from((data['reports'] as List?) ?? const []),
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: _toDate(data['createdAt']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'category': category,
      'body': body,
      'visibility': visibility,
      'reports': reports,
      'commentsCount': commentsCount,
      'createdBy': createdBy,
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
