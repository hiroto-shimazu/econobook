import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/community.dart';
import '../dialogs/currency_edit_dialog.dart';
import '../models/community.dart';
import '../services/community_service.dart';
import '../services/ledger_service.dart';
import '../services/request_service.dart';
import '../widgets/bank_panels.dart';

class CentralBankScreen extends StatefulWidget {
  const CentralBankScreen({
    super.key,
    required this.communityId,
    required this.user,
    this.communityName,
  });

  final String communityId;
  final User user;
  final String? communityName;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required User user,
    String? communityName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CentralBankScreen(
          communityId: communityId,
          user: user,
          communityName: communityName,
        ),
      ),
    );
  }

  @override
  State<CentralBankScreen> createState() => _CentralBankScreenState();
}

class _CentralBankScreenState extends State<CentralBankScreen> {
  final CommunityService _communityService = CommunityService();
  final LedgerService _ledgerService = LedgerService();
  final RequestService _requestService = RequestService();

  late Future<Map<String, dynamic>?> _membershipFuture;
  late Future<List<_MemberOption>> _membersFuture;

  final TextEditingController _sendAmountCtrl = TextEditingController();
  final TextEditingController _sendMemoCtrl = TextEditingController();
  String? _sendTargetUid;
  bool _sending = false;

  final TextEditingController _requestAmountCtrl = TextEditingController();
  final TextEditingController _requestMemoCtrl = TextEditingController();
  String? _requestTargetUid;
  bool _creatingRequest = false;

  final TextEditingController _loanAmountCtrl = TextEditingController();
  final TextEditingController _loanMemoCtrl = TextEditingController();
  String? _loanTargetUid;
  bool _loaning = false;
  bool _createRepaymentRequest = true;
  final TextEditingController _initialGrantCtrl = TextEditingController();
  final TextEditingController _treasuryAdjustCtrl = TextEditingController();
  String _balanceMode = 'private';
  Set<String> _customVisibleMembers = {};
  bool _visibilityInitialized = false;
  bool _treasuryInitialized = false;
  num _treasuryBalance = 0;
  bool _savingVisibility = false;
  bool _savingInitialGrant = false;
  bool _adjustingTreasury = false;

  @override
  void initState() {
    super.initState();
    _membershipFuture = FirebaseFirestore.instance
        .doc('memberships/${widget.communityId}_${widget.user.uid}')
        .get()
        .then((snap) => snap.data());
    _membersFuture = _loadMembers();
  }

  @override
  void dispose() {
    _sendAmountCtrl.dispose();
    _sendMemoCtrl.dispose();
    _requestAmountCtrl.dispose();
    _requestMemoCtrl.dispose();
    _loanAmountCtrl.dispose();
    _loanMemoCtrl.dispose();
    _initialGrantCtrl.dispose();
    _treasuryAdjustCtrl.dispose();
    super.dispose();
  }

  Future<List<_MemberOption>> _loadMembers() async {
    final membershipSnap = await FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: widget.communityId)
        .get();

    final futures = membershipSnap.docs.map((doc) async {
      final data = doc.data();
      final uid = data['uid'] as String?;
      if (uid == null || uid.isEmpty) return null;
      final userSnap = await FirebaseFirestore.instance.doc('users/$uid').get();
      final userData = userSnap.data();
      final name = (userData?['displayName'] as String?) ?? uid;
      return _MemberOption(uid: uid, name: name);
    });

