import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'error_formatter.dart';

void showCopyableErrorSnack({
  required BuildContext context,
  required String heading,
  required FormattedError error,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final body = '$heading: ${error.message}';
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      duration: const Duration(days: 365),
      content: Row(
        children: [
          Expanded(
            child: SelectableText(
              body,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          IconButton(
            tooltip: 'コピー',
            icon: const Icon(Icons.copy, size: 20, color: Colors.white),
            onPressed: () async {
              final buffer = StringBuffer(body);
              if (error.stackTrace != null && error.stackTrace!.isNotEmpty) {
                buffer
                  ..writeln()
                  ..writeln(error.stackTrace);
              }
              try {
                await Clipboard.setData(ClipboardData(text: buffer.toString()));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('エラー内容をコピーしました'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (_) {}
            },
          ),
          if ((error.stackTrace != null && error.stackTrace!.isNotEmpty) ||
              (error.raw != null && error.raw!.isNotEmpty))
            IconButton(
              tooltip: '詳細',
              icon: const Icon(Icons.info_outline, size: 20, color: Colors.white),
              onPressed: () {
                _showErrorDetailDialog(context, heading, error);
              },
            ),
        ],
      ),
    ),
  );
}

void _showErrorDetailDialog(
  BuildContext context,
  String heading,
  FormattedError error,
) {
  final parts = <String>[];
  parts.add('Message:\n${error.message}');
  if (error.raw != null && error.raw!.isNotEmpty) {
    parts.add('Raw error:\n${error.raw}');
  }
  if (error.stackTrace != null && error.stackTrace!.isNotEmpty) {
    parts.add('Stack trace:\n${error.stackTrace}');
  }
  final detail = parts.join('\n\n');

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(heading),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: SingleChildScrollView(
          child: SelectableText(detail),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final payload = detail;
            try {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('詳細をコピーしました'),
                  duration: Duration(seconds: 2),
                ),
              );
            } catch (_) {}
          },
          child: const Text('コピー'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}
