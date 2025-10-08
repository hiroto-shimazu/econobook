// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js' as legacy_js;
import 'dart:js_util' as js_util;
import 'error_normalizer.dart';

// Single, consolidated web error normalizer implementation.
// This file extracts useful fields from JS Error-like objects using
// both dart:js_util (modern) and dart:js (legacy) APIs.

T? _dynGet<T>(Object? o, String field) {
  if (o == null) return null;
  try {
    final dyn = o as dynamic;
    // Try property access that may exist on JS interop wrappers.
    final v = dyn?.$field;
    if (v is T) return v;
    if (v == null) return null;
    return v as T?;
  } catch (_) {
    try {
      final dyn = o as dynamic;
      final v = dyn?[field];
      if (v is T) return v;
      if (v == null) return null;
      return v as T?;
    } catch (_) {
      return null;
    }
  }
}

String? _tryJSONStringify(Object? o, {int? space}) {
  if (o == null) return null;
  try {
    final jsonObj = js_util.getProperty(js_util.globalThis, 'JSON');
    final args = <Object?>[o];
    if (space != null) {
      // JSON.stringify(obj, null, space)
      args.add(null);
      args.add(space);
    }
    final str = js_util.callMethod(jsonObj, 'stringify', args);
    if (str is String && str.isNotEmpty && str != '{}' && str != 'null' && str != '[object Object]') {
      return str;
    }
  } catch (_) {}
  return null;
}

Object _unbox(Object e) {
  Object cur = e;
  for (final key in const ['error', 'reason', 'cause']) {
    try {
      final dynField = _dynGet<Object>(cur, key);
      if (dynField != null) {
        cur = dynField;
        continue;
      }
    } catch (_) {}
    try {
      if (js_util.hasProperty(cur, key)) {
        final v = js_util.getProperty<Object?>(cur, key);
        if (v != null) {
          cur = v;
        }
      }
    } catch (_) {}
  }
  return cur;
}

