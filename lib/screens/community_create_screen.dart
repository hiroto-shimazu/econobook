// lib/screens/community_create_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community.dart';
import '../services/community_service.dart';

// ---- Brand tokens（他画面と統一）----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

class CommunityCreateScreen extends StatefulWidget {
  const CommunityCreateScreen({super.key});

  @override
  State<CommunityCreateScreen> createState() => _CommunityCreateScreenState();
}

class _CommunityCreateScreenState extends State<CommunityCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController(text: 'PTS');
  final _descCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _currencyNameCtrl = TextEditingController(text: 'コミュニティポイント');
  final _precisionCtrl = TextEditingController(text: '2');
  final _maxSupplyCtrl = TextEditingController();
  final _txFeeCtrl = TextEditingController(text: '0');
  final _borrowLimitCtrl = TextEditingController(text: '0');
  final _interestCtrl = TextEditingController(text: '0');
  bool _discoverable = true;
  bool _allowMinting = true;
  bool _requireApproval = false;
  bool _loading = false;

  final CommunityService _communityService = CommunityService();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _descCtrl.dispose();
    _coverCtrl.dispose();
    _currencyNameCtrl.dispose();
    _precisionCtrl.dispose();
    _maxSupplyCtrl.dispose();
    _txFeeCtrl.dispose();
    _borrowLimitCtrl.dispose();
    _interestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('コミュニティ作成',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _label('コミュニティ名'),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('例）画像情報処理ラボ'),
            ),
            const SizedBox(height: 12),
            _label('通貨シンボル（2〜8文字・半角英数）'),
            TextField(
              controller: _symbolCtrl,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('例）IRON、LAB、PTS'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _label('説明（任意）'),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: _inputDecoration('コミュニティの用途やルールなど'),
            ),
            const SizedBox(height: 12),
            _label('カバー画像URL（任意）'),
            TextField(
              controller: _coverCtrl,
              textInputAction: TextInputAction.done,
              decoration: _inputDecoration('https://...'),
            ),
            const SizedBox(height: 12),
            const Divider(height: 32),
            Text('通貨・中央銀行設定',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _label('通貨名（任意）'),
            TextField(
              controller: _currencyNameCtrl,
              decoration: _inputDecoration('例）Econoポイント'),
            ),
            const SizedBox(height: 12),
            _label('小数点以下桁数'),
            TextField(
              controller: _precisionCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('例）2'),
            ),
            const SizedBox(height: 12),
            _label('最大発行枚数（未設定で無制限）'),
            TextField(
              controller: _maxSupplyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDecoration('例）1000000'),
            ),
            const SizedBox(height: 12),
            _label('取引手数料（bps）'),
            TextField(
              controller: _txFeeCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('例）25 (0.25%)'),
            ),
            const SizedBox(height: 12),
            _label('メンバーあたり借入上限'),
            TextField(
              controller: _borrowLimitCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDecoration('例）500 (未設定で制限なし)'),
            ),
            const SizedBox(height: 12),
            _label('年利（bps）'),
            TextField(
              controller: _interestCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('例）1200 (12%)'),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              title: const Text('メンバーによる自動発行/焼却を許可'),
              subtitle: const Text('無効にすると管理者のみ発行可能'),
              value: _allowMinting,
              onChanged: (v) => setState(() => _allowMinting = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              title: const Text('一般公開（閲覧と参加申請を許可）'),
              value: _discoverable,
              onChanged: (v) => setState(() => _discoverable = v),
            ),
            SwitchListTile.adaptive(
              title: const Text('参加には管理者の承認が必要'),
              value: _requireApproval,
              onChanged: (v) => setState(() => _requireApproval = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: kBrandGrad,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('作成する'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w700)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: kLightGray,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBrandBlue, width: 2),
        ),
      );

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('ログインが必要です');
      return;
    }
    final name = _nameCtrl.text.trim();
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    final desc = _descCtrl.text.trim();
    final cover = _coverCtrl.text.trim();
    final currencyName = _currencyNameCtrl.text.trim();
    final precision = int.tryParse(_precisionCtrl.text.trim()) ?? 2;
    final maxSupply = _maxSupplyCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_maxSupplyCtrl.text.trim());
    final txFeeBps = int.tryParse(_txFeeCtrl.text.trim()) ?? 0;
    final borrowLimit = _borrowLimitCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_borrowLimitCtrl.text.trim());
    final interestBps = int.tryParse(_interestCtrl.text.trim()) ?? 0;

    // ---- バリデーション ----
    if (name.length < 2 || name.length > 40) {
      _toast('コミュニティ名は2〜40文字で入力してください');
      return;
    }
    final symbolOk = RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(symbol);
    if (!symbolOk) {
      _toast('通貨シンボルは2〜8文字の半角英数で入力してください');
      return;
    }

    final safePrecision = precision < 0 ? 0 : (precision > 8 ? 8 : precision);

    final currency = CommunityCurrency(
      name: currencyName.isEmpty ? symbol : currencyName,
      code: symbol,
      precision: safePrecision,
      supplyModel: maxSupply == null ? 'unlimited' : 'capped',
      txFeeBps: txFeeBps,
      expireDays: null,
      creditLimit: borrowLimit?.round() ?? 0,
      interestBps: interestBps,
      maxSupply: maxSupply,
      allowMinting: _allowMinting,
      borrowLimitPerMember: borrowLimit,
    );

    final policy = CommunityPolicy(
      enableRequests: true,
      enableSplitBill: true,
      enableTasks: true,
      enableMediation: false,
      minorsRequireGuardian: true,
      postVisibilityDefault: 'community',
      requiresApproval: _requireApproval,
    );

    setState(() => _loading = true);
    try {
      final community = await _communityService.createCommunity(
        name: name,
        symbol: symbol,
        ownerUid: user.uid,
        description: desc.isEmpty ? null : desc,
        coverUrl: cover.isEmpty ? null : cover,
        discoverable: _discoverable,
        currency: currency,
        policy: policy,
      );

      if (!mounted) return;
      _toast('作成しました（招待コード: ${community.inviteCode}）');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}
