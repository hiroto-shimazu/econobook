import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/community.dart';
import '../models/conversation_summary.dart';
import '../services/chat_service.dart';
import '../services/conversation_service.dart';

const Color _kBgLight = Color(0xFFF1F5F9);
const Color _kCardWhite = Color(0xFFFFFFFF);
const Color _kMainBlue = Color(0xFF2563EB);
const Color _kSubGreen = Color(0xFF16A34A);
const Color _kAccentOrange = Color(0xFFF59E0B);
const Color _kDangerRed = Color(0xFFDC2626);
const Color _kTextMain = Color(0xFF0F172A);
const Color _kTextSub = Color(0xFF64748B);
const Color _kBubbleMe = Color(0xFFD1FAE5);
const Color _kBubbleMeText = Color(0xFF065F46);
const Color _kBubbleOther = Color(0xFFF3F4F6);

class MemberChatScreen extends StatefulWidget {
  const MemberChatScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.currentUser,
    required this.partnerUid,
    required this.partnerDisplayName,
    required this.threadId,
    this.partnerPhotoUrl,
    required this.memberRole,
  });

  final String communityId;
  final String communityName;
  final User currentUser;
  final String partnerUid;
  final String partnerDisplayName;
  final String threadId;
  final String? partnerPhotoUrl;
  final String memberRole;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required User currentUser,
    required String partnerUid,
    required String partnerDisplayName,
    required String threadId,
    String? partnerPhotoUrl,
    required String memberRole,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberChatScreen(
          communityId: communityId,
          communityName: communityName,
          currentUser: currentUser,
          partnerUid: partnerUid,
          partnerDisplayName: partnerDisplayName,
          partnerPhotoUrl: partnerPhotoUrl,
          threadId: threadId,
          memberRole: memberRole,
        ),
      ),
    );
  }

  @override
  State<MemberChatScreen> createState() => _MemberChatScreenState();
}

class _MemberChatScreenState extends State<MemberChatScreen> {
  final ConversationService _conversationService = ConversationService();
  final ChatService _chatService = ChatService();
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Stream<List<ChatMessage>>? _messageStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _threadStream;
  Community? _community;
  String _partnerDisplayName = '';
  String? _partnerPhotoUrl;
  ConversationSummary? _summary;
  Object? _summaryError;
  bool _summaryLoading = false;
  bool _sending = false;
  bool _markingRead = false;
  // track message ids that have had their timestamps shown so we can preserve them
  final Set<String> _timeShownIds = <String>{};