String? _propAsString(Object? o, String key) {
  if (o == null) return null;
  try {
    if (js_util.hasProperty(o, key)) {
      final v = js_util.getProperty<Object?>(o, key);
      if (v == null) return null;
      return v.toString();
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic> _collectProps(Object? o) {
  final picked = <String, dynamic>{};
  if (o == null) return picked;
  for (final k in const ['name', 'message', 'code', 'status', 'details', 'reason', 'cause', 'stack']) {
    final v = _propAsString(o, k);
    if (v != null && v.isNotEmpty) picked[k] = v;
  }

  try {
    final objectCtor = js_util.getProperty(js_util.globalThis, 'Object');
    final rawKeys = js_util.callMethod<Object?>(objectCtor, 'getOwnPropertyNames', <Object?>[o]);
    if (rawKeys is List) {
      for (final key in rawKeys) {
        final keyStr = key?.toString() ?? '';
        if (keyStr.isEmpty || picked.containsKey(keyStr)) continue;
        try {
          final v = js_util.getProperty<Object?>(o, keyStr);
          if (v == null) continue;
          if (v is num || v is bool || v is String) {
            picked[keyStr] = v;
          } else {
            final s = _tryJSONStringify(v) ?? v.toString();
            if (s.isNotEmpty && s != '[object Object]') picked[keyStr] = s;
          }
        } catch (_) {}
      }
    }
  } catch (_) {}

  return picked;
}

// Legacy dart:js helpers
bool _looksLegacy(Object? o) {
  if (o == null) return false;
  final t = o.runtimeType.toString();
  return t.contains('LegacyJavaScriptObject') || o is legacy_js.JsObject;
}

String? _legacyGet(legacy_js.JsObject obj, String key) {
  try {
    final v = obj[key];
    if (v == null) return null;
    return v.toString();
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _collectLegacyProps(legacy_js.JsObject? obj) {
  final picked = <String, dynamic>{};
  if (obj == null) return picked;
  for (final k in const ['name', 'message', 'code', 'status', 'details', 'reason', 'cause', 'stack']) {
    final v = _legacyGet(obj, k);
    if (v != null && v.isNotEmpty) picked[k] = v;
  }
  try {
    final keys = legacy_js.context['Object'].callMethod('getOwnPropertyNames', [obj]);
    if (keys is legacy_js.JsArray) {
      for (final k in keys) {
        final keyStr = k?.toString() ?? '';
        if (keyStr.isEmpty || picked.containsKey(keyStr)) continue;
        try {
          final v = obj[keyStr];
          if (v == null) continue;
          if (v is num || v is bool || v is String) {
            picked[keyStr] = v;
          } else {
            String? s;
            try {
              s = legacy_js.context['JSON'].callMethod('stringify', [v]) as String?;
            } catch (_) {}
            s ??= v.toString();
            if (s.isNotEmpty && s != '[object Object]') picked[keyStr] = s;
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return picked;
}

void _consoleLog(Object? o) {
  if (o == null) return;
  try {
    final console = js_util.getProperty(js_util.globalThis, 'console');
    js_util.callMethod(console, 'error', [o]);
    js_util.callMethod(console, 'dir', [o]);
  } catch (_) {}
}

NormalizedError normalizeErrorImpl(Object error) {
  final wrapperToString = error.toString();
  final wrapperStack = _dynGet<String>(error, 'stack');

  // Unwrap to inner JS object if present
  final unboxed = _unbox(error);
  Object inner = unboxed;

  // Try legacy JsObject route if needed
  Map<String, dynamic>? legacyPicked;
  String? legacyName;
  String? legacyMessage;
  String? legacyCode;
  String? legacyStack;

  if (_looksLegacy(inner)) {
    try {
      final jsObj = inner is legacy_js.JsObject ? inner : legacy_js.JsObject.fromBrowserObject(inner);
      legacyPicked = _collectLegacyProps(jsObj);
      legacyName = legacyPicked['name']?.toString();
      legacyMessage = legacyPicked['message']?.toString();
      legacyCode = legacyPicked['code']?.toString();
      legacyStack = legacyPicked['stack']?.toString();
    } catch (_) {
      // Best effort
    }
  }

  // js_util path (fallbacks to legacy values when present)
  final name = legacyName ?? _propAsString(inner, 'name');
  final message = legacyMessage ?? _propAsString(inner, 'message');
  final code = legacyCode ?? _propAsString(inner, 'code');
  final stack = legacyStack ?? _propAsString(inner, 'stack') ?? wrapperStack;

  // Compose message
  String? combinedMessage = message;
  if ((combinedMessage == null || combinedMessage.isEmpty) && code != null && code.isNotEmpty) {
    combinedMessage = code;
  }
  if ((combinedMessage == null || combinedMessage.isEmpty) && name != null && name.isNotEmpty) {
    combinedMessage = name;
  }
  combinedMessage ??= _tryJSONStringify(inner);
  combinedMessage ??= wrapperToString;

  // Collect properties (both paths)
  final innerPropsJsUtil = _collectProps(inner);
  final innerPropsLegacy = legacyPicked ?? <String, dynamic>{};

  // Build raw payload
  final rawMap = <String, dynamic>{
    'wrapper': {
      'type': error.runtimeType.toString(),
      'message': wrapperToString,
      if (wrapperStack != null && wrapperStack.isNotEmpty) 'stack': wrapperStack,
    },
    'inner': {
      'type': inner.runtimeType.toString(),
      if (name != null) 'name': name,
      if (code != null) 'code': code,
      if (message != null) 'message': message,
      if (stack != null) 'stack': stack,
    },
    'innerProps': {
      if (innerPropsJsUtil.isNotEmpty) 'js_util': innerPropsJsUtil,
      if (innerPropsLegacy.isNotEmpty) 'legacy_js': innerPropsLegacy,
    },
  };

  // If we couldn't collect any inner props, try extra fallbacks to capture
  // a string representation for debugging (helps with LegacyJavaScriptObject).
  if (innerPropsJsUtil.isEmpty && innerPropsLegacy.isEmpty) {
    final extra = <String, dynamic>{};
    try {
      final s = _tryJSONStringify(inner, space: 2);
      if (s != null && s.isNotEmpty) extra['stringified'] = s;
    } catch (_) {}
    try {
      // js_util toString if available
      if (js_util.hasProperty(inner, 'toString')) {
        final ts = js_util.callMethod(inner, 'toString', <Object?>[]);
        if (ts is String && ts.isNotEmpty) extra['toString'] = ts;
      } else {
        final ts = inner.toString();
        if (ts.isNotEmpty) extra['toString'] = ts;
      }
    } catch (_) {}

    if (_looksLegacy(inner)) {
      try {
        final legacyJson = legacy_js.context['JSON'].callMethod('stringify', [inner, null, 2]) as String?;
        if (legacyJson != null && legacyJson.isNotEmpty) extra['legacy_stringified'] = legacyJson;
      } catch (_) {}
      try {
        final jsObj = inner is legacy_js.JsObject ? inner : legacy_js.JsObject.fromBrowserObject(inner);
        final lt = jsObj.callMethod('toString', <Object?>[]);
        if (lt is String && lt.isNotEmpty) extra['legacy_toString'] = lt;
      } catch (_) {}
    }

    if (extra.isNotEmpty) rawMap['extra'] = extra;
  }

  // Log original object for deep inspection
  _consoleLog(unboxed);

  return NormalizedError(
    error: inner,
    stackTrace: stack,
    message: combinedMessage == '[object Object]' ? null : combinedMessage,
    raw: jsonEncode(rawMap),
  );
}