part of 'communities_screen.dart';

enum _TalkFilter { unread, mention, active, pinned }
enum _TalkSort { unreadFirst, recent, name }

class _TalkFilterChipData {
  final String label;
  final _TalkFilter filter;
  final Color color;

  const _TalkFilterChipData({
    required this.label,
    required this.filter,
    required this.color,
  });
}

class _TalkEntry {
  final String threadId;
  final String communityId;
  final String communityName;
  final String? communityCoverUrl;
  final String partnerUid;
  final String partnerDisplayName;
  final String? partnerPhotoUrl;
  final String previewText;
  final int unreadCount;
  final DateTime? updatedAt;
  final bool hasMention;
  final bool isPinned;

  const _TalkEntry({
    required this.threadId,
    required this.communityId,
    required this.communityName,
    required this.communityCoverUrl,
    required this.partnerUid,
    required this.partnerDisplayName,
    required this.partnerPhotoUrl,
    required this.previewText,
    required this.unreadCount,
    required this.updatedAt,
    required this.hasMention,
    required this.isPinned,
  });
}

class _PendingRequestBanner extends StatelessWidget {
  const _PendingRequestBanner({
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, color: kAccentOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '承認待ちのリクエストが ${count} 件あります',
              style: const TextStyle(
                color: kTextMain,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            child: const Text('確認する'),
          ),
        ],
      ),
    );
  }
}

class _TalkTab extends StatefulWidget {
  const _TalkTab({
    required this.user,
    required this.talkThreadsQuery,
    required this.pendingRequestsCountStream,
    required this.searchKeyword,
  });

  final User user;
  final Query<Map<String, dynamic>> talkThreadsQuery;
  final Stream<int> pendingRequestsCountStream;
  final String searchKeyword;

  @override
  State<_TalkTab> createState() => _TalkTabState();
}

