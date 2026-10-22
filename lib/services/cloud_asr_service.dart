import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 不依赖系统 SpeechRecognizer 的云端语音识别（应用宝等环境可用）
class CloudAsrService {
  CloudAsrService();

  /// OpenAI 兼容转录（通义 compatible-mode / OpenAI / 部分代理）
  String llmApiKey = '';
  String llmBaseUrl = '';
  String llmProviderId = '';

  /// 百度智能云「语音识别」API Key / Secret（与曦灵 AppId 不同）
  String baiduApiKey = '';
  String baiduSecretKey = '';

  /// 电脑 LiveTalking 引擎（手机录音可走 /api/xile/asr 代理）
  String engineBaseUrl = '';

  String? _baiduToken;
  DateTime? _baiduTokenExpire;

  bool get isConfigured {
    if (engineBaseUrl.trim().isNotEmpty) return true;
    if (baiduApiKey.trim().isNotEmpty && baiduSecretKey.trim().isNotEmpty) {
      return true;
    }
    if (llmApiKey.trim().isEmpty || llmBaseUrl.trim().isEmpty) return false;
    final id = llmProviderId.toLowerCase();
    final base = llmBaseUrl.toLowerCase();
    // DeepSeek 无语音转写；通义千问 / OpenAI 兼容可走云识别
    if (id == 'deepseek' || base.contains('deepseek')) return false;
    return id == 'dashscope' ||
        base.contains('dashscope') ||
        id == 'openai' ||
        base.contains('openai');
  }

  void configure({
    String? llmApiKey,
    String? llmBaseUrl,
    String? llmProviderId,
    String? baiduApiKey,
    String? baiduSecretKey,
    String? engineBaseUrl,
  }) {
    if (llmApiKey != null) this.llmApiKey = llmApiKey.trim();
    if (llmBaseUrl != null) {
      this.llmBaseUrl = llmBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    }
    if (llmProviderId != null) this.llmProviderId = llmProviderId.trim();
    if (baiduApiKey != null) this.baiduApiKey = baiduApiKey.trim();
    if (baiduSecretKey != null) this.baiduSecretKey = baiduSecretKey.trim();
    if (engineBaseUrl != null) {
      this.engineBaseUrl = engineBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    }
  }

  Future<String?> transcribeWav(
    Uint8List wavBytes, {
    void Function(String status)? onStatus,
  }) async {
    if (wavBytes.isEmpty) return null;

    // 0) 电脑引擎代理（手机无系统识别时的主路径；引擎错误直接抛给 UI）
    if (engineBaseUrl.trim().isNotEmpty) {
      onStatus?.call('电脑引擎识别中…');
      final viaEngine = await _transcribeViaEngine(wavBytes);
      if (viaEngine != null && viaEngine.isNotEmpty) return viaEngine;
    }

    final dashscope = llmProviderId == 'dashscope' ||
        llmBaseUrl.toLowerCase().contains('dashscope');

    if (llmApiKey.isNotEmpty && dashscope) {
      onStatus?.call('通义千问识别中…');
      final viaNative = await _transcribeDashscopeAsr(wavBytes);
      if (viaNative != null && viaNative.isNotEmpty) return viaNative;
      final viaCompat = await _transcribeOpenAiCompatible(wavBytes);
      if (viaCompat != null && viaCompat.isNotEmpty) return viaCompat;
      final viaQwen = await _transcribeQwenAudio(wavBytes);
      if (viaQwen != null && viaQwen.isNotEmpty) return viaQwen;
    } else if (llmApiKey.isNotEmpty && llmBaseUrl.isNotEmpty) {
      onStatus?.call('正在云端识别…');
      final viaLlm = await _transcribeOpenAiCompatible(wavBytes);
      if (viaLlm != null && viaLlm.isNotEmpty) return viaLlm;
    }

    // 2) 百度短语音识别
    if (baiduApiKey.isNotEmpty && baiduSecretKey.isNotEmpty) {
      onStatus?.call('正在百度语音识别…');
      final viaBaidu = await _transcribeBaidu(wavBytes);
      if (viaBaidu != null && viaBaidu.isNotEmpty) return viaBaidu;
    }

    return null;
  }

