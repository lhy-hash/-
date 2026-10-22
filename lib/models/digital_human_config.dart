import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 数字人引擎类型
enum DhProvider {
  /// 本地 LiveTalking（GPU）
  local,
  /// 百度曦灵 · 实时互动直播
  baidu,
}

class DigitalHumanConfig {
  DigitalHumanConfig({
    this.enabled = true,
    this.provider = DhProvider.local,
    this.engineBaseUrl = 'http://127.0.0.1:8010',
    this.avatarId = 'user_upload_host',
    this.hostPresenceId = 'host_upload',
    this.previewPath = '/index.html',
    this.rtmpUrl = '',
    this.platformHint = 'douyin',
    this.baiduAppId = '',
    this.baiduAppKey = '',
    this.baiduFigureId = 'A2A_V2-muqing',
    this.baiduTtsPer = '5118',
    this.baiduTtsSpd = 5,
    this.baiduTtsPit = 5,
    this.baiduTtsVol = 5,
    this.voiceProfileId = 'upload_natural',
    this.baiduCameraId = '0',
    this.baiduAsrApiKey = '',
    this.baiduAsrSecretKey = '',
  });

  bool enabled;
  DhProvider provider;

  /// 本地 LiveTalking 地址
  String engineBaseUrl;
  String avatarId;
  /// 站立/坐播形象包（男女声 + 动作配置）
  String hostPresenceId;
  String previewPath;
  String rtmpUrl;
  String platformHint;

  /// 百度曦灵 AppID / AppKey（在 https://xiling.cloud.baidu.com 创建）
  String baiduAppId;
  String baiduAppKey;
  /// 形象 ID，见曦灵公共形象列表
  String baiduFigureId;
  /// 音色 per / 语速音调音量（更接近真人时语速勿过慢）
  String baiduTtsPer;
  int baiduTtsSpd;
  int baiduTtsPit;
  int baiduTtsVol;
  /// 内置 HostVoiceProfile.id；空则按主播名自动分配
  String voiceProfileId;
  String baiduCameraId;

  /// 百度智能云「短语音识别」API Key / Secret（应用宝无系统识别时用）
  String baiduAsrApiKey;
  String baiduAsrSecretKey;

  Map<String, dynamic> baiduTtsMap() => {
        'per': int.tryParse(baiduTtsPer) ?? 5118,
        'spd': baiduTtsSpd.clamp(1, 15),
        'pit': baiduTtsPit.clamp(1, 15),
        'vol': baiduTtsVol.clamp(1, 15),
      };

  bool get isBaidu => provider == DhProvider.baidu;
  bool get isLocal => provider == DhProvider.local;

  String get normalizedBase {
    var u = engineBaseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  String get previewUrl => '$normalizedBase$previewPath';

  bool get baiduReady =>
      baiduAppId.trim().isNotEmpty && baiduAppKey.trim().isNotEmpty;

  /// 鉴权：AppId/Signature/ExpireTime
  String buildBaiduToken({Duration ttl = const Duration(hours: 12)}) {
    final appId = baiduAppId.trim();
    final appKey = baiduAppKey.trim();
    if (appId.isEmpty || appKey.isEmpty) {
      throw StateError('请先填写百度曦灵 AppID / AppKey');
    }
    final expire = _isoOffset(DateTime.now().add(ttl));
    final sig = Hmac(sha256, utf8.encode(appKey))
        .convert(utf8.encode('$appId$expire'))
        .toString();
    return '$appId/$sig/$expire';
  }

  String buildRealtimeUrl([String? token]) {
    final t = token ?? buildBaiduToken();
    return Uri.https('open.xiling.baidu.com', '/cloud/realtime', {
      'token': t,
      'initMode': 'noAudio',
      'cameraId': baiduCameraId,
      'figureId': baiduFigureId,
    }).toString();
  }

  static String _isoOffset(DateTime dt) {
    final local = dt.toLocal();
    final o = local.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final oh = o.inHours.abs().toString().padLeft(2, '0');
    final om = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
        '.${three(local.millisecond)}$sign$oh:$om';
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'engineBaseUrl': engineBaseUrl,
        'avatarId': avatarId,
        'hostPresenceId': hostPresenceId,
        'previewPath': previewPath,
        'rtmpUrl': rtmpUrl,
        'platformHint': platformHint,
        'baiduAppId': baiduAppId,
        'baiduAppKey': baiduAppKey,
        'baiduFigureId': baiduFigureId,
        'baiduTtsPer': baiduTtsPer,
        'baiduTtsSpd': baiduTtsSpd,
        'baiduTtsPit': baiduTtsPit,
        'baiduTtsVol': baiduTtsVol,
        'voiceProfileId': voiceProfileId,
        'baiduCameraId': baiduCameraId,
        'baiduAsrApiKey': baiduAsrApiKey,
        'baiduAsrSecretKey': baiduAsrSecretKey,
      };

  factory DigitalHumanConfig.fromJson(Map<String, dynamic> j) {
    final p = '${j['provider'] ?? 'baidu'}';
    return DigitalHumanConfig(
      enabled: j['enabled'] != false,
      provider: p == 'baidu' ? DhProvider.baidu : DhProvider.local,
      engineBaseUrl: (j['engineBaseUrl'] as String?) ?? 'http://127.0.0.1:8010',
      avatarId: (j['avatarId'] as String?) ?? 'dh_xixi',
      hostPresenceId: (j['hostPresenceId'] as String?) ?? 'host_xixi',
      previewPath: (j['previewPath'] as String?) ?? '/index.html',
      rtmpUrl: (j['rtmpUrl'] as String?) ?? '',
      platformHint: (j['platformHint'] as String?) ?? 'douyin',
      baiduAppId: (j['baiduAppId'] as String?) ?? '',
      baiduAppKey: (j['baiduAppKey'] as String?) ?? '',
      baiduFigureId: (j['baiduFigureId'] as String?) ?? 'A2A_V2-muqing',
      baiduTtsPer: (j['baiduTtsPer'] as String?) ?? '5118',
      baiduTtsSpd: (j['baiduTtsSpd'] as num?)?.toInt() ?? 5,
      baiduTtsPit: (j['baiduTtsPit'] as num?)?.toInt() ?? 5,
      baiduTtsVol: (j['baiduTtsVol'] as num?)?.toInt() ?? 5,
      voiceProfileId: (j['voiceProfileId'] as String?) ?? 'xixi_sweet',
      baiduCameraId: (j['baiduCameraId'] as String?) ?? '0',
      baiduAsrApiKey: (j['baiduAsrApiKey'] as String?) ?? '',
      baiduAsrSecretKey: (j['baiduAsrSecretKey'] as String?) ?? '',
    );
  }
}
