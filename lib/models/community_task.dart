import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityTask {
  CommunityTask({
    required this.id,
    required this.communityId,
    required this.title,
    required this.description,
    required this.reward,
    required this.deadline,
    required this.status,
    required this.assigneeUid,
    required this.createdBy,
    required this.createdAt,
    required this.proofUrl,
    required this.visibility,
  });

  final String id;
  final String communityId;
  final String title;
  final String? description;
  final num reward;
  final DateTime? deadline;
  final String
      status; // open | taken | submitted | approved | rejected | cancelled
  final String? assigneeUid;
  final String createdBy;
  final DateTime? createdAt;
  final String? proofUrl;
  final String visibility; // self | community | public

  factory CommunityTask.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return CommunityTask.fromMap(id: snap.id, data: data);
  }

  factory CommunityTask.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    return CommunityTask(
      id: id,
      communityId: (data['cid'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: (data['desc'] as String?)?.trim(),
      reward: (data['reward'] as num?) ?? 0,
      deadline: _toDate(data['deadline']),
      status: (data['status'] as String?) ?? 'open',
      assigneeUid: (data['assigneeUid'] as String?)?.trim(),
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: _toDate(data['createdAt']),
      proofUrl: (data['proofUrl'] as String?)?.trim(),
      visibility: (data['visibility'] as String?) ?? 'community',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'cid': communityId,
      'title': title,
      'desc': description,
      'reward': reward,
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
      'status': status,
      'assigneeUid': assigneeUid,
      'createdBy': createdBy,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'proofUrl': proofUrl,
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
