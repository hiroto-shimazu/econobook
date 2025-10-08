import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

import 'error_normalizer.dart';

class FormattedError {
  const FormattedError({required this.message, this.stackTrace, this.raw});

  final String message;
  final String? stackTrace;
  final String? raw; // raw representation of the underlying error object
}

FormattedError formatError(Object error, [StackTrace? stackTrace]) {
  final normalized = normalizeError(error);
  final innerError = normalized.error;
  final resolvedStack = stackTrace?.toString() ?? normalized.stackTrace;
  final message = _resolveMessage(normalized, innerError);

  String? raw;

  // Prefer the normalizer's raw if it looks meaningful.
  final normRaw = normalized.raw?.trim();
  if (normRaw != null &&
      normRaw.isNotEmpty &&
      normRaw != '[object Object]') {
    raw = normRaw;
  } else {
    try {
      if (innerError is String) {
        raw = innerError;
      } else {
        // Try JSON encoding; many platform errors will succeed here.
        try {
          raw = jsonEncode(innerError);
        } catch (_) {
          // If jsonEncode failed (e.g., JS interop object on web), prefer a JSON-like message if present.
          final normMsg = normalized.message?.trim();
          if (normMsg != null &&
              normMsg.isNotEmpty &&
              (normMsg.startsWith('{') || normMsg.startsWith('['))) {
            raw = normMsg;
          } else {
            raw = innerError.toString();
          }
        }
      }
    } catch (_) {
      raw = null;
    }
  }

  // Normalize useless outputs away.
  if (raw != null && raw.trim() == '[object Object]') {
    raw = null;
  }

  // Pretty-print JSON if the raw looks like JSON.
  if (raw != null) {
    final t = raw.trim();
    final looksJson = (t.startsWith('{') && t.endsWith('}')) ||
        (t.startsWith('[') && t.endsWith(']'));
    if (looksJson) {
      try {
        raw = const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
      } catch (_) {/* ignore pretty-print errors */}
    }
  }

  return FormattedError(message: message, stackTrace: resolvedStack, raw: raw);
}

String _describe(Object error) {
  String description;
  if (error is FirebaseException) {
    description = _firebaseMessage(error);
  } else if (error is PlatformException) {
    description = _platformMessage(error);
  } else if (error is AssertionError) {
    description = error.message?.toString() ?? error.toString();
  } else if (error is Exception) {
    description = error.toString();
  } else if (error is Error) {
    description = error.toString();
  } else {
    description = error.toString();
  }

  if (description.trim().isEmpty) {
    return '原因不明のエラーが発生しました (${error.runtimeType})';
  }
  if (description.startsWith('Instance of ')) {
    return '${error.runtimeType}: ${description.replaceFirst('Instance of ', '')}';
  }
  return description;
}

String _resolveMessage(NormalizedError normalized, Object innerError) {
  final normalizedMessage = normalized.message?.trim();
  if (normalizedMessage != null && normalizedMessage.isNotEmpty) {
    if (!_isGenericMessage(normalizedMessage)) {
      return normalizedMessage;
    }
  }

  final described = _describe(innerError).trim();
  if (described.isNotEmpty && !_isGenericMessage(described)) {
    return described;
  }

  final fallback = innerError.toString().trim();
  if (fallback.isNotEmpty && !_isGenericMessage(fallback)) {
    return fallback;
  }

  return '原因不明のエラーが発生しました (${innerError.runtimeType})';
}

bool _isGenericMessage(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed == '[object Object]') return true;
  if (trimmed == 'null') return true;
  if (trimmed == 'undefined') return true;
  if (trimmed.startsWith('Instance of ')) return true;
  // Treat Dart/JS wrapper text as generic so the UI prefers a better message.
  if (trimmed.startsWith('Dart exception thrown from converted Future')) return true;
  if (trimmed.contains('Use the properties \'error\' to fetch the boxed error')) return true;
  return false;
}

String _firebaseMessage(FirebaseException error) {
  final buffer = StringBuffer();
  if (error.message != null && error.message!.trim().isNotEmpty) {
    buffer.write(error.message!.trim());
  } else {
    buffer.write('Firebaseエラー');
  }
  buffer.write(' [${error.code}]');
  return buffer.toString();
}

String _platformMessage(PlatformException error) {
  final buffer = StringBuffer();
  if (error.message != null && error.message!.trim().isNotEmpty) {
    buffer.write(error.message!.trim());
  } else {
    buffer.write('Platformエラー');
  }
  if (error.code.isNotEmpty) {
    buffer.write(' [${error.code}]');
  }
  if (error.details != null) {
    buffer.write(' (${error.details})');
  }
  return buffer.toString();
}
