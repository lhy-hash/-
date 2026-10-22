import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 手机端 / 电脑模拟观众端 = client；商家管理后台 = admin
enum AppRole { client, admin }

AppRole? _runtimeRole;

void setRuntimeRole(AppRole role) {
  _runtimeRole = role;
}

AppRole resolveAppRole({List<String>? args}) {
  if (_runtimeRole != null) return _runtimeRole!;

  for (final raw in args ?? const <String>[]) {
    final a = raw.trim().toLowerCase();
    if (a == '--role=client' || a == 'role=client' || a == '--client') {
      return AppRole.client;
    }
    if (a == '--role=admin' || a == 'role=admin' || a == '--admin') {
      return AppRole.admin;
    }
  }

  const forced = String.fromEnvironment('XILE_ROLE', defaultValue: '');
  if (forced == 'client') return AppRole.client;
  if (forced == 'admin') return AppRole.admin;

  if (kIsWeb) return AppRole.admin;
  try {
    if (Platform.isAndroid || Platform.isIOS) return AppRole.client;
  } catch (_) {}
  return AppRole.admin;
}

bool get isClientApp => resolveAppRole() == AppRole.client;
bool get isAdminApp => resolveAppRole() == AppRole.admin;
