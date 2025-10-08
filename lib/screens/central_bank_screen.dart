import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/community.dart';
import '../dialogs/currency_edit_dialog.dart';
import '../models/community.dart';
import '../services/community_service.dart';
import '../services/ledger_service.dart';
import '../services/request_service.dart';
import '../utils/error_formatter.dart';
import '../utils/error_normalizer.dart';
import '../utils/error_snackbar.dart';
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
  final Set<_BankActionType> _pendingActions = <_BankActionType>{};
  bool _autoInvoiceOnLend = true;

  late Future<Map<String, dynamic>?> _membershipFuture;
  late Future<List<_MemberOption>> _membersFuture;

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
          final membershipHasPermission = membershipRole == 'owner' ||
              (membershipData?['canManageBank'] == true);

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
                          _BankActionsSection(
                            members: members,
                            currency: currency,
                            loading: membersLoading,
                            pendingTypes: _pendingActions,
                            onAction: (type) => _openActionFlow(
                              type: type,
                              currency: currency,
                              members: members,
                            ),
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

  Future<void> _openActionFlow({
    required _BankActionType type,
    required CommunityCurrency currency,
    required List<_MemberOption> members,
  }) async {
    if (members.isEmpty) {
      _showSnack('操作できるメンバーがいません');
      return;
    }
    final config = _bankActionConfigs[type]!;
    final result = await showModalBottomSheet<_BankActionInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BankActionSheet(
        config: config,
        members: members,
        currency: currency,
        initialAutoInvoice: _autoInvoiceOnLend,
        showAutoInvoiceToggle: type == _BankActionType.lend,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _pendingActions.add(type));
    try {
      switch (type) {
        case _BankActionType.issue:
          await _ledgerService.recordTransfer(
            communityId: widget.communityId,
            fromUid: kCentralBankUid,
            toUid: result.memberUid,
            amount: result.amount,
            memo: _normalizeMemo(result.memo, config.defaultMemo),
            createdBy: widget.user.uid,
            entryType: 'issue',
          );
          _showActionSuccess('発行しました', currency, result.amount);
          break;
        case _BankActionType.redeem:
          await _ledgerService.recordTransfer(
            communityId: widget.communityId,
            fromUid: result.memberUid,
            toUid: kCentralBankUid,
            amount: result.amount,
            memo: _normalizeMemo(result.memo, config.defaultMemo),
            createdBy: widget.user.uid,
            entryType: 'redeem',
            enforceSufficientFunds: true,
          );
          _showActionSuccess('回収しました', currency, result.amount);
          break;
        case _BankActionType.lend:
          await _ledgerService.recordTransfer(
            communityId: widget.communityId,
            fromUid: kCentralBankUid,
            toUid: result.memberUid,
            amount: result.amount,
            memo: _normalizeMemo(result.memo, config.defaultMemo),
            createdBy: widget.user.uid,
            entryType: 'lend',
          );
          if (result.createRepaymentRequest) {
            await _requestService.createRequest(
              communityId: widget.communityId,
              fromUid: kCentralBankUid,
              toUid: result.memberUid,
              amount: result.amount,
              memo: _normalizeMemo(
                result.memo,
                '貸出返済のお願い',
              ),
              createdBy: widget.user.uid,
              type: 'invoice',
            );
            _showActionSuccess('貸出と返済請求を登録しました', currency, result.amount);
          } else {
            _showActionSuccess('貸出を記録しました', currency, result.amount);
          }
          _autoInvoiceOnLend = result.createRepaymentRequest;
          break;
        case _BankActionType.invoice:
          await _requestService.createRequest(
            communityId: widget.communityId,
            fromUid: kCentralBankUid,
            toUid: result.memberUid,
            amount: result.amount,
            memo: _normalizeMemo(result.memo, config.defaultMemo),
            createdBy: widget.user.uid,
            type: 'invoice',
          );
          _showActionSuccess('請求を送信しました', currency, result.amount);
          break;
        case _BankActionType.gift:
          await _ledgerService.recordTransfer(
            communityId: widget.communityId,
            fromUid: kCentralBankUid,
            toUid: result.memberUid,
            amount: result.amount,
            memo: _normalizeMemo(result.memo, config.defaultMemo),
            createdBy: widget.user.uid,
            entryType: 'gift',
          );
          _showActionSuccess('贈与しました', currency, result.amount);
          break;
      }
    } catch (e, st) {
      // Debug: print normalized error details to help diagnose boxed JS errors
      final normalized = normalizeError(e);
      debugPrint('NORMALIZED_ERROR: message=${normalized.message} error=${normalized.error} stack=${normalized.stackTrace} raw=${normalized.raw}');

      // Build an operation context if available so that boxed Web errors
      // still carry the transfer operation identifiers for debugging.
      String? opCtx;
      try {
        final opParts = <String>[];
        opParts.add('community=${widget.communityId}');
        // We don't have local access to the last input result here, but the
        // ledger service will have thrown with a message containing idempotency
        // when applicable. Include the normalized raw as fallback to capture
        // any id/key info.
        opParts.add('actor=${widget.user.uid}');
        opCtx = opParts.join(' ');
      } catch (_) {
        opCtx = null;
      }

      // Force show a debug dialog with raw error content. Schedule it for the
      // next frame and use the root navigator so it renders even if other
      // overlays (e.g. bottom sheets) are still tearing down.
      if (mounted) {
      // Schedule debug dialog display on next frame to avoid context issues
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) {
              final size = MediaQuery.of(ctx).size;
              return AlertDialog(
                    title: const Text('デバッグ: Raw Error'),
                    content: SizedBox(
                      width: size.width * 0.9,
                      height: size.height * 0.8,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          'Operation context: ${opCtx ?? 'unknown'}\n'
                          'Error object: ${e.runtimeType}\n'
                          'Error toString: ${e.toString()}\n'
                          'Normalized message: ${normalized.message}\n'
                          'Normalized raw: ${normalized.raw}\n'
                          'Stack: ${st.toString()}',
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('閉じる'),
                      ),
                    ],
                  );
            },
          );
        });
      }
      }

      final formatted = formatError(e, st);
      final heading = '${config.label}に失敗しました';
      // If we have operation context, append it to the raw/details so the
      // copyable snack and detail dialog include it in a structured way.
      FormattedError formattedWithCtx = formatted;
      if (opCtx != null && opCtx.isNotEmpty) {
        final combinedRaw = StringBuffer();
        if (formatted.raw != null && formatted.raw!.isNotEmpty) {
          combinedRaw.writeln(formatted.raw);
          combinedRaw.writeln();
        }
        combinedRaw.writeln('Operation: $opCtx');
        formattedWithCtx = FormattedError(
          message: formatted.message,
          stackTrace: formatted.stackTrace,
          raw: combinedRaw.toString(),
        );
      }
      showCopyableErrorSnack(
        context: context,
        heading: heading,
        error: formattedWithCtx,
      );
    } finally {
      if (mounted) {
        setState(() => _pendingActions.remove(type));
      }
    }
  }

  String _normalizeMemo(String? memo, String fallback) {
    final trimmed = memo?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  void _showActionSuccess(
      String message, CommunityCurrency currency, double amount) {
    final formatted = amount.toStringAsFixed(currency.precision);
    _showSnack('$message ($formatted ${currency.code})');
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

enum _BankActionType { issue, redeem, lend, invoice, gift }

class _BankActionConfig {
  const _BankActionConfig({
    required this.type,
    required this.label,
    required this.description,
    required this.buttonLabel,
    required this.defaultMemo,
    required this.icon,
  });

  final _BankActionType type;
  final String label;
  final String description;
  final String buttonLabel;
  final String defaultMemo;
  final IconData icon;
}

class _BankActionInput {
  const _BankActionInput({
    required this.memberUid,
    required this.amount,
    this.memo,
    this.createRepaymentRequest = false,
  });

  final String memberUid;
  final double amount;
  final String? memo;
  final bool createRepaymentRequest;
}

const Map<_BankActionType, _BankActionConfig> _bankActionConfigs = {
  _BankActionType.issue: _BankActionConfig(
    type: _BankActionType.issue,
    label: 'メンバーに通貨を発行',
    description: '中央銀行の残高から選んだメンバーに通貨を配布します。',
    buttonLabel: '発行',
    defaultMemo: '中央銀行からの発行',
    icon: Icons.trending_up_rounded,
  ),
  _BankActionType.redeem: _BankActionConfig(
    type: _BankActionType.redeem,
    label: 'メンバーから回収',
    description: 'メンバーの残高から中央銀行へ通貨を戻します。',
    buttonLabel: '回収',
    defaultMemo: '中央銀行が回収',
    icon: Icons.trending_down_rounded,
  ),
  _BankActionType.lend: _BankActionConfig(
    type: _BankActionType.lend,
    label: '貸し出しを記録',
    description: '貸し付けを記録し、必要に応じて返済リクエストを作成します。',
    buttonLabel: '貸出',
    defaultMemo: '中央銀行からの貸出',
    icon: Icons.volunteer_activism_outlined,
  ),
  _BankActionType.invoice: _BankActionConfig(
    type: _BankActionType.invoice,
    label: '請求を送信',
    description: '返済や支払いの請求をメンバーに送信します。',
    buttonLabel: '請求',
    defaultMemo: '中央銀行からの請求',
    icon: Icons.request_quote_outlined,
  ),
  _BankActionType.gift: _BankActionConfig(
    type: _BankActionType.gift,
    label: '贈与として送金',
    description: '贈り物として中央銀行から通貨を送ります。',
    buttonLabel: '贈与',
    defaultMemo: '中央銀行からの贈与',
    icon: Icons.card_giftcard_outlined,
  ),
};

const List<_BankActionType> _bankActionOrder = <_BankActionType>[
  _BankActionType.issue,
  _BankActionType.redeem,
  _BankActionType.lend,
  _BankActionType.invoice,
  _BankActionType.gift,
];

class _BankActionsSection extends StatelessWidget {
  const _BankActionsSection({
    required this.members,
    required this.currency,
    required this.loading,
    required this.pendingTypes,
    required this.onAction,
  });

  final List<_MemberOption> members;
  final CommunityCurrency currency;
  final bool loading;
  final Set<_BankActionType> pendingTypes;
  final ValueChanged<_BankActionType> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[
      const Text('中央銀行の操作',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
        'メンバーへの送金や請求を行います（単位: ${currency.code}）。',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 12),
    ];

    if (loading) {
      sections.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (members.isEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '操作できるメンバーがまだいません。メンバーを招待してください。',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    } else {
      for (final type in _bankActionOrder) {
        final config = _bankActionConfigs[type]!;
        sections.add(
          _BankActionRow(
            config: config,
            pending: pendingTypes.contains(type),
            onPressed: () => onAction(type),
          ),
        );
        if (type != _bankActionOrder.last) {
          sections.add(const Divider(height: 24));
        }
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections,
        ),
      ),
    );
  }
}

class _BankActionRow extends StatelessWidget {
  const _BankActionRow({
    required this.config,
    required this.pending,
    required this.onPressed,
  });

  final _BankActionConfig config;
  final bool pending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(config.icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  config.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 104),
            child: FilledButton(
              onPressed: pending ? null : onPressed,
              child: pending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(config.buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankActionSheet extends StatefulWidget {
  const _BankActionSheet({
    required this.config,
    required this.members,
    required this.currency,
    required this.initialAutoInvoice,
    required this.showAutoInvoiceToggle,
  });

  final _BankActionConfig config;
  final List<_MemberOption> members;
  final CommunityCurrency currency;
  final bool initialAutoInvoice;
  final bool showAutoInvoiceToggle;

  @override
  State<_BankActionSheet> createState() => _BankActionSheetState();
}

class _BankActionSheetState extends State<_BankActionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _memoCtrl;
  String? _selectedUid;
  late bool _autoInvoice;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _memoCtrl = TextEditingController();
    _selectedUid = widget.members.isNotEmpty ? widget.members.first.uid : null;
    _autoInvoice = widget.initialAutoInvoice;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  double? _parseAmount(String raw) {
    final sanitized = raw.trim().replaceAll(',', '');
    if (sanitized.isEmpty) return null;
    return double.tryParse(sanitized);
  }

  String? _validateAmount(String? raw) {
    final sanitized = raw?.trim().replaceAll(',', '') ?? '';
    if (sanitized.isEmpty) {
      return '金額を入力してください';
    }
    final value = double.tryParse(sanitized);
    if (value == null) {
      return '数値を入力してください';
    }
    if (value <= 0) {
      return '0より大きい金額を入力してください';
    }
    final dotIndex = sanitized.indexOf('.');
    if (dotIndex != -1) {
      final decimals = sanitized.length - dotIndex - 1;
      if (decimals > widget.currency.precision) {
        if (widget.currency.precision == 0) {
          return '小数点以下は入力できません';
        }
        return '小数点以下は${widget.currency.precision}桁までです';
      }
    }
    return null;
  }

  void _submit() {
    if (_selectedUid == null) return;
    if (!_formKey.currentState!.validate()) return;
    final amount = _parseAmount(_amountCtrl.text);
    if (amount == null) return;
    final memo = _memoCtrl.text.trim();
    Navigator.of(context).pop(
      _BankActionInput(
        memberUid: _selectedUid!,
        amount: amount,
        memo: memo.isEmpty ? null : memo,
        createRepaymentRequest:
            widget.showAutoInvoiceToggle ? _autoInvoice : false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + bottomInset,
              ),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(widget.config.icon,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.config.label,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.config.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedUid,
                        isExpanded: true,
                        items: [
                          for (final member in widget.members)
                            DropdownMenuItem(
                              value: member.uid,
                              child: Text(member.name),
                            ),
                        ],
                        decoration: const InputDecoration(labelText: '対象メンバー'),
                        onChanged: (value) {
                          setState(() => _selectedUid = value);
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '対象メンバーを選択してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: '金額',
                          suffixText: widget.currency.code,
                          helperText: widget.currency.precision > 0
                              ? '小数点以下は${widget.currency.precision}桁まで入力できます'
                              : '整数で入力してください',
                        ),
                        validator: _validateAmount,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _memoCtrl,
                        decoration: InputDecoration(
                          labelText: 'メモ（任意）',
                          hintText: widget.config.defaultMemo,
                        ),
                        maxLines: 2,
                      ),
                      if (widget.showAutoInvoiceToggle) ...[
                        const SizedBox(height: 16),
                        SwitchListTile.adaptive(
                          value: _autoInvoice,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('返済リクエストも同時に作成する'),
                          subtitle: const Text(
                            'オンにすると同額の請求がメンバーに送られます',
                          ),
                          onChanged: (value) =>
                              setState(() => _autoInvoice = value),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _selectedUid == null ? null : _submit,
                              icon: Icon(widget.config.icon),
                              label: Text(widget.config.buttonLabel),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
