// lib/dev/dev_users.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Dev mode is enabled only when running in debug AND the
/// --dart-define=USE_DEV_MENU=true flag is provided. This prevents the dev
/// menu from appearing during normal operation on developer machines or CI.
bool get isDev {
  const useDevMenu = bool.fromEnvironment('USE_DEV_MENU', defaultValue: false);
  return kDebugMode && useDevMenu;
}

class DevUserEntry {
  const DevUserEntry({
    required this.uid,
    this.label,
    this.note,
    this.minor,
    this.canManageBank,
    this.isBuiltin = false,
  });

  final String uid;
  final String? label;
  final String? note;
  final bool? minor;
  final bool? canManageBank;
  final bool isBuiltin;

  String get displayLabel => label ?? uid;

  DevUserEntry copyWith({
    String? label,
    String? note,
    bool? minor,
    bool? canManageBank,
    bool? isBuiltin,
  }) {
    return DevUserEntry(
      uid: uid,
      label: label ?? this.label,
      note: note ?? this.note,
      minor: minor ?? this.minor,
      canManageBank: canManageBank ?? this.canManageBank,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }
}

class DevUserState {
  DevUserState({
    required List<DevUserEntry> entries,
    this.activeUid,
    this.lastUsedUid,
  }) : _entries = List<DevUserEntry>.from(entries);

  final List<DevUserEntry> _entries;
  final String? activeUid;
  final String? lastUsedUid;

  List<DevUserEntry> get entries => List<DevUserEntry>.unmodifiable(_entries);

  DevUserState copyWith({
    List<DevUserEntry>? entries,
    String? activeUid,
    bool clearActive = false,
    String? lastUsedUid,
    bool clearLastUsed = false,
  }) {
    final List<DevUserEntry> nextEntries = entries != null
        ? List<DevUserEntry>.from(entries)
        : List<DevUserEntry>.from(_entries);
    return DevUserState(
      entries: nextEntries,
      activeUid: clearActive ? null : (activeUid ?? this.activeUid),
      lastUsedUid: clearLastUsed ? null : (lastUsedUid ?? this.lastUsedUid),
    );
  }
}

const List<DevUserEntry> _builtinDevUsers = <DevUserEntry>[
  DevUserEntry(
    uid: 'dev_alice',
    label: 'dev_alice',
    note: '管理者 / バンク権限',
    canManageBank: true,
    minor: false,
    isBuiltin: true,
  ),
  DevUserEntry(
    uid: 'dev_bob',
    label: 'dev_bob',
    note: '一般メンバー',
    minor: false,
    canManageBank: false,
    isBuiltin: true,
  ),
  DevUserEntry(
    uid: 'dev_minor',
    label: 'dev_minor',
    note: '未成年テスト',
    minor: true,
    canManageBank: false,
    isBuiltin: true,
  ),
];

DevUserState _initialDevUserState() {
  return DevUserState(
    entries: _builtinDevUsers,
    activeUid: _builtinDevUsers.isNotEmpty ? _builtinDevUsers.first.uid : null,
    lastUsedUid:
        _builtinDevUsers.isNotEmpty ? _builtinDevUsers.first.uid : null,
  );
}

class DevUserRegistry {
  DevUserRegistry._()
      : _state = ValueNotifier<DevUserState>(_initialDevUserState());

  static final DevUserRegistry instance = DevUserRegistry._();

  final ValueNotifier<DevUserState> _state;

  DevUserState get state => _state.value;

  ValueListenable<DevUserState> get listenable => _state;

  void _mutate(DevUserState Function(DevUserState current) reducer) {
    _state.value = reducer(_state.value);
  }

  DevUserEntry? entryByUid(String uid) {
    for (final entry in state.entries) {
      if (entry.uid == uid) return entry;
    }
    return null;
  }

  bool canRemove(String uid) {
    final entry = entryByUid(uid);
    if (entry == null) return false;
    return !entry.isBuiltin;
  }

  String defaultUid() {
    final DevUserState current = state;
    final List<DevUserEntry> entries = current.entries;
    if (entries.isEmpty) return '';
    final String? active = _resolveUid(entries, current.activeUid);
    if (active != null) return active;
    final String? last = _resolveUid(entries, current.lastUsedUid);
    if (last != null) return last;
    return entries.first.uid;
  }

  void addOrUpdate(
    DevUserEntry entry, {
    bool activate = false,
    bool remember = false,
  }) {
    _mutate((DevUserState current) {
      final List<DevUserEntry> entries =
          List<DevUserEntry>.from(current.entries);
      final int idx =
          entries.indexWhere((DevUserEntry e) => e.uid == entry.uid);
      if (idx >= 0) {
        final DevUserEntry existing = entries[idx];
        entries[idx] = existing.copyWith(
          label: entry.label ?? existing.label,
          note: entry.note ?? existing.note,
          minor: entry.minor ?? existing.minor,
          canManageBank: entry.canManageBank ?? existing.canManageBank,
          isBuiltin: existing.isBuiltin || entry.isBuiltin,
        );
      } else {
        if (entry.isBuiltin) {
          final int insertion =
              entries.indexWhere((DevUserEntry e) => !e.isBuiltin);
          if (insertion == -1) {
            entries.add(entry);
          } else {
            entries.insert(insertion, entry);
          }
        } else {
          entries.add(entry);
        }
      }
      return current.copyWith(
        entries: entries,
        activeUid: activate ? entry.uid : current.activeUid,
        lastUsedUid: remember ? entry.uid : current.lastUsedUid,
      );
    });
  }