  @override
  void initState() {
    super.initState();
    _messageStream = _conversationService.messageStream(
      communityId: widget.communityId,
      threadId: widget.threadId,
    );
    _threadStream = _chatService.threadStream(
      communityId: widget.communityId,
      threadId: widget.threadId,
    );
    _partnerDisplayName = widget.partnerDisplayName;
    _partnerPhotoUrl = widget.partnerPhotoUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCommunity();
      _loadPartnerProfile();
      _markAsRead();
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunity() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .get();
      if (!snap.exists) return;
      final community = Community.fromSnapshot(snap);
      if (!mounted) return;
      setState(() => _community = community);
      await _refreshSummary();
    } catch (e) {
      if (!mounted) return;
      setState(() => _summaryError = e);
    }
  }

  Future<void> _loadPartnerProfile() async {
    try {
      if (widget.partnerUid.isEmpty) return;
      final snap = await FirebaseFirestore.instance
          .doc('users/${widget.partnerUid}')
          .get();
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final candidate = (data['displayName'] as String?)?.trim();
      String? photo;
      for (final key in const [
        'photoUrl',
        'photoURL',
        'avatarUrl',
        'imageUrl',
        'iconUrl',
      ]) {
        final value = (data[key] as String?)?.trim();
        if (value != null && value.isNotEmpty) {
          photo = value;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        if (candidate != null && candidate.isNotEmpty) {
          _partnerDisplayName = candidate;
        }
        if (photo != null && photo.isNotEmpty) {
          _partnerPhotoUrl = photo;
        }
      });
    } catch (_) {
      // ignore profile load errors
    }
  }

  Future<void> _refreshSummary() async {
    final community = _community;
    if (community == null) return;
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final summary = await _conversationService.loadMonthlySummary(
        communityId: widget.communityId,
        currentUid: widget.currentUser.uid,
        partnerUid: widget.partnerUid,
        currencyCode: community.currency.code,
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _summaryError = e);
    } finally {
      if (mounted) {
        setState(() => _summaryLoading = false);
      }
    }
  }

  Future<void> _markAsRead() async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await _chatService.markThreadAsRead(
        communityId: widget.communityId,
        threadId: widget.threadId,
        userUid: widget.currentUser.uid,
      );
    } catch (_) {
      // ignore
    } finally {
      _markingRead = false;
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _conversationService.sendText(
        communityId: widget.communityId,
        senderUid: widget.currentUser.uid,
        receiverUid: widget.partnerUid,
        text: text,
      );
      _messageCtrl.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openTransferSheet() async {
    final community = _community;
    if (community == null) return;
    final result = await showModalBottomSheet<_AmountMemo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AmountSheet(
        title: '送金する',
        actionLabel: '送金',
        currencyCode: community.currency.code,
      ),
    );
    if (result == null) return;
    await _executeTransfer(result.amount, result.memo ?? '');
  }

  Future<void> _executeTransfer(num amount, String memo) async {
    final community = _community;
    if (community == null) return;
    try {
      await _conversationService.sendTransfer(
        communityId: widget.communityId,
        senderUid: widget.currentUser.uid,
        receiverUid: widget.partnerUid,
        amount: amount,
        currencyCode: community.currency.code,
        memo: memo.isEmpty ? null : memo,
      );
      await _refreshSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${community.currency.code} ${amount.toStringAsFixed(community.currency.precision)} を送金しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送金に失敗しました: $e')),
      );
    }
  }

  Future<void> _openRequestSheet() async {
    final community = _community;
    if (community == null) return;
    final result = await showModalBottomSheet<_AmountMemo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AmountSheet(
        title: '請求する',
        actionLabel: '請求を作成',
        currencyCode: community.currency.code,
      ),
    );
    if (result == null) return;
    try {
      await _conversationService.sendRequest(
        communityId: widget.communityId,
        requesterUid: widget.currentUser.uid,
        targetUid: widget.partnerUid,
        amount: result.amount,
        currencyCode: community.currency.code,
        memo: result.memo,
      );
      await _refreshSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請求を送信しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請求に失敗しました: $e')),
      );
    }
  }

  Future<void> _openSplitSheet() async {
    final community = _community;
    if (community == null) return;
    final result = await showModalBottomSheet<_SplitInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SplitSheet(
        currencyCode: community.currency.code,
      ),
    );
    if (result == null) return;
    try {
      await _conversationService.sendSplitRequest(
        communityId: widget.communityId,
        requesterUid: widget.currentUser.uid,
        targetUid: widget.partnerUid,
        totalAmount: result.total,
        currencyCode: community.currency.code,
        memo: result.memo,
      );
      await _refreshSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('割り勘リクエストを送信しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('割り勘リクエストに失敗しました: $e')),
      );
    }
  }

  Future<void> _openTaskSheet() async {
    final community = _community;
    if (community == null) return;
    final result = await showModalBottomSheet<_TaskInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskSheet(
        currencyCode: community.currency.code,
      ),
    );
    if (result == null) return;
    try {
      await _conversationService.sendTask(
        communityId: widget.communityId,
        creatorUid: widget.currentUser.uid,
        assigneeUid: widget.partnerUid,
        title: result.title,
        reward: result.reward,
        currencyCode: community.currency.code,
        description: result.description,
      );
      await _refreshSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タスクを共有しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('タスクの共有に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = _community;
    final currencyCode = community?.currency.code ?? 'ECO';
    return Scaffold(
      backgroundColor: _kBgLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(currencyCode),
            Expanded(
              child: Container(
                color: _kBgLight,
                child: Column(
                  children: [
                    _buildSummaryCard(currencyCode),
                    const SizedBox(height: 12),
                    Expanded(child: _buildMessageArea()),
                    // Action row: small horizontal icon buttons just above composer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildActionRow(),
                    ),
                    _buildComposer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String currencyCode) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCardWhite,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: _kMainBlue.withOpacity(0.15),
            backgroundImage: (_partnerPhotoUrl ?? widget.partnerPhotoUrl) ==
                        null ||
                    (_partnerPhotoUrl ?? widget.partnerPhotoUrl)!.isEmpty
                ? null
                : NetworkImage((_partnerPhotoUrl ?? widget.partnerPhotoUrl)!),
            child: (_partnerPhotoUrl ?? widget.partnerPhotoUrl) == null ||
                    (_partnerPhotoUrl ?? widget.partnerPhotoUrl)!.isEmpty
                ? Text(
                    (_partnerDisplayName.isNotEmpty
                            ? _partnerDisplayName
                            : widget.partnerDisplayName)
                        .characters
                        .first
                        .toUpperCase(),
                    style: const TextStyle(
                        color: _kMainBlue, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _partnerDisplayName.isNotEmpty
                      ? _partnerDisplayName
                      : widget.partnerDisplayName,
                  style: const TextStyle(
                    color: _kTextMain,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${widget.communityName} · ${_roleLabel(widget.memberRole)}',
                  style: const TextStyle(fontSize: 12, color: _kTextSub),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String currencyCode) {
    final summary = _summary;
    final net = summary?.net ?? 0;
    final pending =
        (summary?.pendingRequestCount ?? 0) + (summary?.pendingTaskCount ?? 0);
    final period = summary?.periodLabel ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _kCardWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              offset: Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'あなた ↔ ${_partnerDisplayName.isNotEmpty ? _partnerDisplayName : widget.partnerDisplayName} ($period)',
                        style: const TextStyle(
                          color: _kTextSub,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatAmount(net, currencyCode),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _kTextMain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            currencyCode,
                            style: const TextStyle(
                              fontSize: 16,
                              color: _kTextSub,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kAccentOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '保留: ${pending}件',
                    style: const TextStyle(
                      color: _kAccentOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Actions moved into the composer for a compact UI
            if (_summaryLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_summaryError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ErrorNotice(
                  title: 'サマリーを取得できませんでした',
                  error: _summaryError!,
                  guidance: _guidanceForError(_summaryError!),
                  debugLines: kDebugMode
                      ? [
                          'communityId=${widget.communityId}',
                          'partnerUid=${widget.partnerUid}',
                        ]
                      : const [],
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildMessageArea() {
    final messageStream = _messageStream;
    if (messageStream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<ChatMessage>>(
      stream: messageStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _ErrorNotice(
                title: 'メッセージの取得に失敗しました',
                error: snapshot.error!,
                guidance: _guidanceForError(snapshot.error!),
                debugLines: kDebugMode
                    ? [
                        'communityId=${widget.communityId}',
                        'threadId=${widget.threadId}',
                      ]
                    : const [],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data ?? const <ChatMessage>[];
        final entries = _buildTimelineEntries(messages);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _threadStream,
          builder: (context, threadSnapshot) {
            if (threadSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _ErrorNotice(
                    title: 'スレッド情報の取得に失敗しました',
                    error: threadSnapshot.error!,
                    guidance: _guidanceForError(threadSnapshot.error!),
                    debugLines: kDebugMode
                        ? [
                            'communityId=${widget.communityId}',
                            'threadId=${widget.threadId}',
                          ]
                        : const [],
                  ),
                ),
              );
            }
            int partnerUnread = 0;
            if (threadSnapshot.data?.exists == true) {
              final data = threadSnapshot.data!.data();
              final unreadMap = (data?['unreadCounts'] as Map?) ?? const {};
              final value = unreadMap[widget.currentUser.uid];
              final unread = value is num ? value.toInt() : 0;
              if (unread > 0) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _markAsRead());
              }
              final partnerValue = unreadMap[widget.partnerUid];
              if (partnerValue is num) {
                partnerUnread = partnerValue.toInt();
              }
            }
            final bool partnerHasUnread = partnerUnread > 0;
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.isDate) {
                  return _DateChip(date: entry.date!);
                }
                final showTime = entry.showTime ?? true;
                final isMine =
                    entry.message!.senderUid == widget.currentUser.uid;
                return _MessageBubble(
                  message: entry.message!,
                  isMine: isMine,
                  partnerPhotoUrl: _partnerPhotoUrl ?? widget.partnerPhotoUrl,
                  partnerInitial: (_partnerDisplayName.isNotEmpty
                          ? _partnerDisplayName
                          : widget.partnerDisplayName)
                      .characters
                      .first
                      .toUpperCase(),
                  currencyCode: _community?.currency.code ?? 'ECO',
                  showTime: showTime,
                  isRead: isMine && showTime && !partnerHasUnread,
                );
              },
            );
          },
        );
      },
    );
  }

  List<_TimelineEntry> _buildTimelineEntries(List<ChatMessage> messages) {
    final entries = <_TimelineEntry>[];
    DateTime? lastDate;
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final createdAt = message.createdAt ?? DateTime.now();
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      if (lastDate == null || !_isSameDay(lastDate, date)) {
        entries.add(_TimelineEntry.date(date));
        lastDate = date;
      }
      // showTime only when next message is from a different sender or there is no next message
      final bool showTime;
      if (i + 1 < messages.length) {
        final next = messages[i + 1];
        showTime = next.senderUid != message.senderUid;
      } else {
        showTime = true;
      }
      // preserve previously shown times for past messages
      final effectiveShow = showTime || _timeShownIds.contains(message.id);
      if (effectiveShow) {
        _timeShownIds.add(message.id);
      }
      entries.add(_TimelineEntry.message(message, showTime: effectiveShow));
    }
    return entries;
  }

  List<String> _guidanceForError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return const [
            'メンバーシップまたは該当する権限が不足しています。コミュニティの権限管理から銀行・メンバー権限を取得してください。',
          ];
        case 'failed-precondition':
          return const [
            'Firestore の複合インデックスが未作成の可能性があります。エラーメッセージ内の URL からインデックスを作成してください。',
          ];
        default:
          break;
      }
    }
    return const [];
  }

  Widget _buildComposer() {
    return Container(
      decoration: const BoxDecoration(
        color: _kCardWhite,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 12,
        left: 16,
        right: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ComposerIconButton(
            icon: Icons.add,
            onTap: () => _openTransferSheet(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: TextField(
                controller: _messageCtrl,
                minLines: 1,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'メッセージを入力',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ComposerIconButton(
            icon: Icons.emoji_emotions_outlined,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              '${_summary?.net.toStringAsFixed(2) ?? '0.00'} ${_community?.currency.code ?? ''}',
              style: const TextStyle(
                fontSize: 12,
                color: _kTextMain,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _sending ? null : _sendText,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kMainBlue,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _formatAmount(num value, String currencyCode) {
    final sign = value >= 0 ? '+' : '-';
    final absValue = value.abs();
    return '$sign${absValue.toStringAsFixed(2)}';
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'オーナー';
      case 'admin':
        return '管理者';
      case 'mediator':
        return '仲介';
      case 'pending':
        return '承認待ち';
      default:
        return 'メンバー';
    }
  }
}

class _TimelineEntry {
  _TimelineEntry.date(this.date)
      : message = null,
        isDate = true,
        showTime = null;

  _TimelineEntry.message(this.message, {this.showTime = true})
      : date = null,
        isDate = false;

  final DateTime? date;
  final ChatMessage? message;
  final bool isDate;
  final bool? showTime;
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            '${date.year}年${date.month}月${date.day}日',
            style: const TextStyle(color: _kTextSub, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

Widget _buildActionRow() {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: _ActionExpandedButton(
            icon: Icons.north_east,
            label: '送る',
            color: _kMainBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionExpandedButton(
            icon: Icons.south_west,
            label: '請求',
            color: _kSubGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionExpandedButton(
            icon: Icons.calculate,
            label: '割り勘',
            color: _kTextSub,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionExpandedButton(
            icon: Icons.task_alt_outlined,
            label: 'タスク',
            color: _kAccentOrange,
          ),
        ),
      ],
    ),
  );
}

class _ActionExpandedButton extends StatelessWidget {
  const _ActionExpandedButton(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final state = context.findAncestorStateOfType<_MemberChatScreenState>();
        if (state == null) return;
        switch (label) {
          case '送る':
            state._openTransferSheet();
            break;
          case '請求':
            state._openRequestSheet();
            break;
          case '割り勘':
            state._openSplitSheet();
            break;
          case 'タスク':
            state._openTaskSheet();
            break;
          default:
            break;
        }
      },
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.18), color.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: _kTextMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.partnerPhotoUrl,
    required this.partnerInitial,
    required this.currencyCode,
    this.showTime = true,
    required this.isRead,
  });

  final ChatMessage message;
  final bool isMine;
  final String? partnerPhotoUrl;
  final String partnerInitial;
  final String currencyCode;
  final bool showTime;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.text ?? 'システムメッセージ',
            style: const TextStyle(color: _kTextSub, fontSize: 12),
          ),
        ),
      );
    }

    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bool isSpecial = message.isTransfer ||
        message.isRequest ||
        message.isSplit ||
        message.isTask;
    final Color bubbleColor = isSpecial
        ? _buildCardColor(isMine)
        : (isMine ? _kBubbleMe : _kBubbleOther);
    final Color textColor = isMine ? _kBubbleMeText : _kTextMain;

    final Widget content = _buildContent(context, textColor);

    Widget? metaWidget;
    if (showTime) {
      final metaChildren = <Widget>[];
      if (isMine && isRead) {
        metaChildren.add(
          const Text(
            '既読',
            style: TextStyle(
              color: _kTextSub,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
        metaChildren.add(const SizedBox(height: 2));
      }
      metaChildren.add(
        Text(
          _formatTime(message.createdAt),
          style: const TextStyle(color: _kTextSub, fontSize: 10),
        ),
      );
      metaWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: metaChildren,
      );
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: _kMainBlue.withOpacity(0.15),
                  backgroundImage:
                      partnerPhotoUrl == null || partnerPhotoUrl!.isEmpty
                          ? null
                          : NetworkImage(partnerPhotoUrl!),
                  child: partnerPhotoUrl == null || partnerPhotoUrl!.isEmpty
                      ? Text(
                          partnerInitial,
                          style: const TextStyle(
                            color: _kMainBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
            if (isMine && metaWidget != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: metaWidget,
              ),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.68,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(24),
                    topRight: const Radius.circular(24),
                    bottomLeft: Radius.circular(isMine ? 24 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 24),
                  ),
                  border: isSpecial
                      ? Border.all(
                          color: isMine
                              ? Colors.transparent
                              : const Color(0xFFE2E8F0),
                        )
                      : null,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: content,
              ),
            ),
            if (!isMine && metaWidget != null) ...[
              const SizedBox(width: 8),
              metaWidget,
            ],
          ],
        ),
      ),
    );
  }

  Color _buildCardColor(bool isMine) {
    if (message.isTransfer) {
      return isMine ? _kSubGreen : const Color(0xFFEFF4FF);
    }
    if (message.isRequest || message.isSplit) {
      return const Color(0xFFFFF7ED);
    }
    if (message.isTask) {
      return const Color(0xFFF5F3FF);
    }
    return isMine ? _kBubbleMe : _kBubbleOther;
  }

  Widget _buildContent(BuildContext context, Color textColor) {
    if (message.isTransfer) {
      final amount = message.amount ?? 0;
      final isCredit = !isMine;
      return Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Icon(
                isCredit ? Icons.south_west : Icons.north_east,
                size: 18,
                color: isCredit ? _kSubGreen : _kMainBlue,
              ),
              const SizedBox(width: 6),
              Text(
                '${isCredit ? '+' : '-'}${amount.toStringAsFixed(2)} $currencyCode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isCredit ? _kSubGreen : _kMainBlue,
                ),
              ),
            ],
          ),
          if (message.memo != null && message.memo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.memo!,
              style: const TextStyle(fontSize: 13, color: _kTextMain),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '取引ID: ${message.ledgerEntryId ?? '-'}',
            style: const TextStyle(color: _kTextSub, fontSize: 11),
          ),
        ],
      );
    }

    if (message.isRequest || message.isSplit) {
      final amount = message.amount ?? 0;
      return Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.request_page, color: _kAccentOrange, size: 18),
              const SizedBox(width: 6),
              Text(
                '${amount.toStringAsFixed(2)} $currencyCode を請求',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          if (message.memo != null && message.memo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.memo!,
              style: const TextStyle(fontSize: 13, color: _kTextMain),
            ),
          ],
          const SizedBox(height: 8),
          _RequestStatusChip(requestId: message.requestId),
        ],
      );
    }

    if (message.isTask) {
      final reward = message.metadata['reward'];
      final title = (message.metadata['title'] as String?) ?? 'タスク';
      final desc = message.metadata['description'] as String?;
      return Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, color: _kMainBlue, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kTextMain,
                  ),
                ),
              ),
            ],
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(color: _kTextMain, fontSize: 13)),
          ],
          if (reward is num) ...[
            const SizedBox(height: 8),
            Text(
              '報酬: ${reward.toStringAsFixed(2)} $currencyCode',
              style: const TextStyle(
                  color: _kSubGreen, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          _TaskStatusChip(taskId: message.taskId),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          message.text ?? '',
          style: TextStyle(color: textColor, fontSize: 15),
        ),
      ],
    );
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _RequestStatusChip extends StatelessWidget {
  const _RequestStatusChip({required this.requestId});

  final String? requestId;

  @override
  Widget build(BuildContext context) {
    if (requestId == null) {
      return const SizedBox.shrink();
    }
    final requestDoc = FirebaseFirestore.instance
        .collection('requests')
        .doc(_conversationContextOf(context).communityId)
        .collection('items')
        .doc(requestId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: requestDoc.snapshots(),
      builder: (context, snapshot) {
        final status =
            (snapshot.data?.data()?['status'] as String?) ?? 'pending';
        final label = switch (status) {
          'approved' => '承認済み',
          'rejected' => '却下',
          'processing' => '処理中',
          _ => '保留中',
        };
        final color = switch (status) {
          'approved' => _kSubGreen,
          'rejected' => _kDangerRed,
          'processing' => _kAccentOrange,
          _ => _kAccentOrange,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

class _TaskStatusChip extends StatelessWidget {
  const _TaskStatusChip({required this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context) {
    if (taskId == null) {
      return const SizedBox.shrink();
    }
    final taskDoc = FirebaseFirestore.instance
        .collection('tasks')
        .doc(_conversationContextOf(context).communityId)
        .collection('items')
        .doc(taskId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taskDoc.snapshots(),
      builder: (context, snapshot) {
        final status = (snapshot.data?.data()?['status'] as String?) ?? 'open';
        final label = switch (status) {
          'open' => '募集中',
          'taken' => '進行中',
          'submitted' => '提出済み',
          'approved' => '承認済み',
          'rejected' => '却下',
          _ => 'ステータス不明',
        };
        final color = switch (status) {
          'approved' => _kSubGreen,
          'rejected' => _kDangerRed,
          'submitted' => _kMainBlue,
          'taken' => _kAccentOrange,
          _ => _kTextSub,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _kTextSub),
      ),
    );
  }
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.title,
    required this.actionLabel,
    required this.currencyCode,
  });

  final String title;
  final String actionLabel;
  final String currencyCode;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            decoration: InputDecoration(
              labelText: '金額 (${widget.currencyCode})',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoCtrl,
            decoration: InputDecoration(
              labelText: 'メモ (任意)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.actionLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final amount = num.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金額を正しく入力してください')),
      );
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(_AmountMemo(
      amount: amount,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
    ));
  }
}

class _SplitSheet extends StatefulWidget {
  const _SplitSheet({required this.currencyCode});

  final String currencyCode;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _totalCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '割り勘の合計',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _totalCtrl,
            decoration: InputDecoration(
              labelText: '合計金額 (${widget.currencyCode})',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoCtrl,
            decoration: InputDecoration(
              labelText: 'メモ (任意)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('割り勘を送信'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final total = num.tryParse(_totalCtrl.text.trim());
    if (total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('合計金額を正しく入力してください')),
      );
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(_SplitInput(
      total: total,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
    ));
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.currencyCode});

  final String currencyCode;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _rewardCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rewardCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'タスクを依頼',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: 'タイトル',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rewardCtrl,
            decoration: InputDecoration(
              labelText: '報酬 (${widget.currencyCode})',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: '説明 (任意)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('共有'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    final reward = num.tryParse(_rewardCtrl.text.trim());
    if (title.isEmpty || reward == null || reward <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルと正しい報酬を入力してください')),
      );
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(_TaskInput(
      title: title,
      reward: reward,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    ));
  }
}

class _BottomSheetContainer extends StatelessWidget {
  const _BottomSheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: child,
      ),
    );
  }
}

