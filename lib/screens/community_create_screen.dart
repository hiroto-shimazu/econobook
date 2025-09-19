// lib/screens/community_create_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool _discoverable = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _descCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('コミュニティ作成', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

            SwitchListTile.adaptive(
              title: const Text('一般公開（閲覧と参加申請を許可）'),
              value: _discoverable,
              onChanged: (v) => setState(() => _discoverable = v),
            ),

            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: kBrandGrad, borderRadius: BorderRadius.all(Radius.circular(999)),
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
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
        child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w700)),
      );

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

    // ---- バリデーション ----
    if (name.length < 2 || name.length > 40) {
      _toast('コミュニティ名は2〜40文字で入力してください'); return;
    }
    final symbolOk = RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(symbol);
    if (!symbolOk) {
      _toast('通貨シンボルは2〜8文字の半角英数で入力してください'); return;
    }

    setState(() => _loading = true);
    try {
      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();
      final communities = fs.collection('communities');
      final memberships = fs.collection('memberships');

      final docRef = communities.doc(); // 新規 ID
      final invite = _genCode(6);

      batch.set(docRef, {
        'name': name,
        'symbol': symbol,
        'description': desc,
        'coverUrl': cover,
        'discoverable': _discoverable,
        'ownerUid': user.uid,
        'admins': [user.uid],
        'membersCount': 1,
        'inviteCode': invite,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),

        // 将来の拡張（通貨/中央銀行っぽいメタ）
        'currency': {
          'code': symbol,
          'precision': 2,
          'supplyModel': 'unlimited', // or 'capped'
          'txFeeBps': 0, // basis points
        },
      });

      batch.set(memberships.doc(), {
        'uid': user.uid,
        'cid': docRef.id,
        'role': 'owner',
        'balance': 0,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      _toast('作成しました（招待コード: $invite）');
      Navigator.pop(context, true); // Communities に戻る（true を返す）
    } catch (e) {
      _toast('作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _genCode(int len) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 認識しづらい文字は除外
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}