class _TalkTabState extends State<_TalkTab> {
  _TalkFilter? _selectedTalkFilter = _TalkFilter.unread;
  _TalkSort _selectedTalkSort = _TalkSort.unreadFirst;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.talkThreadsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorNotice('トークを取得できませんでした: ${snapshot.error}');
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildTalkScaffold(children: [_talkEmptyState()]);
        }

        return FutureBuilder<List<_TalkEntry?>>(
          future: Future.wait(docs.map(_buildTalkEntry)),
          builder: (context, metaSnap) {
            if (metaSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (metaSnap.hasError) {
              return _errorNotice('トークを処理できませんでした: ${metaSnap.error}');
            }
            final entries =
                (metaSnap.data ?? const <_TalkEntry?>[]).whereType<_TalkEntry>().toList();
            if (entries.isEmpty) {
              return _buildTalkScaffold(children: [_talkEmptyState()]);
            }

            final filtered = _applyTalkFilters(entries);
            if (filtered.isEmpty) {
              return _buildTalkScaffold(
                children: [
                  _talkEmptyState(message: '条件に一致するトークがありません'),
                ],
              );
            }

            final pinned = filtered.where((e) => e.isPinned).toList();
            final unread =
                filtered.where((e) => !e.isPinned && e.unreadCount > 0).toList();
            final recent =
                filtered.where((e) => !e.isPinned && e.unreadCount == 0).toList();

            _applyTalkSort(pinned);
            _applyTalkSort(unread);
            _applyTalkSort(recent);

            final content = <Widget>[
              StreamBuilder<int>(
                stream: widget.pendingRequestsCountStream,
                builder: (context, requestSnap) {
                  final count = requestSnap.data ?? 0;
                  if (count <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PendingRequestBanner(
                        count: count,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('承認待ちリクエスト画面は準備中です')),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              _buildTalkFilters(),
            ];

            void addSection(String title, List<_TalkEntry> items) {
              if (items.isEmpty) return;
              content
                ..add(const SizedBox(height: 24))
                ..add(_sectionHeader(title))
                ..add(const SizedBox(height: 8));
              for (final entry in items) {
                content
                  ..add(_TalkThreadTile(
                    entry: entry,
                    timeLabel: _formatTalkTime(entry.updatedAt),
                    onTap: () => _openThread(entry),
                    onTogglePin: () => _togglePin(entry),
                  ))
                  ..add(const SizedBox(height: 12));
              }
            }

            addSection('ピン留め', pinned);
            addSection('未読', unread);
            addSection('最近', recent);

            if (pinned.isEmpty && unread.isEmpty && recent.isEmpty) {
              content
                ..add(const SizedBox(height: 32))
                ..add(_talkEmptyState(message: '条件に一致するトークがありません'));
            }

            return _buildTalkScaffold(children: content);
          },
        );
      },
    );
  }

  List<_TalkEntry> _applyTalkFilters(List<_TalkEntry> entries) {
    final keyword = widget.searchKeyword.toLowerCase();
    final filter = _selectedTalkFilter;
    return [
      for (final entry in entries)
        if ((keyword.isEmpty ||
                ('${entry.communityName} ${entry.partnerDisplayName} '
                        '${entry.previewText}')
                    .toLowerCase()
                    .contains(keyword)) &&
            _matchesTalkFilter(filter, entry))
          entry
    ];
  }

  bool _matchesTalkFilter(_TalkFilter? filter, _TalkEntry entry) {
    if (filter == null) return true;
    return switch (filter) {
      _TalkFilter.unread => entry.unreadCount > 0,
      _TalkFilter.mention => entry.hasMention,
      _TalkFilter.active => true,
      _TalkFilter.pinned => entry.isPinned,
    };
  }

  void _applyTalkSort(List<_TalkEntry> entries) {
    switch (_selectedTalkSort) {
      case _TalkSort.unreadFirst:
        entries.sort((a, b) {
          final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
          if (unreadCompare != 0) return unreadCompare;
          final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
        break;
      case _TalkSort.recent:
        entries.sort((a, b) {
          final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
        break;
      case _TalkSort.name:
        entries.sort((a, b) => a.partnerDisplayName
            .toLowerCase()
            .compareTo(b.partnerDisplayName.toLowerCase()));
        break;
    }
  }

  List<_TalkFilterChipData> get _talkFilterChips => const [
        _TalkFilterChipData(
          label: '未読',
          filter: _TalkFilter.unread,
          color: kBrandBlue,
        ),
        _TalkFilterChipData(
          label: 'メンション',
          filter: _TalkFilter.mention,
          color: kAccentOrange,
        ),
        _TalkFilterChipData(
          label: '参加中',
          filter: _TalkFilter.active,
          color: kBrandBlue,
        ),
        _TalkFilterChipData(
          label: 'ピン留め',
          filter: _TalkFilter.pinned,
          color: kBrandBlue,
        ),
      ];

  Widget _buildTalkFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final chip in _talkFilterChips) ...[
              _TalkFilterChip(
                label: chip.label,
                isActive: _selectedTalkFilter == chip.filter,
                color: chip.color,
                onTap: () {
                  setState(() {
                    if (_selectedTalkFilter == chip.filter) {
                      _selectedTalkFilter = null;
                    } else {
                      _selectedTalkFilter = chip.filter;
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            DropdownButton<_TalkSort>(
              value: _selectedTalkSort,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedTalkSort = value);
              },
              items: const [
                DropdownMenuItem(
                  value: _TalkSort.unreadFirst,
                  child: Text('未読優先'),
                ),
                DropdownMenuItem(
                  value: _TalkSort.recent,
                  child: Text('新着順'),
                ),
                DropdownMenuItem(
                  value: _TalkSort.name,
                  child: Text('名前順'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<_TalkEntry?> _buildTalkEntry(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      final data = doc.data();
      final communityId = data['communityId'] as String? ?? 'unknown';
      final partnerUid = (data['participants'] as List<dynamic>?)
              ?.cast<String>()
              .firstWhere((uid) => uid != widget.user.uid, orElse: () => '') ??
          '';
      if (partnerUid.isEmpty) return null;

      final communitySnap = await withIndexLinkCopy(
        context,
        () => FirebaseFirestore.instance.doc('communities/$communityId').get(),
      );
      final communityData = communitySnap.data() ?? <String, dynamic>{};
      final communityName =
          (communityData['name'] as String?) ?? (communityData['id'] as String? ?? communityId);
      final communityCover = (communityData['coverUrl'] as String?)?.trim();

      final memberSnap = await withIndexLinkCopy(
        context,
        () => FirebaseFirestore.instance.doc('users/$partnerUid').get(),
      );
      final memberData = memberSnap.data() ?? <String, dynamic>{};
      final displayName =
          (memberData['displayName'] as String?) ?? (memberData['name'] as String?) ?? 'メンバー';
      final photoUrl = (memberData['photoUrl'] as String?)?.trim();

      final lastMessage = (data['lastMessage'] as String?) ?? '';
      final lastSenderUid = (data['lastSenderUid'] as String?) ?? '';
      final unread = (data['unreadCounts'] as Map<String, dynamic>?)
              ?[widget.user.uid]
              ?.toInt() ??
          0;
      final updatedAt = _readTimestamp(data['updatedAt']);
      final pinnedBy = (data['pinnedBy'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
      final hasMention = _detectMention(lastMessage, lastSenderUid);

      final previewText = lastMessage.isEmpty
          ? 'メッセージはまだありません'
          : (lastSenderUid == widget.user.uid
              ? 'あなた: $lastMessage'
              : '$displayName: $lastMessage');

      return _TalkEntry(
        threadId: doc.id,
        communityId: communityId,
        communityName: communityName,
        communityCoverUrl: communityCover,
        partnerUid: partnerUid,
        partnerDisplayName: displayName,
        partnerPhotoUrl: photoUrl,
        previewText: previewText,
        unreadCount: unread,
        updatedAt: updatedAt,
        hasMention: hasMention,
        isPinned: pinnedBy.contains(widget.user.uid),
      );
    } catch (e) {
      return null;
    }
  }

  bool _detectMention(String message, String senderUid) {
    if (message.isEmpty || senderUid == widget.user.uid) return false;
    final lowerMessage = message.toLowerCase();
  final displayName = FirebaseAuth.instance.currentUser?.displayName ?? widget.user.displayName;
    if (displayName == null || displayName.trim().isEmpty) {
      return lowerMessage.contains('@${widget.user.uid.toLowerCase()}');
    }
    final nameLower = displayName.toLowerCase();
    return lowerMessage.contains('@$nameLower') ||
        lowerMessage.contains('@${widget.user.uid.toLowerCase()}');
  }

  Future<void> _togglePin(_TalkEntry entry) async {
    try {
      await FirebaseFirestore.instance
          .collection('community_chats')
          .doc(entry.communityId)
          .collection('threads')
          .doc(entry.threadId)
          .set({
        'pinnedBy': entry.isPinned
            ? FieldValue.arrayRemove([widget.user.uid])
            : FieldValue.arrayUnion([widget.user.uid]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ピン留めを変更できませんでした: $e')),
      );
    }
  }

  Future<void> _openThread(_TalkEntry entry) async {
    try {
      final memberSnap = await FirebaseFirestore.instance
          .doc('memberships/${entry.communityId}_${entry.partnerUid}')
          .get();
      final role = (memberSnap.data()?['role'] as String?) ?? 'member';
      if (!mounted) return;
      await MemberChatScreen.open(
        context,
        communityId: entry.communityId,
        communityName: entry.communityName,
        currentUser: widget.user,
        partnerUid: entry.partnerUid,
        partnerDisplayName: entry.partnerDisplayName,
        partnerPhotoUrl: entry.partnerPhotoUrl,
        threadId: entry.threadId,
        memberRole: role,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットを開けませんでした: $e')),
      );
    }
  }

  String? _formatTalkTime(DateTime? time) {
    if (time == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(time.year, time.month, time.day);
    if (target == today) {
      final hours = time.hour.toString().padLeft(2, '0');
      final minutes = time.minute.toString().padLeft(2, '0');
      return '$hours:$minutes';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (target == yesterday) {
      return '昨日';
    }
    if (now.year == time.year) {
      return '${time.month}/${time.day}';
    }
    return '${time.year}/${time.month}/${time.day}';
  }

  Widget _buildTalkScaffold({required List<Widget> children}) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      children: children,
    );
  }
}
