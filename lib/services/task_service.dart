import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community_task.dart';
import 'firestore_refs.dart';
import 'ledger_service.dart';

class TaskService {
  TaskService({FirebaseFirestore? firestore, LedgerService? ledgerService})
      : refs = FirestoreRefs(firestore ?? FirebaseFirestore.instance),
        ledger = ledgerService ?? LedgerService(firestore: firestore);

  final FirestoreRefs refs;
  final LedgerService ledger;

  Future<CommunityTask> createTask({
    required String communityId,
    required String title,
    String? description,
    required num reward,
    DateTime? deadline,
    required String createdBy,
    String visibility = 'community',
  }) async {
    if (reward <= 0) {
      throw ArgumentError('reward must be positive');
    }

    await refs.membershipDoc(communityId, createdBy).get().then((value) {
      if (!value.exists) throw StateError('Creator is not a member');
    });

    final mapRef = refs.tasksRaw(communityId).doc();
    await mapRef.set({
      'cid': communityId,
      'title': title,
      'desc': description,
      'reward': reward,
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline),
      'status': 'open',
      'assigneeUid': null,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'visibility': visibility,
    });
    final typedSnap = await refs.tasks(communityId).doc(mapRef.id).get();
    final task = typedSnap.data();
    if (task == null) throw StateError('Task creation failed');
    return task;
  }

  Future<void> assignTask({
    required String communityId,
    required String taskId,
    required String assigneeUid,
    required String assignedBy,
  }) async {
    final taskRef = refs.tasks(communityId).doc(taskId);
    await refs.raw.runTransaction((tx) async {
      final snap = await tx.get(taskRef);
      if (!snap.exists) {
        throw StateError('Task not found');
      }
      final data = snap.data()!;
      if (data.status != 'open') {
        throw StateError('Task is not open for assignment');
      }
      await refs.membershipDoc(communityId, assigneeUid).get().then((value) {
        if (!value.exists) {
          throw StateError('Assignee is not a member');
        }
      });
      tx.update(taskRef, {
        'status': 'taken',
        'assigneeUid': assigneeUid,
        'assignedBy': assignedBy,
        'assignedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> submitTaskProof({
    required String communityId,
    required String taskId,
    required String assigneeUid,
    String? proofUrl,
  }) async {
    final taskRef = refs.tasks(communityId).doc(taskId);
    await refs.raw.runTransaction((tx) async {
      final snap = await tx.get(taskRef);
      if (!snap.exists) throw StateError('Task not found');
      final data = snap.data()!;
      if (data.assigneeUid != assigneeUid) {
        throw StateError('Only the assigned user can submit');
      }
      if (data.status != 'taken') {
        throw StateError('Task is not ready for submission');
      }
      tx.update(taskRef, {
        'status': 'submitted',
        'proofUrl': proofUrl,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> approveTask({
    required String communityId,
    required String taskId,
    required String approvedBy,
    String? memo,
  }) async {
    final taskRef = refs.tasks(communityId).doc(taskId);
    CommunityTask? task;

    await refs.raw.runTransaction((tx) async {
      final snap = await tx.get(taskRef);
      if (!snap.exists) throw StateError('Task not found');
      final data = snap.data()!;
      if (data.status != 'submitted') {
        throw StateError('Task is not submitted');
      }
      task = data;
      tx.update(taskRef, {
        'status': 'approved',
        'approvedBy': approvedBy,
        'approvedAt': FieldValue.serverTimestamp(),
      });
    });

    if (task == null) return;
    final assigneeUid = task!.assigneeUid;
    if (assigneeUid == null) {
      throw StateError('Task has no assignee');
    }

    await ledger.recordTransfer(
      communityId: communityId,
      fromUid: task!.createdBy,
      toUid: assigneeUid,
      amount: task!.reward,
      memo: memo ?? 'Task "${task!.title}" approved',
      createdBy: approvedBy,
      idempotencyKey: 'task_$taskId',
      visibility: task!.visibility,
      taskId: taskId,
    );
  }

  Future<void> rejectTask({
    required String communityId,
    required String taskId,
    required String rejectedBy,
    String? reason,
  }) async {
    final taskRef = refs.tasks(communityId).doc(taskId);
    await refs.raw.runTransaction((tx) async {
      final snap = await tx.get(taskRef);
      if (!snap.exists) throw StateError('Task not found');
      final data = snap.data()!;
      if (data.status != 'submitted') {
        throw StateError('Task has not been submitted');
      }
      tx.update(taskRef, {
        'status': 'rejected',
        'rejectedBy': rejectedBy,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
      });
    });
  }
}
