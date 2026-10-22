import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/host_voice_profile.dart';
import 'cloud_asr_service.dart';
import 'cloud_tts_service.dart';

class VoiceService {
  VoiceService({
    CloudAsrService? cloudAsr,
    CloudTtsService? cloudTts,
  })  : cloudAsr = cloudAsr ?? CloudAsrService(),
        cloudTts = cloudTts ?? CloudTtsService();

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final MethodChannel _speechChannel = const MethodChannel('com.xile/speech');
  final CloudAsrService cloudAsr;
  final CloudTtsService cloudTts;

  bool _ttsReady = false;
  bool _sttReady = false;
  bool _sttChecked = false;
  String? lastInitError;
  bool isSpeaking = false;
  bool isListening = false;
  String partialListenText = '';
  HostVoiceProfile profile = HostVoiceProfile.presets.first;
  String? activeVoiceName;
  String? lastListenMode; // system / intent / cloud

  // 微信式按住说话
  String? _holdPath;
  DateTime? _holdStartedAt;
  bool _holdCancelled = false;

  /// 应用宝等无系统识别时，只要能录音 + 云端 ASR（或系统弹窗）就可听
  bool get canListen => true;

  Future<void> init({bool forceStt = false}) async {
    if (!_ttsReady) {
      try {
        await _tts.setLanguage('zh-CN');
        await _tts.setVolume(1.0);
        await _tts.awaitSpeakCompletion(true);
        try {
          await _tts.setSharedInstance(true);
        } catch (_) {}
        _ttsReady = true;
        await _applyProfileToEngine();
      } catch (e) {
        lastInitError = '语音播报初始化失败：$e';
      }
    }
    if (forceStt) {
      _sttChecked = false;
      _sttReady = false;
    }
    if (!_sttChecked) {
      _sttChecked = true;
      try {
        _sttReady = await _stt.initialize(
          onError: (_) {},
          onStatus: (_) {},
        );
      } catch (_) {
        _sttReady = false;
      }
      // 系统不可用不算致命：后面走录音云识别 / 系统弹窗
      if (!_sttReady) {
        lastInitError = null;
      }
    }
  }

  Future<void> applyProfile(HostVoiceProfile next) async {
    profile = next;
    await init();
    if (_ttsReady) await _applyProfileToEngine();
  }

  Future<void> applyForHost({
    String? hostName,
    String? avatarId,
    String? preferredId,
  }) {
    return applyProfile(
      HostVoiceProfile.resolve(
        hostName: hostName,
        avatarId: avatarId,
        preferredId: preferredId,
      ),
    );
  }

  Future<void> _applyProfileToEngine() async {
    final p = profile;
    try {
      await _tts.setSpeechRate(p.localRate.clamp(0.35, 0.7));
      await _tts.setPitch(p.localPitch.clamp(0.7, 1.4));
    } catch (_) {}
    await _pickNaturalZhVoice(p);
  }

