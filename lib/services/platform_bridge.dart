import 'package:flutter/services.dart';

/// Flutter ↔ 原生音视频/AI 模块通信桥（架构方案落地桩）
/// 未接原生 SDK 时返回模拟结果，便于控台联调。
class PlatformBridge {
  PlatformBridge._();
  static final instance = PlatformBridge._();

  static const media = MethodChannel('com.xile/media');
  static const ai = MethodChannel('com.xile/ai');
  static const mediaEvents = EventChannel('com.xile/media_events');
  static const danmaku = EventChannel('com.xile/danmaku');

  bool nativeBound = false;
  String lastStatus = '未绑定原生推流（演示桩）';

  Future<Map<String, dynamic>> startPush({
    required String rtmpUrl,
    required String roomId,
  }) async {
    try {
      final result = await media.invokeMethod<dynamic>('startPush', {
        'rtmpUrl': rtmpUrl,
        'roomId': roomId,
      });
      nativeBound = true;
      lastStatus = '原生推流已启动';
      return _asMap(result) ?? {'ok': true, 'mode': 'native'};
    } on MissingPluginException {
      lastStatus = '演示模式：已模拟 startPush → $rtmpUrl';
      return {
        'ok': true,
        'mode': 'stub',
        'rtmpUrl': rtmpUrl,
        'roomId': roomId,
        'message': lastStatus,
      };
    } catch (e) {
      lastStatus = '推流失败：$e';
      return {'ok': false, 'message': lastStatus};
    }
  }

  Future<Map<String, dynamic>> stopPush() async {
    try {
      final result = await media.invokeMethod<dynamic>('stopPush');
      lastStatus = '原生推流已停止';
      return _asMap(result) ?? {'ok': true};
    } on MissingPluginException {
      lastStatus = '演示模式：已模拟 stopPush';
      return {'ok': true, 'mode': 'stub', 'message': lastStatus};
    }
  }

  Future<Map<String, dynamic>> sendSpeak({
    required String text,
    String motion = 'speaking',
  }) async {
    try {
      final result = await ai.invokeMethod<dynamic>('speak', {
        'text': text,
        'motion': motion,
      });
      return _asMap(result) ?? {'ok': true};
    } on MissingPluginException {
      return {
        'ok': true,
        'mode': 'stub',
        'text': text,
        'motion': motion,
        'message': '演示：话术已交给 AI 通道（待接原生/云推理）',
      };
    }
  }

  Future<Map<String, dynamic>> setAvatar(String pathOrId) async {
    try {
      final result = await ai.invokeMethod<dynamic>('setAvatar', {
        'avatar': pathOrId,
      });
      return _asMap(result) ?? {'ok': true};
    } on MissingPluginException {
      return {
        'ok': true,
        'mode': 'stub',
        'avatar': pathOrId,
        'message': '演示：形象切换指令已记录',
      };
    }
  }

  Stream<dynamic> watchMediaEvents() {
    try {
      return mediaEvents.receiveBroadcastStream();
    } catch (_) {
      return Stream<dynamic>.periodic(
        const Duration(seconds: 5),
        (i) => {'fps': 28 + (i % 3), 'bitrate': 1800, 'stub': true},
      );
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