    final result = <_MemberOption>[];
    for (final future in futures) {
      final option = await future;
      if (option != null && option.uid != kCentralBankUid) {
        result.add(option);
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  double? _parseAmount(String raw) {
    final sanitized = raw.trim().replaceAll(',', '');
    if (sanitized.isEmpty) return null;
    return double.tryParse(sanitized);
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('中央銀行',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _membershipFuture,
        builder: (context, membershipSnap) {
          if (membershipSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final membershipData = membershipSnap.data;
          final membershipRole =
              (membershipData?['role'] as String?) ?? 'member';
          final membershipHasPermission =
              membershipRole == 'owner' || (membershipData?['canManageBank'] == true);

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .doc('communities/${widget.communityId}')
                .snapshots(),
            builder: (context, communitySnap) {
              if (communitySnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (communitySnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('コミュニティ情報の取得に失敗しました: '
                        '${communitySnap.error}'),
                  ),
                );
              }

              final data = communitySnap.data?.data() ?? <String, dynamic>{};
              final currency = CommunityCurrency.fromMap(
                  (data['currency'] as Map<String, dynamic>?) ?? const {});
              final policy = CommunityPolicy.fromMap(
                  (data['policy'] as Map<String, dynamic>?) ?? const {});
              final visibility = CommunityVisibility.fromMap(
                  (data['visibility'] as Map<String, dynamic>?) ?? const {});
              final treasury = CommunityTreasury.fromMap(
                  (data['treasury'] as Map<String, dynamic>?) ?? const {});
              final communityName = widget.communityName ??
                  (data['name'] as String?) ??
                  widget.communityId;
              final inviteCode = (data['inviteCode'] as String?) ?? '';
              final ownerUid = (data['ownerUid'] as String?) ?? '';
              final canManage =
                  membershipHasPermission || ownerUid == widget.user.uid;

              if (!_savingVisibility) {
                final fetchedCustom = visibility.customMembers.toSet();
                if (!_visibilityInitialized ||
                    _balanceMode != visibility.balanceMode ||
                    !_setEquals(_customVisibleMembers, fetchedCustom)) {
                  _balanceMode = visibility.balanceMode;
                  _customVisibleMembers = fetchedCustom;
                  _visibilityInitialized = true;
                }
              }

              if (!_savingInitialGrant && !_adjustingTreasury) {
                _treasuryBalance = treasury.balance;
                if (!_treasuryInitialized) {
                  _initialGrantCtrl.text = treasury.initialGrant == 0
                      ? ''
                      : treasury.initialGrant.toString();
                }
                _treasuryInitialized = true;
              } else {
                _treasuryBalance = treasury.balance;
              }

              return FutureBuilder<List<_MemberOption>>(
                future: _membersFuture,
                builder: (context, membersSnap) {
                  final members = membersSnap.data ?? const [];
                  final membersLoading =
                      membersSnap.connectionState == ConnectionState.waiting;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(communityName,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.black)),
                        const SizedBox(height: 12),
                        if (inviteCode.isNotEmpty)
                          Text('招待コード: $inviteCode',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 16),
                        _CentralBankSettingsCard(
                          currency: currency,
                          policy: policy,
                          balanceMode: visibility.balanceMode,
                          customMembers: visibility.customMembers,
                          onEdit: canManage
                              ? () => showCurrencyEditDialog(
                                    context,
                                    communityId: widget.communityId,
                                    currency: currency,
                                    policy: policy,
                                    service: _communityService,
                                  )
                              : null,
                          canManage: canManage,
                        ),
                        const SizedBox(height: 16),
                        if (!canManage) ...[
                          const Text(
                            '中央銀行設定の変更権限がありません。必要な場合は管理者に依頼してください。',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          _RequestPermissionButton(
                            communityId: widget.communityId,
                            service: _communityService,
                            currentUid: widget.user.uid,
                          ),
                        ],
                        if (canManage) ...[
                          BankSettingRequestsPanel(
                            communityId: widget.communityId,
                            service: _communityService,
                            resolverUid: widget.user.uid,
                            onOpenSettings: () => showCurrencyEditDialog(
                              context,
                              communityId: widget.communityId,
                              currency: currency,
                              policy: policy,
                              service: _communityService,
                            ),
                          ),
                          CentralBankRequestsPanel(
                            communityId: widget.communityId,
                            approverUid: widget.user.uid,
                            requestService: _requestService,
                          ),
                          const SizedBox(height: 16),
                          CentralBankVisibilityCard(
                            balanceMode: _balanceMode,
                            members: members,
                            customSelected:
                                Set<String>.unmodifiable(_customVisibleMembers),
                            onChangedMode: (mode) {
                              setState(() {
                                _balanceMode = mode;
                                if (mode != 'custom') {
                                  _customVisibleMembers.clear();
                                }
                              });
                            },
                            onToggleMember: (uid) {
                              setState(() {
                                if (_customVisibleMembers.contains(uid)) {
                                  _customVisibleMembers.remove(uid);
                                } else {
                                  _customVisibleMembers.add(uid);
                                }
                              });
                            },
                            submitting: _savingVisibility || membersLoading,
                            onSubmit: () {
                              if (membersLoading || _savingVisibility) return;
                              _saveVisibility();
                            },
                          ),
                          const SizedBox(height: 16),
                          CentralBankTreasuryCard(
                            balance: _treasuryBalance,
                            currencyCode: currency.code,
                            precision: currency.precision,
                            initialGrantController: _initialGrantCtrl,
                            adjustController: _treasuryAdjustCtrl,
                            savingInitialGrant: _savingInitialGrant,
                            adjustingBalance: _adjustingTreasury,
                            onSaveInitialGrant: () {
                              if (_savingInitialGrant) return;
                              _updateInitialGrant();
                            },
                            onAdjustBalance: () {
                              if (_adjustingTreasury) return;
                              _applyTreasuryAdjustment();
                            },
                          ),
                          const SizedBox(height: 16),
                          _CentralBankActionCard(
                            title: '中央銀行から送金',
                            description: 'メンバーへ直接残高を送金します',
                            amountController: _sendAmountCtrl,
                            memoController: _sendMemoCtrl,
                            selectedUid: _sendTargetUid,
                            onChangedUid: (value) =>
                                setState(() => _sendTargetUid = value),
                            onSubmit: membersLoading
                                ? null
                                : () => _submitSend(currency),
                            submitting: _sending,
                            members: members,
                          ),
                          const SizedBox(height: 16),
                          _CentralBankActionCard(
                            title: '中央銀行から請求',
                            description: 'メンバーに対して返金や徴収を依頼します',
                            amountController: _requestAmountCtrl,
                            memoController: _requestMemoCtrl,
                            selectedUid: _requestTargetUid,
                            onChangedUid: (value) =>
                                setState(() => _requestTargetUid = value),
                            onSubmit: membersLoading
                                ? null
                                : () => _submitCentralBankRequest(),
                            submitting: _creatingRequest,
                            members: members,
                            actionLabel: '請求を送信',
                          ),
                          const SizedBox(height: 16),
                          _LoanActionCard(
                            amountController: _loanAmountCtrl,
                            memoController: _loanMemoCtrl,
                            selectedUid: _loanTargetUid,
                            onChangedUid: (value) =>
                                setState(() => _loanTargetUid = value),
                            onSubmit: membersLoading
                                ? null
                                : () => _submitLoan(currency),
                            submitting: _loaning,
                            members: members,
                            createRepaymentRequest: _createRepaymentRequest,
                            onChangedCreateRequest: (value) => setState(
                                () => _createRepaymentRequest = value ?? true),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _submitSend(CommunityCurrency currency) async {
    final target = _sendTargetUid;
    final amount = _parseAmount(_sendAmountCtrl.text);
    if (target == null || target.isEmpty) {
      _showSnack('送金先を選択してください');
      return;
    }
    if (amount == null || amount <= 0) {
      _showSnack('金額を正しく入力してください');
      return;
    }

    setState(() => _sending = true);
    try {
      await _ledgerService.recordTransfer(
        communityId: widget.communityId,
        fromUid: kCentralBankUid,
        toUid: target,
        amount: amount,
        memo: _sendMemoCtrl.text.trim().isEmpty
            ? '中央銀行送金'
            : _sendMemoCtrl.text.trim(),
        createdBy: widget.user.uid,
      );
      if (!mounted) return;
      _sendAmountCtrl.clear();
      _sendMemoCtrl.clear();
      setState(() => _sendTargetUid = null);
      _showSnack('送金しました (${amount.toStringAsFixed(currency.precision)})');
    } catch (e) {
      _showSnack('送金に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitCentralBankRequest() async {
    final target = _requestTargetUid;
    final amount = _parseAmount(_requestAmountCtrl.text);
    if (target == null || target.isEmpty) {
      _showSnack('請求先を選択してください');
      return;
    }
    if (amount == null || amount <= 0) {
      _showSnack('金額を正しく入力してください');
      return;
    }

    setState(() => _creatingRequest = true);
    try {
      await _requestService.createRequest(
        communityId: widget.communityId,
        fromUid: kCentralBankUid,
        toUid: target,
        amount: amount,
        memo: _requestMemoCtrl.text.trim().isEmpty
            ? '中央銀行からの請求'
            : _requestMemoCtrl.text.trim(),
        createdBy: widget.user.uid,
      );
      if (!mounted) return;
      _requestAmountCtrl.clear();
      _requestMemoCtrl.clear();
      setState(() => _requestTargetUid = null);
      _showSnack('請求を作成しました');
    } catch (e) {
      _showSnack('請求の作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _creatingRequest = false);
    }
  }

  Future<void> _submitLoan(CommunityCurrency currency) async {
    final target = _loanTargetUid;
    final amount = _parseAmount(_loanAmountCtrl.text);
    if (target == null || target.isEmpty) {
      _showSnack('貸出先を選択してください');
      return;
    }
    if (amount == null || amount <= 0) {
      _showSnack('金額を正しく入力してください');
      return;
    }

    setState(() => _loaning = true);
    try {
      final memoText = _loanMemoCtrl.text.trim();
      await _ledgerService.recordTransfer(
        communityId: widget.communityId,
        fromUid: kCentralBankUid,
        toUid: target,
        amount: amount,
        memo: memoText.isEmpty ? '中央銀行貸出' : memoText,
        createdBy: widget.user.uid,
      );

      if (_createRepaymentRequest) {
        await _requestService.createRequest(
          communityId: widget.communityId,
          fromUid: kCentralBankUid,
          toUid: target,
          amount: amount,
          memo: memoText.isEmpty ? '貸出返済のお願い' : memoText,
          createdBy: widget.user.uid,
        );
      }

      if (!mounted) return;
      _loanAmountCtrl.clear();
      _loanMemoCtrl.clear();
      setState(() {
        _loanTargetUid = null;
      });
      _showSnack('貸出を記録しました (${amount.toStringAsFixed(currency.precision)})');
    } catch (e) {
      _showSnack('貸出の記録に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loaning = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveVisibility() async {
    setState(() => _savingVisibility = true);
    try {
      final visibility = CommunityVisibility(
        balanceMode: _balanceMode,
        customMembers: _balanceMode == 'custom'
            ? _customVisibleMembers.toList()
            : const [],
      );
      await _communityService.updateVisibilitySettings(
        communityId: widget.communityId,
        visibility: visibility,
      );
      _showSnack('残高公開設定を保存しました');
    } catch (e) {
      _showSnack('設定の保存に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _savingVisibility = false;
          _visibilityInitialized = false;
        });
      }
    }
  }

  Future<void> _updateInitialGrant() async {
    final value = double.tryParse(_initialGrantCtrl.text.trim());
    if (value == null) {
      _showSnack('初期配布金額を正しく入力してください');
      return;
    }
    setState(() => _savingInitialGrant = true);
    try {
      await _communityService.updateTreasurySettings(
        communityId: widget.communityId,
        initialGrant: value,
      );
      _showSnack('初期配布金額を更新しました');
    } catch (e) {
      _showSnack('初期配布金額の更新に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _savingInitialGrant = false;
          _treasuryInitialized = false;
        });
      }
    }
  }

  Future<void> _applyTreasuryAdjustment() async {
    final delta = double.tryParse(_treasuryAdjustCtrl.text.trim());
    if (delta == null || delta == 0) {
      _showSnack('加減する金額を入力してください');
      return;
    }
    setState(() => _adjustingTreasury = true);
    try {
      await _communityService.adjustTreasuryBalance(
        communityId: widget.communityId,
        delta: delta,
      );
      _showSnack('中央銀行の残高を更新しました');
      _treasuryAdjustCtrl.clear();
    } catch (e) {
      _showSnack('残高の更新に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _adjustingTreasury = false;
          _treasuryInitialized = false;
        });
      }
    }
  }
}

class _MemberOption {
  const _MemberOption({required this.uid, required this.name});
  final String uid;
  final String name;
}

// (moved proper _CentralBankActionCard definition below)
class _CentralBankSettingsCard extends StatelessWidget {
  const _CentralBankSettingsCard({
    required this.currency,
    required this.policy,
    this.onEdit,
    required this.canManage,
    this.balanceMode,
    this.customMembers = const [],
  });

  final CommunityCurrency currency;
  final CommunityPolicy policy;
  final VoidCallback? onEdit;
  final bool canManage;
  final String? balanceMode;
  final List<String> customMembers;

  @override
  Widget build(BuildContext context) {
    final actionLabel = canManage ? '設定を変更' : '設定を確認';
    final actionIcon = canManage ? Icons.edit : Icons.visibility_outlined;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('中央銀行設定',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _settingsRow('通貨名', currency.name),
            _settingsRow('シンボル', currency.code),
            _settingsRow('小数点以下桁数', '${currency.precision} 桁'),
            _settingsRow(
                '発行方式', currency.supplyModel == 'capped' ? '上限あり' : '無制限'),
            if (currency.maxSupply != null)
              _settingsRow('最大発行枚数', currency.maxSupply!.toString()),
            _settingsRow('取引手数料', '${currency.txFeeBps / 100}%'),
            if (currency.borrowLimitPerMember != null)
              _settingsRow(
                  'メンバー借入上限', currency.borrowLimitPerMember!.toString()),
            _settingsRow('年利', '${currency.interestBps / 100}%'),
            _settingsRow('メンバーによる発行', currency.allowMinting ? '許可' : '管理者のみ'),
            if (currency.expireDays != null)
              _settingsRow('有効期限', '${currency.expireDays}日'),
            _settingsRow('参加承認', policy.requiresApproval ? '承認必須' : '自動参加'),
            if (onEdit != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _settingsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.black87, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _CentralBankActionCard extends StatelessWidget {
  const _CentralBankActionCard({
    required this.title,
    required this.description,
    required this.amountController,
    required this.memoController,
    required this.members,
    required this.selectedUid,
    required this.onChangedUid,
    required this.onSubmit,
    required this.submitting,
    this.actionLabel,
  });

  final String title;
  final String description;
  final TextEditingController amountController;
  final TextEditingController memoController;
  final List<_MemberOption> members;
  final String? selectedUid;
  final ValueChanged<String?> onChangedUid;
  final VoidCallback? onSubmit;
  final bool submitting;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedUid,
              items: [
                for (final member in members)
                  DropdownMenuItem(
                    value: member.uid,
                    child: Text(member.name),
                  ),
              ],
              decoration: const InputDecoration(labelText: '対象メンバー'),
              onChanged: onSubmit == null ? null : onChangedUid,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '金額'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memoController,
              decoration: const InputDecoration(labelText: 'メモ（任意）'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel ?? '送信'),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class CentralBankVisibilityCard extends StatelessWidget {
  const CentralBankVisibilityCard({
    super.key,
    required this.balanceMode,
    required this.members,
    required this.customSelected,
    required this.onChangedMode,
    required this.onToggleMember,
    required this.submitting,
    required this.onSubmit,
  });

  final String balanceMode;
  final List<_MemberOption> members;
  final Set<String> customSelected;
  final ValueChanged<String> onChangedMode;
  final ValueChanged<String> onToggleMember;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('残高公開設定',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _RadioRow(
              label: '全員に公開',
              value: 'everyone',
              groupValue: balanceMode,
              onChanged: onChangedMode,
            ),
            _RadioRow(
              label: '全員非公開',
              value: 'private',
              groupValue: balanceMode,
              onChanged: onChangedMode,
            ),
            _RadioRow(
              label: 'メンバーごとに指定',
              value: 'custom',
              groupValue: balanceMode,
              onChanged: onChangedMode,
            ),
            if (balanceMode == 'custom') ...[
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: members
                    .map(
                      (member) => FilterChip(
                        label: Text(member.name),
                        selected: customSelected.contains(member.uid),
                        onSelected: (_) => onToggleMember(member.uid),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('設定を保存'),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: (val) => onChanged(val ?? value),
      title: Text(label),
    );
  }
}

class CentralBankTreasuryCard extends StatelessWidget {
  const CentralBankTreasuryCard({
    super.key,
    required this.balance,
    required this.currencyCode,
    required this.precision,
    required this.initialGrantController,
    required this.adjustController,
    required this.savingInitialGrant,
    required this.adjustingBalance,
    required this.onSaveInitialGrant,
    required this.onAdjustBalance,
  });

  final num balance;
  final String currencyCode;
  final int precision;
  final TextEditingController initialGrantController;
  final TextEditingController adjustController;
  final bool savingInitialGrant;
  final bool adjustingBalance;
  final VoidCallback onSaveInitialGrant;
  final VoidCallback onAdjustBalance;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('中央銀行残高',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('現在の残高: $currencyCode ${balance.toStringAsFixed(precision)}'),
            const SizedBox(height: 12),
            TextField(
              controller: initialGrantController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '初期配布金額 (新規メンバー)',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: savingInitialGrant ? null : onSaveInitialGrant,
                child: savingInitialGrant
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('初期配布金額を更新'),
              ),
            ),
            const Divider(height: 32),
            TextField(
              controller: adjustController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '残高を加減する (正で加算／負で減算)',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: adjustingBalance ? null : onAdjustBalance,
                child: adjustingBalance
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('残高を更新'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanActionCard extends StatelessWidget {
  const _LoanActionCard({
    required this.amountController,
    required this.memoController,
    required this.members,
    required this.selectedUid,
    required this.onChangedUid,
    required this.onSubmit,
    required this.submitting,
    required this.createRepaymentRequest,
    required this.onChangedCreateRequest,
  });

  final TextEditingController amountController;
  final TextEditingController memoController;
  final List<_MemberOption> members;
  final String? selectedUid;
  final ValueChanged<String?> onChangedUid;
  final VoidCallback? onSubmit;
  final bool submitting;
  final bool createRepaymentRequest;
  final ValueChanged<bool?> onChangedCreateRequest;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('中央銀行から貸出',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('メンバーへ資金を貸し出し、必要に応じて返済リクエストを作成します',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedUid,
              items: [
                for (final member in members)
                  DropdownMenuItem(
                    value: member.uid,
                    child: Text(member.name),
                  ),
              ],
              decoration: const InputDecoration(labelText: '対象メンバー'),
              onChanged: onSubmit == null ? null : onChangedUid,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '貸出金額'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memoController,
              decoration: const InputDecoration(labelText: 'メモ（任意）'),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: createRepaymentRequest,
              onChanged: submitting ? null : onChangedCreateRequest,
              contentPadding: EdgeInsets.zero,
              title: const Text('返済リクエストを同時に作成する'),
              subtitle: const Text('オンにすると同額の請求が自動で登録されます'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('貸出を記録'),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _RequestPermissionButton extends StatefulWidget {
  const _RequestPermissionButton({
    required this.communityId,
    required this.service,
    required this.currentUid,
  });

  final String communityId;
  final CommunityService service;
  final String currentUid;

  @override
  State<_RequestPermissionButton> createState() =>
      _RequestPermissionButtonState();
}

class _RequestPermissionButtonState extends State<_RequestPermissionButton> {
  bool _sending = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('管理者に依頼する', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '希望する変更内容や理由を記入してください',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    try {
                      final message = _controller.text.trim();
                      await widget.service.submitBankSettingRequest(
                        communityId: widget.communityId,
                        requesterUid: widget.currentUid,
                        message: message.isEmpty ? null : message,
                      );
                      if (!mounted) return;
                      _controller.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('リクエストを送信しました')),
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('送信に失敗しました: $e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _sending = false);
                    }
                  },
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('変更をリクエスト'),
          ),
        )
      ],
    );
  }
}
