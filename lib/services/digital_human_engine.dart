import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import '../models/digital_human_config.dart';
import '../models/host_voice_profile.dart';

class EngineHealth {
  const EngineHealth({
    required this.ok,
    required this.message,
    this.latencyMs,
  });

  final bool ok;
  final String message;
  final int? latencyMs;
}

class AvatarTaskStatus {
  const AvatarTaskStatus({
    required this.taskId,
    required this.status,
    required this.progress,
    this.errorMsg = '',
    this.avatarId = '',
  });

  final String taskId;
  final String status;
  final int progress;
  final String errorMsg;
  final String avatarId;

  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
}

typedef JsSpeakDriver = Future<bool> Function(String text, {required bool interrupt});
typedef TtsPayloadBuilder = Map<String, dynamic>? Function();

/// 已经合成好、还没交给手机播的一句
class PreparedTcp {
  const PreparedTcp({
    required this.gen,
    required this.url,
    required this.durationMs,
    required this.syncDelayMs,
  });

  final int gen;
  final String url;
  final int durationMs;
  final int syncDelayMs;
}

/// 本地 LiveTalking 或 百度曦灵实时数字人
class DigitalHumanEngine {
  DigitalHumanEngine();

  DigitalHumanConfig config = DigitalHumanConfig();
  String? sessionId;
  bool connected = false;
  String? lastError;
  DateTime? _baiduSpeakUntil;
  DateTime? _tcpSpeakUntil;
  final AudioPlayer _tcpPlayer = AudioPlayer();
  /// 退出或打断时 +1，后到的播放直接丢掉，避免退出房间还有声音
  int _audioGen = 0;
  int _pendingDurationMs = 0;

  int get audioGen => _audioGen;

  bool get _phoneTcpVoice =>
      !config.isBaidu &&
      (isMjpegSession ||
          config.avatarId == 'user_upload_host' ||
          config.hostPresenceId == 'host_upload');

  /// 由控台注入：每次口播带上当前主播 EdgeTTS 音色
  TtsPayloadBuilder? ttsPayloadBuilder;

  /// 由直播间页面播放声音。走系统播放器时，进房常被网页抢走，退出才响。
  Future<void> Function(String url, [int? syncDelayMs])? onPlayAudio;

  /// 下一句是否打断上一句（给 WebView xilePlay 用）
  bool _nextPlayInterrupt = true;

  bool takePlayInterrupt() {
    final v = _nextPlayInterrupt;
    _nextPlayInterrupt = true;
    return v;
  }

  Completer<void>? _audioEnd;
  Completer<void>? _audioStart;