  Future<void> _pickNaturalZhVoice(HostVoiceProfile p) async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List || raw.isEmpty) return;

      final voices = <Map<String, String>>[];
      for (final v in raw) {
        if (v is Map) {
          voices.add({
            for (final e in v.entries) '${e.key}': '${e.value}',
          });
        }
      }
      if (voices.isEmpty) return;

      bool isZh(Map<String, String> v) {
        final locale = (v['locale'] ?? v['localeId'] ?? '').toLowerCase();
        final name = (v['name'] ?? '').toLowerCase();
        return locale.contains('zh') ||
            locale.contains('cmn') ||
            name.contains('chinese') ||
            name.contains('zh-');
      }

      final zh = voices.where(isZh).toList();
      final pool = zh.isNotEmpty ? zh : voices;

      int score(Map<String, String> v) {
        final name = (v['name'] ?? '').toLowerCase();
        final locale = (v['locale'] ?? '').toLowerCase();
        var s = 0;
        if (locale.contains('zh-cn') || locale.contains('cmn-hans')) s += 20;
        if (locale.contains('zh')) s += 10;
        if (name.contains('neural') ||
            name.contains('natural') ||
            name.contains('premium') ||
            name.contains('enhanced') ||
            name.contains('online')) {
          s += 30;
        }
        final wantFemale = p.gender == VoiceGender.female;
        final femaleHint = name.contains('female') ||
            name.contains('woman') ||
            name.contains('girl') ||
            name.contains('xiaoyan') ||
            name.contains('xiaoxiao');
        final maleHint = name.contains('male') ||
            name.contains('man') ||
            name.contains('boy') ||
            name.contains('yunyang');
        if (wantFemale && femaleHint) s += 18;
        if (!wantFemale && maleHint) s += 18;
        if (wantFemale && maleHint) s -= 12;
        if (!wantFemale && femaleHint) s -= 12;
        final key = '${p.id}|$name|$locale';
        s += (key.hashCode.abs() % 7);
        return s;
      }

      pool.sort((a, b) => score(b).compareTo(score(a)));
      final best = pool.first;
      final name = best['name'];
      final locale = best['locale'] ?? best['localeId'];
      if (name == null || name.isEmpty) return;

      try {
        await _tts.setVoice({'name': name, 'locale': locale ?? 'zh-CN'});
        activeVoiceName = name;
      } catch (_) {
        if (locale != null && locale.isNotEmpty) {
          await _tts.setLanguage(locale);
        }
      }
    } catch (_) {}
  }

  static String humanizeForSpeech(String text) {
    var s = text
        .replaceAll(RegExp(r'【[^】]*】'), ' ')
        .replaceAll(RegExp(r'[#*`>]'), '')
        .replaceAll('——', '，')
        .replaceAll('—', '，')
        .replaceAll('…', '，')
        .replaceAll('...', '，')
        .replaceAll('：', '，')
        .replaceAll(':', '，')
        .replaceAll('；', '，')
        .replaceAll(';', '，')
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), ' ')
        // 书面词 → 口语词：让讲解像真人主播而不是新闻播报
        .replaceAll('本场主播为人工智能技术生成的数字人', '跟大家说一声哈，我是AI数字人')
        .replaceAll('人工智能技术生成的数字人主播', 'AI数字人主播')
        .replaceAll('参数以商品页为准', '具体以商品页为准哦')
        .replaceAll('以直播间挂链和下单页为准', '看直播间挂链就行')
        .replaceAll('规格以商品页为准', '规格看商品页就行')
        .replaceAll('请大家', '大家')
        .replaceAll('请各位', '各位')
        .replaceAll('敬请期待', '稍等一下')
        .replaceAll('物超所值', '很划算')
        .replaceAll('性价比高', '很划算')
        .replaceAll('性价比超高', '超划算')
        .replaceAll('品质保证', '品质靠谱')
        .replaceAll('假一赔十', '假一赔十，放心拍')
        .replaceAll('欢迎下单', '喜欢就拍')
        .replaceAll('欢迎购买', '喜欢就拍')
        .replaceAll('请点击下方链接', '看下方链接')
        .replaceAll('请点击挂链', '点挂链就行')
        .replaceAll('下单后', '拍下后')
        .replaceAll('购买后', '拍下后')
        .replaceAll('可联系客服', '找客服就行')
        .replaceAll('如有疑问', '有问题')
        .replaceAll('感谢您的', '谢谢你的')
        .replaceAll('感谢大家', '谢谢大家')
        .replaceAll('感谢各位', '谢谢家人们')
        .replaceAll('亲们', '家人们')
        .replaceAll('宝宝们', '家人们')
        .replaceAll('直播间', '直播间')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 长句拆短：一句超过 32 字没标点的，在 18~24 字处插一个逗号让 TTS 喘口气
    s = s.replaceAllMapped(
      RegExp(r'([^，。！？、；\s]{32,})'),
      (m) {
        final seg = m[1]!;
        if (seg.length < 36) return seg;
        final cut = seg.length ~/ 2;
        return '${seg.substring(0, cut)}，${seg.substring(cut)}';
      },
    );

    // 句末标点后插更长停顿（双空格），逗号后插短停顿（单空格）
    // 真人主播句尾会喘口气，TTS 才不会一气呵成像机器播报
    s = s.replaceAllMapped(RegExp(r'([。！？!?])'), (m) => '${m[1]}  ');
    s = s.replaceAllMapped(RegExp(r'([，；,;])'), (m) => '${m[1]} ');
    s = s.replaceAll(RegExp(r'\s{3,}'), '  ').trim();
    return s;
  }

  /// 统一走 webview 播放（口型同步生效，不会两种声音同响）
  Future<void> Function(String url, [int? syncDelayMs])? webPlayer;

  Future<void> speak(String text) async {
    await init();
    final clean = humanizeForSpeech(text);
    if (clean.isEmpty) return;
    isSpeaking = true;
    try {
      await stopSpeaking();
      isSpeaking = true;

      // 1) 通义 Qwen3-TTS 真人声（去掉系统机器人味）
      cloudTts.configure(voice: profile.qwenVoice);
      if (cloudTts.isConfigured) {
        final chunks = _splitForTts(clean);
        for (final chunk in chunks) {
          if (!isSpeaking) break;
          final url = await cloudTts.synthesize(
            chunk,
            voiceOverride: profile.qwenVoice,
          );
          if (url == null || url.isEmpty) {
            // Qwen 失败：绝不 fallback 系统机器人 TTS，直接跳过这一句
            return;
          }
          // 统一通过 webview 播：口型同步生效，不会和引擎声同时响
          if (webPlayer != null) {
            await webPlayer!(url);
            // webview 播放完成通过 audioEnded 回调，这里按字数估算等待
            final durMs = (chunk.length * 320 + 2000).clamp(2000, 60000);
            await Future<void>.delayed(Duration(milliseconds: durMs));
          } else {
            await _player.stop();
            await _player.play(UrlSource(url));
            await _player.onPlayerComplete.first.timeout(
              Duration(seconds: 8 + chunk.length ~/ 4),
              onTimeout: () {},
            );
          }
        }
        return;
      }

      // 2) 没配 Qwen Key：不播（绝不 fallback 系统机器人声）
      // 用户需在设置填通义 API Key 才有声
    } finally {
      isSpeaking = false;
    }
  }

  List<String> _splitForTts(String text) {
    if (text.length <= 500) return [text];
    final parts = <String>[];
    var buf = StringBuffer();
    for (final seg in text.split(RegExp(r'(?<=[。！？!?；;])'))) {
      final s = seg.trim();
      if (s.isEmpty) continue;
      if (buf.length + s.length > 480 && buf.isNotEmpty) {
        parts.add(buf.toString());
        buf = StringBuffer();
      }
      buf.write(s);
    }
    if (buf.isNotEmpty) parts.add(buf.toString());
    return parts.isEmpty ? [text] : parts;
  }

  Future<void> _speakLocal(String clean) async {
    if (!_ttsReady) return;
    await _applyProfileToEngine();
    await _tts.speak(clean);
  }

  Future<void> stopSpeaking() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    isSpeaking = false;
  }

  /// 微信式：按住开始录音（不自动计时结束）
  Future<void> startHoldRecord({
    void Function(String partial)? onPartial,
  }) async {
    await stopSpeaking();
    await stopListen();
    await init(forceStt: false);
    if (!cloudAsr.isConfigured) {
      lastInitError =
          '本机没有语音识别。请确认已连接电脑引擎（同一 Wi‑Fi），或在设置填写通义 API Key。';
      throw Exception(lastInitError);
    }

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw Exception('需要麦克风权限才能语音提问');
    }

    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      try {
        dir = await getApplicationCacheDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final wavPath = p.join(dir.path, 'xile_ask_$stamp.wav');
    final aacPath = p.join(dir.path, 'xile_ask_$stamp.m4a');

    _holdCancelled = false;
    _holdPath = null;
    _holdStartedAt = null;
    isListening = true;
    partialListenText = '';
    lastListenMode = null;
    lastInitError = null;
    onPartial?.call('松手发送');

    var started = false;
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: wavPath,
      );
      _holdPath = wavPath;
      started = true;
    } catch (_) {
      try {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 64000,
          ),
          path: aacPath,
        );
        _holdPath = aacPath;
        started = true;
      } catch (e) {
        isListening = false;
        throw Exception('无法开始录音：$e');
      }
    }
    if (!started || !await _recorder.isRecording()) {
      isListening = false;
      throw Exception('录音未真正开始，请重试');
    }
    // 计时从真正开录算起，避免启动耗时误判“太短”
    _holdStartedAt = DateTime.now();
  }

  /// 微信式：松手 → 立刻停录并识别
  Future<String?> finishHoldRecord({
    void Function(String partial)? onPartial,
  }) async {
    if (_holdCancelled) {
      await _cleanupHoldFile();
      isListening = false;
      return null;
    }

    final started = _holdStartedAt;
    String? stoppedPath;
    try {
      if (await _recorder.isRecording()) {
        stoppedPath = await _recorder.stop();
      }
    } catch (_) {}

    final path = stoppedPath ?? _holdPath;
    isListening = false;
    _holdPath = null;
    _holdStartedAt = null;

    if (path == null) {
      throw Exception('录音失败，请重试');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('录音文件丢失，请重试');
    }

    final elapsedMs =
        started == null ? 0 : DateTime.now().difference(started).inMilliseconds;
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}

    if (elapsedMs < 500 || bytes.length < 2000) {
      throw Exception('说话时间太短，请按住多说一会儿');
    }

    // 空录音/几乎静音：PCM wav 头约 44 字节，其余接近 0
    if (!_hasAudibleSignal(bytes)) {
      throw Exception('没听到声音，请靠近麦克风再说');
    }

    onPartial?.call('正在识别…');
    final text = await cloudAsr.transcribeWav(
      Uint8List.fromList(bytes),
      onStatus: onPartial,
    );
    if (text != null && text.trim().isNotEmpty) {
      partialListenText = text.trim();
      lastListenMode = 'cloud';
      onPartial?.call(partialListenText);
      return partialListenText;
    }
    throw Exception('没有听清，请靠近麦克风再说一次');
  }

  /// 粗检：WAV/AAC 是否有有效内容（避免空麦）
  bool _hasAudibleSignal(List<int> bytes) {
    if (bytes.length < 64) return false;
    // m4a/aac：有 ftyp 或 ADTS 即认为有内容
    if (bytes.length > 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return bytes.length > 3000;
    }
    // WAV：跳过 44 字节头，看是否有非零采样
    var offset = 44;
    if (bytes.length > 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      // 找 data chunk
      for (var i = 12; i + 8 < bytes.length; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          offset = i + 8;
          break;
        }
      }
      var nonZero = 0;
      final end = bytes.length < offset + 8000 ? bytes.length : offset + 8000;
      for (var i = offset; i < end; i++) {
        if (bytes[i] != 0) {
          nonZero++;
          if (nonZero > 20) return true;
        }
      }
      return false;
    }
    return bytes.length > 2000;
  }

  /// 微信式：上滑取消
  Future<void> cancelHoldRecord() async {
    _holdCancelled = true;
    isListening = false;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    await _cleanupHoldFile();
    _holdPath = null;
    _holdStartedAt = null;
  }

  Future<void> _cleanupHoldFile() async {
    final path = _holdPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 兼容旧调用：固定时长录音（非按住说话场景）
  Future<String?> listenOnce({
    void Function(String partial)? onPartial,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await startHoldRecord(onPartial: onPartial);
    final maxMs = timeout.inMilliseconds.clamp(2000, 15000);
    final step = 200;
    var left = maxMs;
    while (left > 0 && isListening && !_holdCancelled) {
      onPartial?.call('录音中… ${(left / 1000).ceil()}s');
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
    return finishHoldRecord(onPartial: onPartial);
  }

  Future<String?> _listenSystem({
    void Function(String partial)? onPartial,
    required Duration timeout,
  }) async {
    String? finalText;
    Future<void> startListen(String? localeId) {
      return _stt.listen(
        onResult: (result) {
          partialListenText = result.recognizedWords;
          onPartial?.call(partialListenText);
          if (result.finalResult) {
            finalText = result.recognizedWords.trim();
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
          localeId: localeId,
        ),
      );
    }

    try {
      try {
        await startListen('zh_CN');
      } catch (_) {
        await startListen(null);
      }
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (finalText != null && finalText!.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      finalText ??=
          partialListenText.trim().isEmpty ? null : partialListenText.trim();
      await stopListen();
      return finalText;
    } catch (_) {
      await stopListen();
      return null;
    }
  }

  Future<String?> _listenAndroidIntent() async {
    try {
      final text = await _speechChannel.invokeMethod<String>('recognizeIntent');
      return text?.trim();
    } on PlatformException catch (e) {
      if (e.code == 'unavailable' || e.code == 'busy') return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> stopListen() async {
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    isListening = false;
  }
}