  void select(String uid) {
    final String trimmed = uid.trim();
    if (trimmed.isEmpty) return;
    _mutate((DevUserState current) {
      final List<DevUserEntry> entries =
          List<DevUserEntry>.from(current.entries);
      if (!entries.any((DevUserEntry e) => e.uid == trimmed)) {
        entries.add(DevUserEntry(uid: trimmed));
      }
      return current.copyWith(
        entries: entries,
        activeUid: trimmed,
        lastUsedUid: trimmed,
      );
    });
  }

  void rememberUsage(String uid) {
    final String trimmed = uid.trim();
    if (trimmed.isEmpty) return;
    _mutate((DevUserState current) {
      final List<DevUserEntry> entries =
          List<DevUserEntry>.from(current.entries);
      if (!entries.any((DevUserEntry e) => e.uid == trimmed)) {
        entries.add(DevUserEntry(uid: trimmed));
      }
      return current.copyWith(
        entries: entries,
        lastUsedUid: trimmed,
      );
    });
  }

  void remove(String uid) {
    _mutate((DevUserState current) {
      final List<DevUserEntry> entries =
          List<DevUserEntry>.from(current.entries);
      final int idx = entries.indexWhere((DevUserEntry e) => e.uid == uid);
      if (idx == -1) return current;
      final DevUserEntry target = entries[idx];
      if (target.isBuiltin) return current;
      entries.removeAt(idx);

      String? active = current.activeUid;
      if (active == uid) {
        active = entries.isNotEmpty ? entries.first.uid : null;
      }
      String? last = current.lastUsedUid;
      if (last == uid) {
        last = entries.isNotEmpty ? (active ?? entries.first.uid) : null;
      }
      return current.copyWith(
        entries: entries,
        activeUid: active,
        lastUsedUid: last,
      );
    });
  }

  Future<void> createDevUser({
    required String uid,
    String? label,
    String? note,
    bool minor = false,
    bool canManageBank = false,
    String? communityId,
    bool joinCommunity = true,
  }) async {
    final String trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'UID must not be empty');
    }

    final String? trimmedLabel =
        label != null && label.trim().isNotEmpty ? label.trim() : null;
    final String? trimmedNote =
        note != null && note.trim().isNotEmpty ? note.trim() : null;

    final CollectionReference<Map<String, dynamic>> users =
        FirebaseFirestore.instance.collection('users');
    final Map<String, dynamic> userData = <String, dynamic>{
      'minor': minor,
      'devUser': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (trimmedLabel != null) {
      userData['displayName'] = trimmedLabel;
    }
    await users.doc(trimmedUid).set(userData, SetOptions(merge: true));

    final String? trimmedCommunityId =
        communityId != null && communityId.trim().isNotEmpty
            ? communityId.trim()
            : null;
    if (trimmedCommunityId != null && joinCommunity) {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('memberships')
              .where('communityId', isEqualTo: trimmedCommunityId)
              .where('userId', isEqualTo: trimmedUid)
              .limit(1)
              .get();
      if (snapshot.docs.isEmpty) {
        await FirebaseFirestore.instance
            .collection('memberships')
            .add(<String, dynamic>{
          'cid': trimmedCommunityId,
          'communityId': trimmedCommunityId,
          'userId': trimmedUid,
          'joinedAt': FieldValue.serverTimestamp(),
          'balance': 0,
          'canManageBank': canManageBank,
          'status': 'active',
          'role': canManageBank ? 'admin' : 'member',
          'pending': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    addOrUpdate(
      DevUserEntry(
        uid: trimmedUid,
        label: trimmedLabel,
        note: trimmedNote,
        minor: minor,
        canManageBank: canManageBank,
      ),
      activate: true,
      remember: true,
    );
  }

  String? _resolveUid(List<DevUserEntry> entries, String? candidate) {
    if (candidate == null) return null;
    for (final DevUserEntry entry in entries) {
      if (entry.uid == candidate) return candidate;
    }
    return null;
  }
}

ValueListenable<DevUserState> get devUserStateListenable =>
    DevUserRegistry.instance.listenable;

DevUserState get devUserState => DevUserRegistry.instance.state;

List<DevUserEntry> getDevUsers() => devUserState.entries;

DevUserEntry? getDevUserByUid(String uid) =>
    DevUserRegistry.instance.entryByUid(uid);

String getDefaultDevUid() => isDev ? DevUserRegistry.instance.defaultUid() : '';

void setActiveDevUid(String uid) {
  if (!isDev) return;
  DevUserRegistry.instance.select(uid);
}

void rememberDevUser(String uid) {
  if (!isDev) return;
  DevUserRegistry.instance.rememberUsage(uid);
}

bool canRemoveDevUser(String uid) => DevUserRegistry.instance.canRemove(uid);

void removeDevUser(String uid) {
  if (!isDev) return;
  DevUserRegistry.instance.remove(uid);
}

Future<void> createDevUser({
  required String uid,
  String? label,
  String? note,
  bool minor = false,
  bool canManageBank = false,
  String? communityId,
  bool joinCommunity = true,
}) {
  if (!isDev) return Future<void>.value();
  return DevUserRegistry.instance.createDevUser(
    uid: uid,
    label: label,
    note: note,
    minor: minor,
    canManageBank: canManageBank,
    communityId: communityId,
    joinCommunity: joinCommunity,
  );
}