  Future<String?> _transcribeViaEngine(Uint8List wavBytes) async {
    final root = engineBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (root.isEmpty) return null;
    final name = _guessAudioFilename(wavBytes);
    try {
      final uri = Uri.parse('$root/api/xile/asr');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: name,
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 50));
      final body = await streamed.stream.bytesToString();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is Map) {
          final text = '${data['text'] ?? ''}'.trim();
          if (text.isNotEmpty) return text;
        }
        final text = '${decoded['text'] ?? ''}'.trim();
        if (text.isNotEmpty) return text;
        final msg = '${decoded['msg'] ?? ''}'.trim();
        final code = decoded['code'];
        if (code != null && code != 0 && msg.isNotEmpty) {
          throw Exception(msg);
        }
      }
      if (streamed.statusCode == 404 || streamed.statusCode == 405) {
        // 引擎没有 ASR 接口：静默跳过，让 transcribeWav 走通义/百度云端识别
        return null;
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception(
          '连不上电脑引擎识别（${streamed.statusCode}），请确认同一 Wi‑Fi 且引擎开着',
        );
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('连不上电脑引擎（$e），请确认 192.168.40.241:8010');
    }
    return null;
  }

  String _guessAudioFilename(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'ask.wav';
    }
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'ask.m4a';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return 'ask.mp3';
    }
    if (bytes.length >= 2 &&
        bytes[0] == 0xFF &&
        (bytes[1] & 0xE0) == 0xE0) {
      return 'ask.mp3';
    }
    return 'ask.wav';
  }

  Future<String?> _transcribeOpenAiCompatible(Uint8List wavBytes) async {
    final uri = Uri.parse('$llmBaseUrl/audio/transcriptions');
    try {
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $llmApiKey';
      req.fields['model'] = llmProviderId == 'dashscope' ||
              llmBaseUrl.contains('dashscope')
          ? 'qwen3-asr-flash'
          : 'whisper-1';
      req.fields['language'] = 'zh';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'ask.wav',
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 45));
      final body = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          // whisper 模型名不对时再试通用名
          if (streamed.statusCode == 404 || body.contains('model')) {
            return await _transcribeOpenAiCompatibleRetry(wavBytes);
          }
          return null;
        }
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = '${decoded['text'] ?? ''}'.trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _transcribeOpenAiCompatibleRetry(Uint8List wavBytes) async {
    for (final model in [
      'qwen3-asr-flash',
      'paraformer-v2',
      'fun-asr',
      'whisper-1',
    ]) {
      try {
        final uri = Uri.parse('$llmBaseUrl/audio/transcriptions');
        final req = http.MultipartRequest('POST', uri);
        req.headers['Authorization'] = 'Bearer $llmApiKey';
        req.fields['model'] = model;
        req.fields['language'] = 'zh';
        req.files.add(
          http.MultipartFile.fromBytes('file', wavBytes, filename: 'ask.wav'),
        );
        final streamed = await req.send().timeout(const Duration(seconds: 45));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            final text = '${decoded['text'] ?? ''}'.trim();
            if (text.isNotEmpty) return text;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// 阿里云百炼官方语音识别（应用宝走这条，不依赖系统引擎）
  Future<String?> _transcribeDashscopeAsr(Uint8List wavBytes) async {
    final uri = Uri.parse(
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
    );
    final dataUrl = 'data:audio/wav;base64,${base64Encode(wavBytes)}';
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $llmApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'qwen3-asr-flash',
              'input': {
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'audio': dataUrl},
                    ],
                  },
                ],
              },
              'parameters': {
                'asr_options': {
                  'language': 'zh',
                  'enable_itn': true,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final output = decoded['output'];
      if (output is Map) {
        final choices = output['choices'];
        if (choices is List && choices.isNotEmpty) {
          final msg = choices.first is Map ? choices.first['message'] : null;
          final content = msg is Map ? msg['content'] : null;
          final text = _dashscopeContentText(content);
          if (text.isNotEmpty) return text;
        }
        final text = '${output['text'] ?? ''}'.trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  String _dashscopeContentText(dynamic content) {
    if (content is String) return content.trim();
    if (content is List) {
      final buf = StringBuffer();
      for (final item in content) {
        if (item is Map) {
          final t = '${item['text'] ?? ''}'.trim();
          if (t.isNotEmpty) buf.write(t);
        } else {
          final t = '$item'.trim();
          if (t.isNotEmpty) buf.write(t);
        }
      }
      return buf.toString().trim();
    }
    return '$content'.trim();
  }

  /// 通义 qwen-audio：把语音当多模态输入，只要「转写文字」
  Future<String?> _transcribeQwenAudio(Uint8List wavBytes) async {
    final uri = Uri.parse('$llmBaseUrl/chat/completions');
    final b64 = base64Encode(wavBytes);
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $llmApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'qwen-audio-turbo',
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'input_audio',
                      'input_audio': {
                        'data': b64,
                        'format': 'wav',
                      },
                    },
                    {
                      'type': 'text',
                      'text': '请把这段中文语音原样转成文字，只输出识别结果，不要解释。',
                    },
                  ],
                },
              ],
              'max_tokens': 200,
              'temperature': 0,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first['message'];
        final content = msg is Map ? msg['content'] : null;
        final text = '$content'.trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _transcribeBaidu(Uint8List wavBytes) async {
    final token = await _baiduAccessToken();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('https://vop.baidu.com/server_api'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'format': 'wav',
              'rate': 16000,
              'channel': 1,
              'cuid': 'xile-app',
              'token': token,
              'dev_pid': 1537, // 普通话输入法模型
              'speech': base64Encode(wavBytes),
              'len': wavBytes.length,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      if (decoded['err_no'] != 0) return null;
      final result = decoded['result'];
      if (result is List && result.isNotEmpty) {
        return '${result.first}'.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _baiduAccessToken() async {
    final now = DateTime.now();
    if (_baiduToken != null &&
        _baiduTokenExpire != null &&
        now.isBefore(_baiduTokenExpire!)) {
      return _baiduToken;
    }
    try {
      final uri = Uri.parse(
        'https://aip.baidubce.com/oauth/2.0/token'
        '?grant_type=client_credentials'
        '&client_id=${Uri.encodeQueryComponent(baiduApiKey)}'
        '&client_secret=${Uri.encodeQueryComponent(baiduSecretKey)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['access_token'] != null) {
        _baiduToken = '${decoded['access_token']}';
        final sec = (decoded['expires_in'] as num?)?.toInt() ?? 2592000;
        _baiduTokenExpire = now.add(Duration(seconds: sec - 60));
        return _baiduToken;
      }
    } catch (_) {}
    return null;
  }
}