class _AmountMemo {
  const _AmountMemo({required this.amount, this.memo});

  final num amount;
  final String? memo;
}

class _SplitInput {
  const _SplitInput({required this.total, this.memo});

  final num total;
  final String? memo;
}

class _TaskInput {
  const _TaskInput(
      {required this.title, required this.reward, this.description});

  final String title;
  final num reward;
  final String? description;
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({
    required this.title,
    required this.error,
    this.guidance = const [],
    this.debugLines = const [],
  });

  final String title;
  final Object error;
  final List<String> guidance;
  final List<String> debugLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _describeError(error);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
          color: _kDangerRed,
          height: 1.4,
        ) ??
        const TextStyle(color: _kDangerRed, fontSize: 13, height: 1.4);
    final linkStyle = baseStyle.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kDangerRed.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _kDangerRed, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                        color: _kDangerRed,
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(
                        color: _kDangerRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 8),
                SelectableText.rich(
                  TextSpan(
                    children: _linkifyText(
                      context,
                      message,
                      baseStyle,
                      linkStyle,
                    ),
                  ),
                  style: baseStyle,
                ),
                if (guidance.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...guidance.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '・',
                            style: TextStyle(
                              color: _kDangerRed,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SelectableText(
                              line,
                              style: theme.textTheme.bodySmall?.copyWith(
                                    color: _kTextMain,
                                    height: 1.4,
                                  ) ??
                                  const TextStyle(
                                    color: _kTextMain,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (debugLines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...debugLines.map(
                    (line) => SelectableText(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            fontFamily: 'monospace',
                          ) ??
                          const TextStyle(
                            color: Colors.black54,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: 'コピー',
              icon: const Icon(Icons.copy_rounded, color: _kDangerRed),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final clipboardText = _buildClipboardText(
                  title,
                  message,
                  guidance,
                  debugLines,
                );
                await Clipboard.setData(ClipboardData(text: clipboardText));
                messenger.showSnackBar(
                  const SnackBar(content: Text('エラー情報をコピーしました')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _describeError(Object error) {
    if (error is FirebaseException) {
      final buffer = StringBuffer();
      if (error.code.isNotEmpty) {
        buffer.write('[${error.code}] ');
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        buffer.write(error.message!.trim());
      } else {
        buffer.write(error.toString());
      }
      return buffer.toString();
    }
    return error.toString();
  }

  static String _buildClipboardText(
    String title,
    String message,
    List<String> guidance,
    List<String> debugLines,
  ) {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln(message);
    if (guidance.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Guidance:');
      for (final line in guidance) {
        buffer.writeln('- $line');
      }
    }
    if (debugLines.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Debug:');
      for (final line in debugLines) {
        buffer.writeln(line);
      }
    }
    return buffer.toString().trim();
  }

  static List<InlineSpan> _linkifyText(
    BuildContext context,
    String message,
    TextStyle baseStyle,
    TextStyle linkStyle,
  ) {
    final spans = <InlineSpan>[];
    final urlPattern = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    int start = 0;
    for (final match in urlPattern.allMatches(message)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: message.substring(start, match.start),
          style: baseStyle,
        ));
      }
      final matchText = match.group(0)!;
      final trimmed = matchText.replaceFirst(RegExp(r'[,.;)\]]+$'), '');
      final trailing = matchText.substring(trimmed.length);
      spans.add(TextSpan(
        text: trimmed,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final messenger = ScaffoldMessenger.of(context);
            final uri = Uri.tryParse(trimmed);
            if (uri == null) {
              messenger.showSnackBar(
                SnackBar(content: Text('URLを開けませんでした: $trimmed')),
              );
              return;
            }
            try {
              final success = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('URLを開けませんでした: $trimmed')),
                );
              }
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('URLを開けませんでした: $e')),
              );
            }
          },
      ));
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing, style: baseStyle));
      }
      start = match.end;
    }
    if (start < message.length) {
      spans.add(TextSpan(text: message.substring(start), style: baseStyle));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: message, style: baseStyle));
    }
    return spans;
  }
}

_ConversationContext _conversationContextOf(BuildContext context) {
  final state = context.findAncestorStateOfType<_MemberChatScreenState>();
  if (state == null) {
    throw StateError('MemberChatScreen state not found in context');
  }
  return _ConversationContext(state.widget.communityId);
}

class _ConversationContext {
  const _ConversationContext(this.communityId);

  final String communityId;
}
