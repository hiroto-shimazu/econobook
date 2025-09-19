import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ContactFormScreen extends StatefulWidget {
  const ContactFormScreen({super.key});
  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController(text: FirebaseAuth.instance.currentUser?.email ?? '');
  final _body = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _name.dispose(); _email.dispose(); _body.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final body = _body.text.trim();
    if (email.isEmpty || body.isEmpty) {
      _toast('メールアドレスとお問い合わせ内容を入力してください'); return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('contacts').add({
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'name': name,
        'email': email,
        'body': body,
        'hp': '', // honeypot（ルール側で空文字を要求）
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'new',
      });
      if (!mounted) return;
      _toast('送信しました。確認次第ご連絡します。');
      Navigator.pop(context);
    } catch (e) {
      _toast('送信に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    const grad = LinearGradient(
      begin: Alignment.centerLeft, end: Alignment.centerRight,
      colors: [Color(0xFFE53935), Color(0xFF0D80F2)],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('お問い合わせ'), backgroundColor: Colors.white, elevation: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'お名前（任意）')),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'メールアドレス')),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _body,
                maxLines: null,
                expands: true,
                maxLength: 2000, // 文字数の上限（ルールと合わせておく）
                decoration: InputDecoration(
                  labelText: 'お問い合わせ内容',
                  alignLabelWithHint: true,
                  hintText: 'ご利用環境（端末/OS/ブラウザ）や手順、エラーメッセージなど',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x22000000)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x22000000)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0D80F2), width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(28)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent, foregroundColor: Colors.white,
                      shadowColor: Colors.transparent, textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('送信'),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}