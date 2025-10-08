import 'error_normalizer.dart';

NormalizedError normalizeErrorImpl(Object error) {
  final msg = error.toString();
  return NormalizedError(
    error: error,
    message: msg.isEmpty ? null : msg,
    raw: msg.isEmpty ? null : msg,
  );
}
