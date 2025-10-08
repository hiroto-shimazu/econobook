import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/community.dart';
import '../../models/split_rounding_mode.dart';
import '../../services/ledger_service.dart';
import '../../services/request_service.dart';
import '../../services/split_calculator.dart';
import '../../services/transaction_event_bus.dart';
import '../../utils/error_formatter.dart';
import '../../utils/error_snackbar.dart';

const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)],
);

enum TransactionKind { transfer, request, split }

class TransactionFlowScreen extends StatefulWidget {
  const TransactionFlowScreen({
    super.key,
    required this.user,
    this.initialCommunityId,
    this.initialKind,
    this.initialMemberUid,
  });

  final User user;
  final String? initialCommunityId;
  final TransactionKind? initialKind;
  final String? initialMemberUid;

  static Future<bool?> open(BuildContext context,
      {required User user,
      String? communityId,
      TransactionKind? initialKind,
      String? initialMemberUid}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionFlowScreen(
          user: user,
          initialCommunityId: communityId,
          initialKind: initialKind,
          initialMemberUid: initialMemberUid,
        ),
      ),
    );
  }

  @override
  State<TransactionFlowScreen> createState() => _TransactionFlowScreenState();
}

class _TransactionFlowScreenState extends State<TransactionFlowScreen> {
  late Future<List<_CommunityOption>> _communitiesFuture;
  late TransactionKind _kind;
  String? _selectedCommunityId;
  bool _submitting = false;
  SplitRoundingMode _splitRoundingMode = SplitRoundingMode.even;

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _requestAmountCtrl = TextEditingController();
  final TextEditingController _splitAmountCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  final TextEditingController _requestMemoCtrl = TextEditingController();
  final TextEditingController _splitMemoCtrl = TextEditingController();

  String? _transferTargetUid;
  String? _requestTargetUid;
  final Set<String> _splitTargets = <String>{};

