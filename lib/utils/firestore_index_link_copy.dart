import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

/// Runs [run] and if a [FirebaseException] occurs containing a Firebase
/// console index URL, extracts the URL, copies it to the clipboard and
/// shows a SnackBar with an action to open the URL.
Future<T> withIndexLinkCopy<T>(BuildContext context, Future<T> Function() run) async {
  try {
    return await run();
  } on FirebaseException catch (e) {
    final msg = e.message ?? '';
    // Firebase console index URL pattern
    final m = RegExp(r'https:\/\/console\.firebase\.google\.com[^\s)\]]+')
        .firstMatch(msg);
    final url = m?.group(0);
    if (url != null && url.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: url));
      } catch (_) {}
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('インデックス作成のURLをコピーしました'),
          action: SnackBarAction(
            label: '開く',
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
            },
          ),
        ),
      );
    }
    rethrow;
  }
}

/// Variant usable from non-UI/service code. If an index-required FirebaseException
/// contains a console URL, this will copy it to the clipboard and optionally
/// call [onIndexUrl] with the URL. It does not show UI (no SnackBar).
Future<T> withIndexLinkCopyForService<T>(Future<T> Function() run, {void Function(String url)? onIndexUrl}) async {
  try {
    return await run();
  } on FirebaseException catch (e) {
    final msg = e.message ?? '';
    final m = RegExp(r'https:\/\/console\.firebase\.google\.com[^\s)\]]+').firstMatch(msg);
    final url = m?.group(0);
    if (url != null && url.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: url));
      } catch (_) {}
      try {
        if (onIndexUrl != null) onIndexUrl(url);
      } catch (_) {}
    }
    rethrow;
  }
}