  void notifyAudioEnded() {
    final c = _audioEnd;
    _audioEnd = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 手机真正出声后再计时，避免还没响就把下一句提前掐进来
  void notifyAudioStarted() {
    final ms = _pendingDurationMs;
    if (ms > 0) {
      _tcpSpeakUntil = DateTime.now()
          .add(Duration(milliseconds: (ms + 600).clamp(800, 120000)));
    }
    final s = _audioStart;
    if (s != null && !s.isCompleted) s.complete();
  }

  /// 等这句在手机上真正播完。超时才放行，避免下一句把声音掐掉。
  Future<void> waitAudioEnd(Duration fallback) {
    final c = Completer<void>();
    _audioEnd = c;
    return c.future.timeout(fallback, onTimeout: () {});
  }

  Future<void> _waitAudioStarted(Duration timeout) {
    final existing = _audioStart;
    if (existing != null && existing.isCompleted) {
      return Future.value();
    }
    final c = existing ?? Completer<void>();
    _audioStart = c;
    return c.future.timeout(timeout, onTimeout: () {});
  }

  /// 由直播间 WebView 注入：百度文本驱动
  JsSpeakDriver? jsSpeakDriver;

  DateTime? get speakUntil => _tcpSpeakUntil ?? _baiduSpeakUntil;

  bool get isMjpegSession =>
      (sessionId ?? '').startsWith('mjpeg-') ||
      (sessionId ?? '') == 'xile-broadcast';

  void updateConfig(DigitalHumanConfig c) {
    config = c;
  }

  Future<EngineHealth> ping() async {
    final sw = Stopwatch()..start();
    if (config.isBaidu) {
      try {
        if (!config.baiduReady) {
          sw.stop();
          return EngineHealth(
            ok: false,
            message: '请填写百度曦灵 AppID / AppKey',
            latencyMs: sw.elapsedMilliseconds,
          );
        }
        final token = config.buildBaiduToken();
        sw.stop();
        return EngineHealth(
          ok: token.isNotEmpty,
          message: '百度鉴权 token 已生成 · 形象 ${config.baiduFigureId}',
          latencyMs: sw.elapsedMilliseconds,
        );
      } catch (e) {
        sw.stop();
        return EngineHealth(
          ok: false,
          message: '百度鉴权失败：$e',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
    }

    try {
      final uri = Uri.parse(config.normalizedBase);
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      sw.stop();
      if (res.statusCode >= 200 && res.statusCode < 500) {
        return EngineHealth(
          ok: true,
          message: '本地引擎可达 ${config.normalizedBase}',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return EngineHealth(
        ok: false,
        message: 'HTTP ${res.statusCode}',
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return EngineHealth(
        ok: false,
        message: '无法连接引擎：$e',
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// 从引擎拉取当前活跃 WebRTC 会话（浏览器打开预览页后会有）
  Future<String?> fetchLatestSessionId() async {
    try {
      final uri = Uri.parse('${config.normalizedBase}/api/admin/sessions');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['code'] != 0) return null;
      final data = body['data'];
      if (data is! Map) return null;
      final list = data['sessions'];
      if (list is! List || list.isEmpty) return null;
      final first = list.first;
      if (first is Map && first['sessionid'] != null) {
        return '${first['sessionid']}';
      }
    } catch (_) {}
    return null;
  }

  /// 若尚未绑定会话，自动附着到当前真正存活的 WebRTC 会话
  Future<bool> ensureSession({bool forceRefresh = false}) async {
    if (!forceRefresh && sessionId != null && sessionId!.isNotEmpty && connected) {
      final live = await fetchLatestSessionId();
      if (live == sessionId) return true;
      if (live != null && live.isNotEmpty) {
        bindSession(live);
        return true;
      }
      clearSession();
      return false;
    }
    final sid = await fetchLatestSessionId();
    if (sid == null || sid.isEmpty) return false;
    bindSession(sid);
    return true;
  }

  void bindSession(String id) {
    sessionId = id;
    connected = id.isNotEmpty;
    lastError = null;
  }

  void clearSession() {
    sessionId = null;
    connected = false;
  }

  Future<bool> speak(
    String text, {
    bool interrupt = true,
    String type = 'echo',
    String? sessionOverride,
  }) async {
    if (!config.enabled) {
      lastError = '未开启真实数字人引擎';
      return false;
    }
    final clean = text
        .replaceAll(RegExp(r'[&<>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return false;

    // 热点 MJPEG / 上传形象：声画走 TCP（慢速/原声 + 口型）
    if (!config.isBaidu &&
        (isMjpegSession ||
            config.avatarId == 'user_upload_host' ||
            config.hostPresenceId == 'host_upload')) {
      final ok = await speakTcp(clean, interrupt: interrupt, rate: '-18%');
      if (ok) return true;
      // 失败再尝试旧 WebRTC human 通道
    }

    if (config.isBaidu) {
      if (jsSpeakDriver == null) {
        lastError = '百度画面尚未就绪：请先打开控台预览';
        return false;
      }
      try {
        final ok = await jsSpeakDriver!(clean, interrupt: interrupt);
        if (ok) {
          lastError = null;
          final sec = (clean.length * 0.22).clamp(1.5, 45.0);
          _baiduSpeakUntil = DateTime.now().add(Duration(milliseconds: (sec * 1000).round()));
        }
        return ok;
      } catch (e) {
        lastError = '百度驱动失败：$e';
        return false;
      }
    }

    Future<bool> postSpeak(String sid) async {
      final uri = Uri.parse('${config.normalizedBase}/human');
      final tts = <String, dynamic>{
        ...?(ttsPayloadBuilder?.call()),
      };
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionid': sid,
              'text': clean,
              'type': type,
              'interrupt': interrupt,
              if (tts.isNotEmpty) 'tts': tts,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['code'] != null && body['code'] != 0) {
          lastError = '引擎返回：${body['msg'] ?? body}';
          return false;
        }
        lastError = null;
        return true;
      }
      lastError = '驱动失败 HTTP ${res.statusCode}: ${res.body}';
      return false;
    }

    try {
      await ensureSession();
      var sid = (sessionOverride != null && sessionOverride.isNotEmpty)
          ? sessionOverride
          : sessionId;
      if (sid == null || sid.isEmpty) {
        lastError = '数字人画面还没接通，请稍候再讲话术';
        return false;
      }
      final ok = await postSpeak(sid);
      if (ok) return true;
      if ((lastError ?? '').contains('session not found')) {
        clearSession();
        await ensureSession(forceRefresh: true);
        sid = sessionId;
        if (sid != null && sid.isNotEmpty) {
          return await postSpeak(sid);
        }
      }
      return false;
    } catch (e) {
      lastError = '驱动异常：$e';
      return false;
    }
  }

  /// 对指定会话列表同时开口（手机画面 + 预览窗同步）
  Future<bool> speakToSessions(
    String text, {
    required List<String> sessionIds,
    bool interrupt = true,
  }) async {
    // 手机口播只合成一次。按会话逐个 speak 会把同一句 TTS 跑两三遍，进房就要等十几秒。
    if (_phoneTcpVoice) {
      return speakTcp(text, interrupt: interrupt, rate: '-18%');
    }
    final ids = sessionIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return speakAll(text, interrupt: interrupt);
    }
    var any = false;
    for (final id in ids) {
      final ok = await speak(text, interrupt: interrupt, sessionOverride: id);
      any = any || ok;
    }
    if (!any) {
      return speakAll(text, interrupt: interrupt);
    }
    return true;
  }

  /// 对引擎上所有会话同时开口（手机端 + 电脑预览窗同步）
  Future<bool> speakAll(String text, {bool interrupt = true}) async {
    if (_phoneTcpVoice) {
      return speakTcp(text, interrupt: interrupt, rate: '-18%');
    }
    final ids = await listSessionIds();
    if (ids.isEmpty) {
      return speak(text, interrupt: interrupt);
    }
    var any = false;
    for (final id in ids) {
      final ok = await speak(text, interrupt: interrupt, sessionOverride: id);
      any = any || ok;
    }
    return any;
  }

  Future<List<String>> listSessionIds() async {
    try {
      final res = await http
          .get(Uri.parse('${config.normalizedBase}/api/admin/sessions'))
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['code'] != 0) return [];
      final data = body['data'];
      if (data is! Map) return [];
      final raw = data['sessions'];
      if (raw is! List) return [];
      final out = <String>[];
      for (final s in raw) {
        if (s is Map && s['sessionid'] != null) {
          final id = '${s['sessionid']}';
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<bool> interrupt() async {
    if (config.isBaidu) {
      _baiduSpeakUntil = DateTime.now();
      if (jsSpeakDriver != null) {
        try {
          await jsSpeakDriver!(' ', interrupt: true);
        } catch (_) {}
      }
      return true;
    }
    _audioGen++;
    _tcpSpeakUntil = null;
    _pendingDurationMs = 0;
    final start = _audioStart;
    _audioStart = null;
    if (start != null && !start.isCompleted) start.complete();
    final end = _audioEnd;
    _audioEnd = null;
    if (end != null && !end.isCompleted) end.complete();
    try {
      await _tcpPlayer.stop();
    } catch (_) {}
    // 口播常发给多会话：打断必须覆盖全部，否则语音提问后主播假死
    final ids = await listSessionIds();
    if ((sessionId ?? '').isNotEmpty && !ids.contains(sessionId)) {
      ids.add(sessionId!);
    }
    // 广播会话也要打断
    if (!ids.contains('xile-broadcast')) ids.add('xile-broadcast');
    if (ids.isEmpty) return true;
    var any = false;
    for (final id in ids) {
      try {
        final uri = Uri.parse('${config.normalizedBase}/interrupt_talk');
        await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sessionid': id}),
        );
        any = true;
      } catch (_) {}
    }
    return any;
  }

  Future<bool?> isSpeaking() async {
    if (config.isBaidu) {
      final until = _baiduSpeakUntil;
      if (until == null) return false;
      return DateTime.now().isBefore(until);
    }
    final tcpUntil = _tcpSpeakUntil;
    if (tcpUntil != null && DateTime.now().isBefore(tcpUntil)) {
      return true;
    }
    if (tcpUntil != null && DateTime.now().isAfter(tcpUntil)) {
      _tcpSpeakUntil = null;
    }
    if (sessionId == null || isMjpegSession) {
      return _tcpSpeakUntil != null &&
          DateTime.now().isBefore(_tcpSpeakUntil!);
    }
    try {
      final uri = Uri.parse('${config.normalizedBase}/is_speaking');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionid': sessionId}),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['data'] is bool) return body['data'] as bool;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _playTcpAudio(String audioUrl, int durationMs, int gen) async {
    if (gen != _audioGen) return;
    final url = audioUrl.startsWith('http')
        ? audioUrl
        : '${config.normalizedBase}$audioUrl';
    try {
      await _tcpPlayer.stop();
      if (gen != _audioGen) return;
      await _tcpPlayer.setReleaseMode(ReleaseMode.stop);
      await _tcpPlayer.setVolume(1.0);
      // 直接播地址，不等整段下载完。下载完再播就是进房要等好几秒。
      await _tcpPlayer.play(UrlSource(url));
      if (gen != _audioGen) {
        await _tcpPlayer.stop();
        return;
      }
    } catch (e) {
      if (gen != _audioGen) return;
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (gen != _audioGen) return;
        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            res.bodyBytes.length < 1000) {
          lastError = '音频下载失败（${res.statusCode}/${res.bodyBytes.length}）';
          return;
        }
        final dir = Directory.systemTemp;
        final file = File(
          '${dir.path}${Platform.pathSeparator}xile_speak_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        await file.writeAsBytes(res.bodyBytes, flush: true);
        if (gen != _audioGen) return;
        await _tcpPlayer.play(DeviceFileSource(file.path));
      } catch (e2) {
        lastError = '音频播放失败：$e2';
        return;
      }
    }
    if (gen != _audioGen) {
      try {
        await _tcpPlayer.stop();
      } catch (_) {}
      return;
    }
    _tcpSpeakUntil = DateTime.now()
        .add(Duration(milliseconds: durationMs.clamp(800, 120000)));
  }

  /// 只合成、不播放。讲解时用来提前备好下一句，避免说完一句再干等。
  Future<PreparedTcp?> prepareTcp(
    String text, {
    bool useOriginal = false,
    String rate = '-18%',
    bool interrupt = false,
  }) async {
    if (!config.enabled || config.isBaidu) return null;
    final gen = _audioGen;
    final clean = text.trim();
    if (!useOriginal && clean.isEmpty) return null;
    try {
      final voice = HostVoiceProfile.byId(config.voiceProfileId) ??
          HostVoiceProfile.byId('upload_natural') ??
          HostVoiceProfile.presets.first;
      final uri = Uri.parse('${config.normalizedBase}/api/xile/speak_tcp');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': clean,
              'interrupt': interrupt,
              'use_original': useOriginal,
              'avatar': config.avatarId.isNotEmpty
                  ? config.avatarId
                  : 'user_upload_host',
              'rate': rate,
              'voice': voice.edgeVoice,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (gen != _audioGen) return null;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        lastError = 'speak_tcp HTTP ${res.statusCode}';
        return null;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['code'] != 0) {
        lastError = '${body is Map ? body['msg'] : body}';
        return null;
      }
      final data = body['data'];
      if (data is! Map) {
        lastError = 'speak_tcp 无数据';
        return null;
      }
      final audioUrl = '${data['audioUrl'] ?? ''}';
      if (audioUrl.isEmpty) {
        lastError = 'speak_tcp 无音频';
        return null;
      }
      final dur = (data['durationMs'] as num?)?.toInt() ?? (clean.length * 280);
      final abs = audioUrl.startsWith('http')
          ? audioUrl
          : '${config.normalizedBase}$audioUrl';
      final sid = '${data['sessionid'] ?? ''}';
      if (sid.isNotEmpty) sessionId = sid;
      lastError = null;
      return PreparedTcp(
        gen: gen,
        url: abs,
        durationMs: dur.clamp(800, 120000),
        syncDelayMs: (data['syncDelayMs'] as num?)?.toInt() ?? 80,
      );
    } catch (e) {
      lastError = 'speak_tcp 异常：$e';
      return null;
    }
  }

  /// 把已经合成好的一句交给手机播，并记时长
  Future<bool> playPreparedTcp(
    PreparedTcp clip, {
    required bool interrupt,
  }) async {
    if (clip.gen != _audioGen) return false;
    _nextPlayInterrupt = interrupt;
    _pendingDurationMs = clip.durationMs;
    _tcpSpeakUntil = DateTime.now().add(
      Duration(milliseconds: (clip.durationMs + 1800).clamp(800, 120000)),
    );
    if (onPlayAudio == null) {
      await _playTcpAudio(clip.url, clip.durationMs, clip.gen);
      return clip.gen == _audioGen && lastError == null;
    }

    Future<bool> kick(bool doInterrupt) async {
      if (clip.gen != _audioGen) return false;
      _nextPlayInterrupt = doInterrupt;
      _audioStart = Completer<void>();
      await onPlayAudio!(clip.url, clip.syncDelayMs);
      await _waitAudioStarted(const Duration(milliseconds: 2200));
      return _audioStart?.isCompleted == true && clip.gen == _audioGen;
    }

    if (await kick(interrupt)) return true;
    // 第一次没真正出声：再推一次，打断卡住的 WebView 音频
    if (clip.gen != _audioGen) return false;
    return kick(true);
  }

  /// 热点稳定：慢速 TTS/原声 → 口型(MJPEG) + 手机播同一轨音频
  Future<bool> speakTcp(
    String text, {
    bool interrupt = true,
    bool useOriginal = false,
    String rate = '-18%',
  }) async {
    final clip = await prepareTcp(
      text,
      useOriginal: useOriginal,
      rate: rate,
      interrupt: interrupt,
    );
    if (clip == null) return false;
    return playPreparedTcp(clip, interrupt: interrupt);
  }

  /// 播放上传视频原声（口型跟原声音轨走）
  Future<bool> playOriginalVoice({
    String? sessionOverride,
    bool interrupt = true,
  }) async {
    if (!config.enabled || config.isBaidu) return false;
    // 热点：走 speak_tcp 原声，保证手机也能听到同一轨
    if (isMjpegSession || (sessionId ?? '').isEmpty) {
      return speakTcp('', interrupt: interrupt, useOriginal: true);
    }
    try {
      final sid = (sessionOverride != null && sessionOverride.isNotEmpty)
          ? sessionOverride
          : sessionId;
      final uri = Uri.parse('${config.normalizedBase}/api/xile/play_original');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (sid != null && sid.isNotEmpty) 'sessionid': sid,
              'avatar': config.avatarId.isNotEmpty
                  ? config.avatarId
                  : 'user_upload_host',
              'interrupt': interrupt,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['code'] != null && body['code'] != 0) {
          lastError = '${body['msg'] ?? body}';
          return false;
        }
        if (body is Map && body['data'] is Map) {
          final data = body['data'] as Map;
          final audioUrl = '${data['audioUrl'] ?? ''}';
          final dur = (data['durationMs'] as num?)?.toInt() ?? 30000;
          if (audioUrl.isNotEmpty) {
            await _playTcpAudio(audioUrl, dur, _audioGen);
          }
        }
        lastError = null;
        return true;
      }
      lastError = '原声播放失败 HTTP ${res.statusCode}';
      return false;
    } catch (e) {
      lastError = '原声播放异常：$e';
      return false;
    }
  }

  /// 肢体动作：1 idle / 2 wave / 3 nod / 4 point（需引擎加载 customvideo）
  Future<bool> setAudiotype(int audiotype, {String? sessionOverride}) async {
    if (!config.enabled || config.isBaidu) return false;
    final sid = (sessionOverride != null && sessionOverride.isNotEmpty)
        ? sessionOverride
        : sessionId;
    if (sid == null || sid.isEmpty) {
      lastError = '尚无会话，无法播放动作';
      return false;
    }
    try {
      final uri = Uri.parse('${config.normalizedBase}/set_audiotype');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sessionid': sid, 'audiotype': audiotype}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['code'] != null && body['code'] != 0) {
          lastError = '${body['msg'] ?? body}';
          return false;
        }
        return true;
      }
      lastError = '动作失败 HTTP ${res.statusCode}';
      return false;
    } catch (e) {
      lastError = '动作异常：$e';
      return false;
    }
  }

  Future<String> createAvatarFromPhoto({
    required String imagePath,
    required String avatarId,
    String model = 'wav2lip',
    int imgSize = 256,
  }) async {
    if (config.isBaidu) {
      throw Exception('百度实时模式请在曦灵控制台配置形象；照片形象请用曦灵「照片数字人」或切回本地引擎');
    }
    final uri = Uri.parse('${config.normalizedBase}/api/avatar/task');
    final req = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['avatar_id'] = avatarId
      ..fields['img_size'] = '$imgSize'
      ..fields['face_det_batch_size'] = '8'
      ..files.add(await http.MultipartFile.fromPath('image_file', imagePath));

    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map || body['code'] != 0) {
      throw Exception('创建形象任务失败：${body is Map ? body['msg'] : res.body}');
    }
    final data = body['data'] as Map<String, dynamic>;
    return '${data['task_id']}';
  }

  Future<AvatarTaskStatus> getAvatarTask(String taskId) async {
    final uri = Uri.parse('${config.normalizedBase}/api/avatar/task/$taskId');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map || body['code'] != 0) {
      throw Exception('查询任务失败：${body is Map ? body['msg'] : res.body}');
    }
    final data = body['data'] as Map<String, dynamic>;
    return AvatarTaskStatus(
      taskId: '${data['task_id']}',
      status: '${data['status']}',
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      errorMsg: '${data['error_msg'] ?? ''}',
      avatarId: '${data['avatar_id'] ?? ''}',
    );
  }

  Future<AvatarTaskStatus> waitAvatarTask(
    String taskId, {
    void Function(AvatarTaskStatus status)? onProgress,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final st = await getAvatarTask(taskId);
      onProgress?.call(st);
      if (st.isDone || st.isFailed) return st;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw TimeoutException('生成数字人超时，请检查电脑引擎日志');
  }
}
