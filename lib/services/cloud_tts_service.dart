import 'dart:convert';

import 'package:http/http.dart' as http;

/// 通义 Qwen3-TTS：真人感口播（替换系统机器人 TTS）
class CloudTtsService {
  CloudTtsService();

  String apiKey = '';
  String model = 'qwen3-tts-flash';
  String voice = 'Cherry';

  bool get isConfigured => apiKey.trim().isNotEmpty;

  void configure({
    String? apiKey,
    String? model,
    String? voice,
  }) {
    if (apiKey != null) this.apiKey = apiKey.trim();
    if (model != null && model.trim().isNotEmpty) this.model = model.trim();
    if (voice != null && voice.trim().isNotEmpty) this.voice = voice.trim();
  }

  /// 返回可播放的 wav/mp3 URL；失败返回 null
  Future<String?> synthesize(
    String text, {
    String? voiceOverride,
  }) async {
    if (!isConfigured) return null;
    final clean = _addNaturalPauses(text.trim());
    if (clean.isEmpty) return null;

    // Qwen3-TTS 单次约 600 字；超长切段由调用方处理，这里截断保底
    final clip = clean.length > 580 ? clean.substring(0, 580) : clean;
    try {
      final res = await http
          .post(
            Uri.parse(
              'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
            ),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'input': {
                'text': clip,
                'voice': voiceOverride?.trim().isNotEmpty == true
                    ? voiceOverride!.trim()
                    : voice,
                'language_type': 'Chinese',
              },
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      // 兼容两种返回：嵌套 output.audio.url 或顶层 audio.url
      final output = decoded['output'];
      Map? audio = (output is Map) ? output['audio'] as Map? : null;
      audio ??= decoded['audio'] is Map ? decoded['audio'] as Map : null;
      if (audio != null) {
        final url = '${audio['url'] ?? ''}'.trim();
        if (url.isNotEmpty) return url;
      }
      // 个别版本直接回 url 字段
      final directUrl = '${decoded['url'] ?? ''}'.trim();
      if (directUrl.isNotEmpty) return directUrl;
    } catch (_) {}
    return null;
  }

  /// 在句末标点后插更长的停顿，让 TTS 真人式喘气，避免「一气呵成的机器播报」
  String _addNaturalPauses(String s) {
    if (s.isEmpty) return s;
    // 句号/问号/感叹号 → 长停顿（用空格串模拟）
    s = s.replaceAllMapped(
      RegExp(r'([。！？!?])'),
      (m) => '${m[1]}  ',
    );
    // 逗号/分号 → 中停顿
    s = s.replaceAllMapped(
      RegExp(r'([，；,;])'),
      (m) => '${m[1]} ',
    );
    // 收尾多余空白
    s = s.replaceAll(RegExp(r'\s{3,}'), '  ').trim();
    return s;
  }
}
