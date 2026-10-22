import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthUser {
  const AuthUser({
    required this.token,
    required this.username,
    required this.displayName,
  });

  final String token;
  final String username;
  final String displayName;
}

class AuthService {
  AuthService({required this.baseUrl});

  String baseUrl;
  AuthUser? current;

  String get _root {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  File _authFile() {
    if (!kIsWeb && Platform.isWindows) {
      final appdata = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      final dir = Directory('$appdata${Platform.pathSeparator}XileLive');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}auth.json');
    }
    if (!kIsWeb && Platform.isAndroid) {
      final dir = Directory('/data/data/com.xile.ai_digital_live/files');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
      } catch (_) {}
      return File('${dir.path}/xile_auth.json');
    }
    return File('${Directory.systemTemp.path}${Platform.pathSeparator}xile_auth.json');
  }

  Future<void> loadSaved() async {
    try {
      final f = _authFile();
      if (!f.existsSync()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map && raw['token'] != null && raw['username'] != null) {
        final token = '${raw['token']}'.trim();
        final username = '${raw['username']}'.trim();
        if (token.isEmpty || username.isEmpty || token == 'null') return;
        current = AuthUser(
          token: token,
          username: username,
          displayName: '${raw['displayName'] ?? username}',
        );
      }
    } catch (_) {}
  }

  Future<void> _persist(AuthUser user) async {
    current = user;
    try {
      final f = _authFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'token': user.token,
        'username': user.username,
        'displayName': user.displayName,
      }));
    } catch (_) {}
  }

  Future<void> logout() async {
    current = null;
    try {
      final f = _authFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<AuthUser> login(String username, String password) async {
    return _authRequest(
      path: '/api/xile/auth/login',
      payload: {'username': username.trim(), 'password': password},
      failLabel: '登录失败',
    );
  }

  Future<AuthUser> register(
    String username,
    String password, {
    String? displayName,
  }) async {
    final name = (displayName ?? username).trim();
    return _authRequest(
      path: '/api/xile/auth/register',
      payload: {
        'username': username.trim(),
        'password': password,
        'displayName': name.isEmpty ? username.trim() : name,
      },
      failLabel: '注册失败',
    );
  }

  Future<AuthUser> _authRequest({
    required String path,
    required Map<String, dynamic> payload,
    required String failLabel,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_root$path'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: utf8.encode(jsonEncode(payload)),
          )
          .timeout(const Duration(seconds: 10));
    } on SocketException {
      throw Exception('连不上服务器($_root)，请确认电脑引擎已开且手机同一 Wi‑Fi');
    } on http.ClientException {
      throw Exception('连不上服务器($_root)，请检查网络与引擎地址');
    } on TimeoutException {
      throw Exception('连接超时，请确认引擎已启动：$_root');
    } catch (e) {
      final s = e.toString();
      if (s.contains('TimeoutException') || s.contains('timed out')) {
        throw Exception('连接超时，请确认引擎已启动：$_root');
      }
      rethrow;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('$failLabel（HTTP ${res.statusCode}）');
    }

    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw Exception('$failLabel：服务器返回不是 JSON，请确认引擎地址正确');
    }
    if (body is! Map) {
      throw Exception(failLabel);
    }
    final code = body['code'];
    final ok = code == 0 || code == '0';
    if (!ok || body['data'] is! Map) {
      throw Exception('${body['msg'] ?? failLabel}');
    }
    final d = Map<String, dynamic>.from(body['data'] as Map);
    final token = '${d['token'] ?? ''}'.trim();
    final uname = '${d['username'] ?? ''}'.trim();
    if (token.isEmpty || token == 'null' || uname.isEmpty || uname == 'null') {
      throw Exception('$failLabel：未返回有效账号信息');
    }
    final user = AuthUser(
      token: token,
      username: uname,
      displayName: '${d['displayName'] ?? uname}',
    );
    await _persist(user);
    return user;
  }
}
