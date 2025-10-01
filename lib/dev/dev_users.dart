// lib/dev/dev_users.dart
import 'package:flutter/foundation.dart';

const devUsers = <String>['dev_alice', 'dev_bob', 'dev_minor'];

bool get isDev => kDebugMode;

/// デフォルトの開発用 UID（ログイン省略時に利用）
String getDefaultDevUid() => isDev ? devUsers.first : '';
