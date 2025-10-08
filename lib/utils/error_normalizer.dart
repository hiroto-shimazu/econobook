import 'error_normalizer_stub.dart'
    if (dart.library.js_util) 'error_normalizer_web.dart';

class NormalizedError {
  const NormalizedError({
    required this.error,
    this.stackTrace,
    this.message,
    this.raw,
  });

  final Object error;
  final String? stackTrace;
  final String? message;
  final String? raw;
}

NormalizedError normalizeError(Object error) => normalizeErrorImpl(error);
