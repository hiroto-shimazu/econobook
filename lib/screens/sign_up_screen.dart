import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  bool _showPass2 = false;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _pass.dispose(); _pass2.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final pass = _pass.text;
    final pass2 = _pass2.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty || pass2.isEmpty) {
      _toast('未入力の項目があります'); return;
    }
    if (pass != pass2) { _toast('パスワードが一致しません'); return; }
    if (pass.length < 6) { _toast('パスワードは6文字以上にしてください'); return; }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass)
          .timeout(const Duration(seconds: 20));

      await cred.user?.updateDisplayName(name).timeout(const Duration(seconds: 10));

      await FirebaseFirestore.instance.doc('users/${cred.user!.uid}').set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.pop(context);
      _toast('アカウントを作成しました。ログインしてください。');
    } on TimeoutException {
      _toast('通信がタイムアウトしました。ネットワークを確認してください');
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'このメールアドレスは既に使用されています',
        'invalid-email'        => 'メールアドレスの形式が正しくありません',
        'weak-password'        => 'パスワードが弱すぎます',
        'operation-not-allowed'=> 'Email/Password が無効です（Consoleで有効化してください）',
        _                      => '作成に失敗しました (${e.code})',
      };
      _toast(msg);
    } catch (e) {
      _toast('作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0D80F2);
    const brandWhite = Colors.white;
    const lightGray = Color(0xFFF0F2F5);
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textSecondary = textPrimary.withOpacity(0.6);

    return Scaffold(
      backgroundColor: brandWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: '戻る',
          onPressed: () => Navigator.pop(context),
          icon: ShaderMask(
            shaderCallback: (Rect bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          ),
        ),
        centerTitle: true,
        title: const Text(''),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _Field(label: '名前', hint: 'あなたの名前', controller: _name,
                        fill: lightGray, primary: textPrimary, secondary: textSecondary, brand: brandBlue),
                    const SizedBox(height: 16),
                    _Field(label: 'メールアドレス', hint: 'your@email.com', controller: _email,
                        keyboard: TextInputType.emailAddress,
                        fill: lightGray, primary: textPrimary, secondary: textSecondary, brand: brandBlue),
                    const SizedBox(height: 16),
                    // パスワード
                    TextField(
                      controller: _pass,
                      obscureText: !_showPass,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'パスワード',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                            ).createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: const Icon(Icons.lock, size: 22, color: Colors.white),
                          ),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showPass = !_showPass),
                          icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                          tooltip: _showPass ? '非表示' : '表示',
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: brandBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // パスワード（確認）
                    TextField(
                      controller: _pass2,
                      obscureText: !_showPass2,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'パスワードの確認',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                            ).createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: const Icon(Icons.lock_outline, size: 22, color: Colors.white),
                          ),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showPass2 = !_showPass2),
                          icon: Icon(_showPass2 ? Icons.visibility_off : Icons.visibility),
                          tooltip: _showPass2 ? '非表示' : '表示',
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: brandBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      onPressed: _loading ? null : _createAccount,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('アカウントを作成'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fill,
    required this.primary,
    required this.secondary,
    required this.brand,
    this.obscure = false,
    this.keyboard,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Color fill, primary, secondary, brand;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: brand, width: 2),
            ),
          ),
          style: TextStyle(color: primary),
        ),
      ],
    );
  }
}