  final LedgerService _ledgerService = LedgerService();
  final RequestService _requestService = RequestService();
  final Map<String, Future<List<_MemberOption>>> _membersFutureCache = {};

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? TransactionKind.transfer;
    _transferTargetUid = widget.initialMemberUid;
    _requestTargetUid = widget.initialMemberUid;
    if (widget.initialMemberUid != null) {
      _splitTargets.add(widget.initialMemberUid!);
    }
    _communitiesFuture = _loadCommunityOptions();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _requestAmountCtrl.dispose();
    _requestMemoCtrl.dispose();
    _splitAmountCtrl.dispose();
    _splitMemoCtrl.dispose();
    super.dispose();
  }

  Future<List<_CommunityOption>> _loadCommunityOptions() async {
    final membershipSnap = await FirebaseFirestore.instance
        .collection('memberships')
        .where('uid', isEqualTo: widget.user.uid)
        .get();

    final futures = membershipSnap.docs.map((doc) async {
      final data = doc.data();
      final cid = data['cid'] as String?;
      if (cid == null || cid.isEmpty) return null;
      final communitySnap =
          await FirebaseFirestore.instance.doc('communities/$cid').get();
      final communityData = communitySnap.data();
      final currency =
          (communityData?['currency'] as Map<String, dynamic>?) ?? const {};
      final name = (communityData?['name'] as String?) ?? cid;
      final symbol = (communityData?['symbol'] as String?) ?? 'PTS';
      final precision = (currency['precision'] as num?)?.toInt() ?? 2;
      return _CommunityOption(
        id: cid,
        name: name,
        symbol: symbol,
        precision: precision,
      );
    });

    final result = <_CommunityOption>[];
    for (final future in futures) {
      final option = await future;
      if (option != null) result.add(option);
    }
    result.sort((a, b) => a.name.compareTo(b.name));

    if (widget.initialCommunityId != null &&
        result.any((e) => e.id == widget.initialCommunityId)) {
      _selectedCommunityId = widget.initialCommunityId;
    } else if (result.isNotEmpty) {
      _selectedCommunityId = result.first.id;
    }
    return result;
  }

  Future<List<_MemberOption>> _loadMembers(String communityId) {
    return _membersFutureCache.putIfAbsent(communityId, () async {
      final membershipSnap = await FirebaseFirestore.instance
          .collection('memberships')
          .where('cid', isEqualTo: communityId)
          .get();

      final memberDocs = membershipSnap.docs;
      final futures = memberDocs.map((doc) async {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid == null) return null;
        final userSnap =
            await FirebaseFirestore.instance.doc('users/$uid').get();
        final userData = userSnap.data();
        final name = (userData?['displayName'] as String?) ?? uid;
        return _MemberOption(
          uid: uid,
          name: uid == widget.user.uid ? '自分' : name,
          isCurrentUser: uid == widget.user.uid,
        );
      });

      final result = <_MemberOption>[];
      for (final future in futures) {
        final member = await future;
        if (member != null) result.add(member);
      }
      result.sort((a, b) => a.name.compareTo(b.name));
      result.add(const _MemberOption(
        uid: kCentralBankUid,
        name: '中央銀行',
        isCurrentUser: false,
        isCentralBank: true,
      ));
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('取引を作成',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<List<_CommunityOption>>(
        future: _communitiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorState('コミュニティの読み込みに失敗しました: ${snapshot.error}');
          }
          final communities = snapshot.data ?? const [];
          if (communities.isEmpty) {
            return _emptyState('まずはコミュニティに参加してください');
          }
          return _buildContent(context, communities);
        },
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, List<_CommunityOption> communities) {
    final selectedCommunity = communities.firstWhere(
      (c) => c.id == _selectedCommunityId,
      orElse: () => communities.first,
    );
    final membersFuture = _loadMembers(selectedCommunity.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('コミュニティ', style: _labelStyle()),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: selectedCommunity.id,
            items: [
              for (final option in communities)
                DropdownMenuItem(
                  value: option.id,
                  child: Text('${option.name} (${option.symbol})'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedCommunityId = value;
                _transferTargetUid = null;
                _requestTargetUid = null;
                _splitTargets.clear();
              });
            },
          ),
          const SizedBox(height: 16),
          _kindSelector(),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<_MemberOption>>(
              future: membersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _errorState('メンバーの読み込みに失敗しました: ${snapshot.error}');
                }
                final members = snapshot.data ?? const [];
                _syncSelectionsWithMembers(members);
                return _buildFormForKind(context, selectedCommunity, members);
              },
            ),
          )
        ],
      ),
    );
  }

  void _syncSelectionsWithMembers(List<_MemberOption> members) {
    final available = members.map((m) => m.uid).toSet();
    final invalidTransfer =
        _transferTargetUid != null && !available.contains(_transferTargetUid);
    final invalidRequest =
        _requestTargetUid != null && !available.contains(_requestTargetUid);
    final invalidSplit =
        _splitTargets.any((uid) => !available.contains(uid));

    if (invalidTransfer || invalidRequest || invalidSplit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          if (invalidTransfer) {
            _transferTargetUid = null;
          }
          if (invalidRequest) {
            _requestTargetUid = null;
          }
          if (invalidSplit) {
            _splitTargets.removeWhere((uid) => !available.contains(uid));
          }
        });
      });
    }
  }

  Widget _kindSelector() {
    return SegmentedButton<TransactionKind>(
      segments: const [
        ButtonSegment(
            value: TransactionKind.transfer,
            label: Text('送金'),
            icon: Icon(Icons.arrow_upward)),
        ButtonSegment(
            value: TransactionKind.request,
            label: Text('請求'),
            icon: Icon(Icons.request_page)),
        ButtonSegment(
            value: TransactionKind.split,
            label: Text('割り勘'),
            icon: Icon(Icons.calculate)),
      ],
      selected: <TransactionKind>{_kind},
      onSelectionChanged: (selection) {
        setState(() {
          _kind = selection.first;
        });
      },
    );
  }

  Widget _buildFormForKind(BuildContext context, _CommunityOption community,
      List<_MemberOption> members) {
    switch (_kind) {
      case TransactionKind.transfer:
        return _TransferForm(
          members: members,
          amountCtrl: _amountCtrl,
          memoCtrl: _memoCtrl,
          targetUid: _transferTargetUid,
          submitting: _submitting,
          onChangedTarget: (value) =>
              setState(() => _transferTargetUid = value),
          onSubmit: () => _submitTransfer(community),
        );
      case TransactionKind.request:
        return _RequestForm(
          members: members,
          amountCtrl: _requestAmountCtrl,
          memoCtrl: _requestMemoCtrl,
          targetUid: _requestTargetUid,
          submitting: _submitting,
          onChangedTarget: (value) => setState(() => _requestTargetUid = value),
          onSubmit: () => _submitRequest(community),
        );
      case TransactionKind.split:
        return _SplitForm(
          members: members,
          totalCtrl: _splitAmountCtrl,
          memoCtrl: _splitMemoCtrl,
          targets: _splitTargets,
          submitting: _submitting,
          roundingMode: _splitRoundingMode,
          precision: community.precision,
          onChangedTargets: (value) => setState(() {
            _splitTargets
              ..clear()
              ..addAll(value);
          }),
          onChangedRounding: (mode) =>
              setState(() => _splitRoundingMode = mode),
          onSubmit: () => _submitSplit(community),
        );
    }
  }

  Future<void> _submitTransfer(_CommunityOption community) async {
    final amount = _parseAmount(_amountCtrl.text);
    final target = _transferTargetUid;
    if (target == null || target.isEmpty) {
      _toast('送金相手を選択してください');
      return;
    }
    if (amount == null || amount <= 0) {
      _toast('金額を正しく入力してください');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _ledgerService.recordTransfer(
        communityId: community.id,
        fromUid: widget.user.uid,
        toUid: target,
        amount: amount,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        createdBy: widget.user.uid,
        enforceSufficientFunds: false,
      );
      TransactionEventBus.instance.notify();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      final formatted = formatError(e, st);
      showCopyableErrorSnack(
        context: context,
        heading: '送金に失敗しました',
        error: formatted,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitRequest(_CommunityOption community) async {
    final amount = _parseAmount(_requestAmountCtrl.text);
    final target = _requestTargetUid;
    if (target == null || target.isEmpty) {
      _toast('請求先を選択してください');
      return;
    }
    if (amount == null || amount <= 0) {
      _toast('金額を正しく入力してください');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _requestService.createRequest(
        communityId: community.id,
        fromUid: widget.user.uid,
        toUid: target,
        amount: amount,
        memo: _requestMemoCtrl.text.trim().isEmpty
            ? null
            : _requestMemoCtrl.text.trim(),
        createdBy: widget.user.uid,
      );
      TransactionEventBus.instance.notify();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      final formatted = formatError(e, st);
      showCopyableErrorSnack(
        context: context,
        heading: '請求に失敗しました',
        error: formatted,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitSplit(_CommunityOption community) async {
    final total = _parseAmount(_splitAmountCtrl.text);
    if (_splitTargets.isEmpty) {
      _toast('割り勘の対象メンバーを選択してください');
      return;
    }
    if (total == null || total <= 0) {
      _toast('合計金額を正しく入力してください');
      return;
    }
    setState(() => _submitting = true);
    try {
      final calculation = await _requestService.createSplitRequests(
        communityId: community.id,
        requesterUid: widget.user.uid,
        targetUids: _splitTargets.toList(),
        totalAmount: total,
        precision: community.precision,
        roundingMode: _splitRoundingMode,
        memo: _splitMemoCtrl.text.trim().isEmpty
            ? '割り勘'
            : _splitMemoCtrl.text.trim(),
      );
      TransactionEventBus.instance.notify();
      if (_splitRoundingMode == SplitRoundingMode.floor &&
          calculation.remainder > 0) {
        _toast(
          '端数 ${calculation.remainder.toStringAsFixed(community.precision)} ${community.symbol} は依頼者負担になります',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      final formatted = formatError(e, st);
      showCopyableErrorSnack(
        context: context,
        heading: '割り勘の作成に失敗しました',
        error: formatted,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  num? _parseAmount(String raw) {
    final sanitized = raw.replaceAll(',', '').trim();
    if (sanitized.isEmpty) return null;
    return num.tryParse(sanitized);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  TextStyle _labelStyle() => const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87);

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_add, size: 32, color: kBrandBlue),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CommunityOption {
  const _CommunityOption({
    required this.id,
    required this.name,
    required this.symbol,
    required this.precision,
  });
  final String id;
  final String name;
  final String symbol;
  final int precision;
}

class _MemberOption {
  const _MemberOption({
    required this.uid,
    required this.name,
    required this.isCurrentUser,
    this.isCentralBank = false,
  });
  final String uid;
  final String name;
  final bool isCurrentUser;
  final bool isCentralBank;
}

class _TransferForm extends StatelessWidget {
  const _TransferForm({
    required this.members,
    required this.amountCtrl,
    required this.memoCtrl,
    required this.onSubmit,
    required this.submitting,
    required this.targetUid,
    required this.onChangedTarget,
  });

  final List<_MemberOption> members;
  final TextEditingController amountCtrl;
  final TextEditingController memoCtrl;
  final VoidCallback onSubmit;
  final bool submitting;
  final String? targetUid;
  final ValueChanged<String?> onChangedTarget;

  @override
  Widget build(BuildContext context) {
    final others =
        members.where((m) => !m.isCurrentUser).toList(growable: false);
    if (others.isEmpty) {
      return const Center(child: Text('他のメンバーがまだいません'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('金額を入力'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: targetUid,
            items: [
              for (final member in others)
                DropdownMenuItem(value: member.uid, child: Text(member.name)),
            ],
            decoration: _inputDecoration('送金相手'),
            onChanged: onChangedTarget,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: memoCtrl,
            decoration: _inputDecoration('メモ（任意）'),
          ),
          const SizedBox(height: 24),
          _SubmitButton(label: '送金する', onPressed: submitting ? null : onSubmit),
        ],
      ),
    );
  }
}

class _RequestForm extends StatelessWidget {
  const _RequestForm({
    required this.members,
    required this.amountCtrl,
    required this.memoCtrl,
    required this.onSubmit,
    required this.submitting,
    required this.targetUid,
    required this.onChangedTarget,
  });

  final List<_MemberOption> members;
  final TextEditingController amountCtrl;
  final TextEditingController memoCtrl;
  final VoidCallback onSubmit;
  final bool submitting;
  final String? targetUid;
  final ValueChanged<String?> onChangedTarget;

  @override
  Widget build(BuildContext context) {
    final others =
        members.where((m) => !m.isCurrentUser && !m.isCentralBank).toList();
    if (others.isEmpty) {
      return const Center(child: Text('他のメンバーがまだいません'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('金額を入力'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: targetUid,
            items: [
              for (final member in others)
                DropdownMenuItem(
                  value: member.uid,
                  child:
                      Text(member.isCentralBank ? '中央銀行（承認が必要）' : member.name),
                ),
            ],
            decoration: _inputDecoration('請求先を選択'),
            onChanged: onChangedTarget,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: memoCtrl,
            decoration: _inputDecoration('メモ（任意）'),
          ),
          if (targetUid == kCentralBankUid) ...[
            const SizedBox(height: 12),
            const Text('※ 中央銀行への請求は設定権限者の承認後に入金されます',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 24),
          _SubmitButton(
              label: '請求を作成', onPressed: submitting ? null : onSubmit),
        ],
      ),
    );
  }
}

class _SplitForm extends StatelessWidget {
  const _SplitForm({
    required this.members,
    required this.totalCtrl,
    required this.memoCtrl,
    required this.targets,
    required this.submitting,
    required this.onSubmit,
    required this.onChangedTargets,
    required this.onChangedRounding,
    required this.roundingMode,
    required this.precision,
  });

  final List<_MemberOption> members;
  final TextEditingController totalCtrl;
  final TextEditingController memoCtrl;
  final Set<String> targets;
  final bool submitting;
  final VoidCallback onSubmit;
  final ValueChanged<Set<String>> onChangedTargets;
  final ValueChanged<SplitRoundingMode> onChangedRounding;
  final SplitRoundingMode roundingMode;
  final int precision;

  @override
  Widget build(BuildContext context) {
    final chips =
        members.where((m) => !m.isCurrentUser && !m.isCentralBank).toList();
    if (chips.isEmpty) {
      return const Center(child: Text('割り勘できるメンバーがいません'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: totalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('合計金額'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in chips)
                FilterChip(
                  label: Text(member.name),
                  selected: targets.contains(member.uid),
                  onSelected: (selected) {
                    final updated = Set<String>.from(targets);
                    if (selected) {
                      updated.add(member.uid);
                    } else {
                      updated.remove(member.uid);
                    }
                    onChangedTargets(updated);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SplitRoundingSelector(
            roundingMode: roundingMode,
            onChanged: onChangedRounding,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: memoCtrl,
            decoration: _inputDecoration('メモ（任意）'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: totalCtrl,
            builder: (_, value, __) => _SplitPreviewCard(
              totalText: value.text,
              targets: targets,
              precision: precision,
              roundingMode: roundingMode,
            ),
          ),
          const SizedBox(height: 24),
          _SubmitButton(
              label: '割り勘を作成', onPressed: submitting ? null : onSubmit),
        ],
      ),
    );
  }
}

class _SplitRoundingSelector extends StatelessWidget {
  const _SplitRoundingSelector({
    required this.roundingMode,
    required this.onChanged,
  });

  final SplitRoundingMode roundingMode;
  final ValueChanged<SplitRoundingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('丸め設定', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<SplitRoundingMode>(
          value: roundingMode,
          decoration: _inputDecoration('丸め方法'),
          items: [
            for (final mode in SplitRoundingMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(mode.label),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) onChanged(mode);
          },
        ),
      ],
    );
  }
}

class _SplitPreviewCard extends StatelessWidget {
  const _SplitPreviewCard({
    required this.totalText,
    required this.targets,
    required this.precision,
    required this.roundingMode,
  });

  final String totalText;
  final Set<String> targets;
  final int precision;
  final SplitRoundingMode roundingMode;

  @override
  Widget build(BuildContext context) {
    final sanitized = totalText.replaceAll(',', '').trim();
    final total = num.tryParse(sanitized);
    if (total == null || total <= 0 || targets.isEmpty) {
      return const SizedBox.shrink();
    }
    SplitCalculation calculation;
    try {
      calculation = calculateSplitAllocations(
        totalAmount: total,
        participantCount: targets.length,
        precision: precision,
        roundingMode: roundingMode,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }

    final minShare = calculation.amounts
        .reduce((value, element) => value < element ? value : element);
    final maxShare = calculation.amounts
        .reduce((value, element) => value > element ? value : element);
    final shareText = minShare == maxShare
        ? '1人あたり ${_formatAmount(minShare, precision)}'
        : '1人あたり ${_formatAmount(minShare, precision)}〜${_formatAmount(maxShare, precision)}';

    final remainderText =
        roundingMode == SplitRoundingMode.floor && calculation.remainder > 0
            ? '端数 ${_formatAmount(calculation.remainder, precision)} は依頼者負担'
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shareText,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.black87)),
          if (remainderText != null) ...[
            const SizedBox(height: 4),
            Text(remainderText, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: kBrandGrad,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              textStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: onPressed,
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: kLightGray,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBrandBlue, width: 2),
      ),
    );

String _formatAmount(double value, int precision) {
  return value.toStringAsFixed(precision);
}
