import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class LlmProviderPreset {
  const LlmProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.hint,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String hint;
}

class LlmTestResult {
  const LlmTestResult({
    required this.ok,
    required this.message,
    this.latencyMs,
    this.sample,
  });

  final bool ok;
  final String message;
  final int? latencyMs;
  final String? sample;
}

/// OpenAI 兼容 Chat Completions；支持编译期 dart-define 与运行时配置
class LlmService {
  LlmService();

  static const presets = <LlmProviderPreset>[
    LlmProviderPreset(
      id: 'dashscope',
      name: '通义千问',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen-plus',
      hint: '阿里云百炼；应用宝语音识别走这一家',
    ),
    LlmProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      hint: '国内常用，性价比高（不支持语音转写）',
    ),
    LlmProviderPreset(
      id: 'moonshot',
      name: '月之暗面 Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      model: 'moonshot-v1-8k',
      hint: 'Kimi OpenAI 兼容接口',
    ),
    LlmProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      hint: '官方或其他兼容代理',
    ),
  ];

  String apiKey = '';
  String baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  String model = 'qwen-plus';
  bool demoMode = true;
  String providerId = 'dashscope';
  String? lastCallMeta;

  bool get isLiveLlm => !demoMode && apiKey.isNotEmpty;

  Future<void> load() async {
    const envKey = String.fromEnvironment('LLM_API_KEY');
    const envBase = String.fromEnvironment('LLM_BASE_URL');
    const envModel = String.fromEnvironment('LLM_MODEL');
    const envDemo = String.fromEnvironment('LLM_DEMO', defaultValue: '');
    const envProvider = String.fromEnvironment('LLM_PROVIDER', defaultValue: 'dashscope');

    // 1) 本机持久化
    await _loadPersisted();

    // 2) 运行时环境变量 / .llm_secrets（电脑后台旁的密钥文件；Web 无 dart:io）
    if (!kIsWeb) {
      await _loadSecretsFile();
      final runtimeKey = Platform.environment['LLM_API_KEY']?.trim() ?? '';
      if (runtimeKey.isNotEmpty) {
        apiKey = runtimeKey;
        final b = Platform.environment['LLM_BASE_URL']?.trim();
        if (b != null && b.isNotEmpty) baseUrl = b.replaceAll(RegExp(r'/$'), '');
        final m = Platform.environment['LLM_MODEL']?.trim();
        if (m != null && m.isNotEmpty) model = m;
        final p = Platform.environment['LLM_PROVIDER']?.trim();
        if (p != null && p.isNotEmpty) providerId = p;
      }
    }

    // 3) 编译期 dart-define 若有 Key，优先生效
    if (envKey.isNotEmpty) {
      apiKey = envKey;
      providerId = envProvider;
      LlmProviderPreset? preset;
      for (final p in presets) {
        if (p.id == providerId) {
          preset = p;
          break;
        }
      }
      baseUrl = envBase.isNotEmpty ? envBase : (preset?.baseUrl ?? baseUrl);
      model = envModel.isNotEmpty ? envModel : (preset?.model ?? model);
      final demoFlag = envDemo.toLowerCase();
      if (demoFlag == '1' || demoFlag == 'true') {
        demoMode = true;
      } else if (demoFlag == '0' || demoFlag == 'false') {
        demoMode = false;
      } else {
        demoMode = false;
      }
    } else if (apiKey.isEmpty) {
      applyPreset(presets.first);
      demoMode = true;
    } else {
      // 有 Key 就默认真问答（除非用户明确保存了演示模式=true 且无强制关闭）
      final envDemoRuntime =
          kIsWeb ? '' : (Platform.environment['LLM_DEMO'] ?? '');
      final forceDemo = (envDemoRuntime.isNotEmpty ? envDemoRuntime : envDemo)
          .toLowerCase();
      if (forceDemo == '1' || forceDemo == 'true') {
        demoMode = true;
      } else {
        demoMode = false;
      }
    }
  }

  Future<void> _loadSecretsFile() async {
    if (kIsWeb) return;
    final candidates = <String>[
      '${Directory.current.path}${Platform.pathSeparator}.llm_secrets',
      if (Platform.isWindows) ...[
        'C:${Platform.pathSeparator}dev${Platform.pathSeparator}xile_admin${Platform.pathSeparator}.llm_secrets',
        'C:${Platform.pathSeparator}dev${Platform.pathSeparator}xile_live${Platform.pathSeparator}.llm_secrets',
        '${Platform.environment['USERPROFILE']}${Platform.pathSeparator}Desktop${Platform.pathSeparator}喜乐${Platform.pathSeparator}ai_digital_live${Platform.pathSeparator}.llm_secrets',
      ],
    ];
    try {
      final exe = Platform.resolvedExecutable;
      final exeDir = File(exe).parent.path;
      candidates.insert(0, '$exeDir${Platform.pathSeparator}.llm_secrets');
    } catch (_) {}

    for (final path in candidates) {
      try {
        final f = File(path);
        if (!await f.exists()) continue;
        for (final line in await f.readAsLines()) {
          final t = line.trim();
          if (t.isEmpty || t.startsWith('#')) continue;
          final i = t.indexOf('=');
          if (i <= 0) continue;
          final k = t.substring(0, i).trim();
          final v = t.substring(i + 1).trim();
          if (k == 'LLM_API_KEY' && v.isNotEmpty) apiKey = v;
          if (k == 'LLM_BASE_URL' && v.isNotEmpty) {
            baseUrl = v.replaceAll(RegExp(r'/$'), '');
          }
          if (k == 'LLM_MODEL' && v.isNotEmpty) model = v;
          if (k == 'LLM_PROVIDER' && v.isNotEmpty) providerId = v;
          if (k == 'LLM_DEMO') {
            final d = v.toLowerCase();
            if (d == '1' || d == 'true') demoMode = true;
            if (d == '0' || d == 'false') demoMode = false;
          }
        }
        if (apiKey.isNotEmpty) return;
      } catch (_) {}
    }
  }

  Future<void> _loadPersisted() async {
    if (kIsWeb) return;
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      final key = (raw['apiKey'] as String?)?.trim() ?? '';
      if (key.isNotEmpty) apiKey = key;
      final bu = (raw['baseUrl'] as String?)?.trim();
      if (bu != null && bu.isNotEmpty) baseUrl = bu.replaceAll(RegExp(r'/$'), '');
      final md = (raw['model'] as String?)?.trim();
      if (md != null && md.isNotEmpty) model = md;
      final pid = (raw['providerId'] as String?)?.trim();
      if (pid != null && pid.isNotEmpty) providerId = pid;
      if (raw.containsKey('demoMode')) {
        demoMode = raw['demoMode'] == true;
      }
    } catch (_) {}
  }

  Future<File> _settingsFile() async {
    // Windows：%APPDATA%\XileLive；Android 等：应用可写临时/主目录
    String root;
    if (Platform.isWindows) {
      root = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    } else if (Platform.isAndroid) {
      root = '/data/data/com.xile.ai_digital_live/files';
    } else {
      root = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    }
    final dir = Directory('$root${Platform.pathSeparator}XileLive');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}llm_settings.json');
  }

  void applyPreset(LlmProviderPreset preset) {
    providerId = preset.id;
    baseUrl = preset.baseUrl;
    model = preset.model;
  }

  Future<void> save({
    required String apiKey,
    required String baseUrl,
    required String model,
    required bool demoMode,
    String? providerId,
  }) async {
    this.apiKey = apiKey.trim();
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    this.model = model.trim().isEmpty ? 'deepseek-chat' : model.trim();
    if (providerId != null) this.providerId = providerId;
    this.demoMode = demoMode || this.apiKey.isEmpty;
    await _persist();
  }

  Future<void> _persist() async {
    if (kIsWeb) return;
    try {
      final f = await _settingsFile();
      await f.writeAsString(jsonEncode({
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'providerId': providerId,
        'demoMode': demoMode,
      }));
    } catch (_) {}
  }

  Future<LlmTestResult> testConnection() async {
    if (apiKey.isEmpty) {
      return const LlmTestResult(ok: false, message: '请先填写 API Key');
    }
    if (demoMode) {
      return const LlmTestResult(
        ok: false,
        message: '当前仍是演示模式，请关闭后再测',
      );
    }

    final sw = Stopwatch()..start();
    try {
      final content = await _chat(
        system: '你是连通性测试助手，只回复四个字：联调成功',
        user: '请确认接口可用',
        temperature: 0,
        maxTokens: 32,
      );
      sw.stop();
      lastCallMeta = 'test ${sw.elapsedMilliseconds}ms';
      final ok = content.contains('联调') || content.isNotEmpty;
      return LlmTestResult(
        ok: ok,
        message: ok ? '真实 LLM 联调成功' : '已连通但回复异常',
        latencyMs: sw.elapsedMilliseconds,
        sample: content,
      );
    } catch (e) {
      sw.stop();
      return LlmTestResult(
        ok: false,
        message: _friendlyError(e),
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<String> generateScript({
    required String industry,
    required String product,
    required String sellingPoints,
    required int minutes,
  }) async {
    if (!isLiveLlm) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      lastCallMeta = 'demo template';
      return _demoScript(
        industry: industry,
        product: product,
        sellingPoints: sellingPoints,
        minutes: minutes,
      );
    }

    final sw = Stopwatch()..start();
    final prompt = '''
你是直播电商话术编剧，面向$industry商家。
请生成约$minutes分钟的数字人直播口播脚本。
商品：$product
卖点：$sellingPoints

硬性要求：
1. 开场必须披露「本场主播为人工智能技术生成的数字人」
2. 禁止绝对化用语与虚假功效承诺（如包治、根治、国家级、稳赚不赔）
3. 结构：开场披露 → 痛点 → 卖点讲解 → 互动提问 → 促单 → 合规收尾
4. 用口语，分段标注【开场】【讲解】【互动】【促单】【收尾】
''';

    try {
      final content = await _chat(
        system: '你是合规的直播电商话术助手，输出中文口播稿。',
        user: prompt,
        temperature: 0.7,
        maxTokens: 1800,
      );
      sw.stop();
      lastCallMeta = 'live ${sw.elapsedMilliseconds}ms · $model';
      return content;
    } catch (e) {
      lastCallMeta = 'error';
      throw Exception(_friendlyError(e));
    }
  }

  Future<String> replyDanmaku({
    required String question,
    required String productContext,
  }) async {
    final q = question.trim();
    if (!isLiveLlm) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      lastCallMeta = 'demo qa';
      return _demoDanmakuReply(q, productContext);
    }

    return _chat(
      system: '''
你是直播间数字人主播，说话要像真人主播口播，不要像客服机器人。
禁止：
- 不要说「亲，您问的是…」「关于你刚才的问题」「感谢您的提问」这类套话
- 不要复述用户原话再答
- 不要背固定卖点开场
- 不要用「本产品具有」「综上所述」等书面腔
要求：
- 直接给答案，口语短句，像当面聊天，60 字以内
- 可用「哦」「哈」「咱们」「家人们」等轻语气词，但别堆砌
- 商品相关可参考商品事实；没有的信息就说不知道/以商品页为准
- 可以不提「AI数字人」，除非用户问你是不是 AI
''',
      user: '商品事实：$productContext\n观众：$q\n直接口语回答：',
      temperature: 0.72,
      maxTokens: 200,
    );
  }

  /// 无大模型时的本地直答（禁止「亲，您问的是」套话）
  String _demoDanmakuReply(String question, String productContext) {
    final q = question.toLowerCase();
    final ctx = productContext.trim().isEmpty
        ? '本地生活午市双人套餐，到店核销，价格以直播间挂链为准'
        : productContext.trim();

    bool hit(List<String> keys) => keys.any((k) => question.contains(k) || q.contains(k));

    if (hit(['多少钱', '价格', '几块', '售价', '优惠', '便宜', '折扣'])) {
      return '价格看直播间挂链就行，$ctx。';
    }
    if (hit(['在哪', '地址', '位置', '门店', '怎么去', '哪里'])) {
      return '地址在商品页里，导航直接按商品页走就好。';
    }
    if (hit(['怎么买', '如何购买', '下单', '链接', '挂链', '怎么拍'])) {
      return '点小黄车或者挂链，下单核销就行。';
    }
    if (hit(['运费', '快递', '包邮', '邮费', '配送'])) {
      return '运费和配送以商品页、下单页为准哈，我这边不另外承诺。';
    }
    if (hit(['退', '售后', '过期', '核销', '有效期', '能退吗'])) {
      return '退改和核销期限按商品页售后规则来哦。';
    }
    if (hit(['几人', '双人', '含什么', '包含', '有什么', '套餐'])) {
      return '套餐大概是这样：$ctx。细项再看一眼商品页。';
    }
    if (hit(['味道', '好不好吃', '推荐', '值不值', '怎么样'])) {
      return '口味看个人，资料上适合想省事吃一顿的，建议再翻翻评价。';
    }
    if (hit(['你好', '在吗', '主播', '嗨', 'hello'])) {
      return '在呢，直接问我就行。';
    }
    if (hit(['疼', '病', '药', '医', '发烧', '肚子'])) {
      return '先歇会儿、喝点温水；要是一直不缓解或者疼得厉害，尽快去看医生，这个我没法替你判断。';
    }

    // 通用：对着问题答，不把整段商品介绍倒出来
    return '这个我按商品页跟你说最准。你刚问的是「$question」，页面上没有的我就不乱承诺。';
  }

  /// 供创作工厂等模块复用的通用生成入口
  Future<String> generateRaw({
    required String system,
    required String user,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    if (!isLiveLlm) {
      throw StateError('演示模式请走本地模板，勿直接调用 generateRaw');
    }
    final sw = Stopwatch()..start();
    try {
      final content = await _chat(
        system: system,
        user: user,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      sw.stop();
      lastCallMeta = 'live ${sw.elapsedMilliseconds}ms · $model';
      return content;
    } catch (e) {
      lastCallMeta = 'error';
      throw Exception(_friendlyError(e));
    }
  }

  Future<String> _chat({
    required String system,
    required String user,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'temperature': temperature,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('LLM 返回 choices 为空');
    }
    final message = choices.first['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?)?.trim();
    if (content == null || content.isEmpty) {
      throw Exception('LLM 返回 content 为空');
    }
    return content;
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return '网络不通：请检查手机网络或 Base URL 是否可访问';
    }
    if (raw.contains('401') || raw.contains('Unauthorized') || raw.contains('invalid_api_key')) {
      return '鉴权失败：API Key 无效或未开通对应模型';
    }
    if (raw.contains('402') || raw.contains('Insufficient')) {
      return '余额不足：请给该 LLM 账号充值';
    }
    if (raw.contains('429')) {
      return '请求过于频繁，请稍后再试';
    }
    if (raw.contains('TimeoutException')) {
      return '请求超时：可换更快模型或检查网络';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  String _demoScript({
    required String industry,
    required String product,
    required String sellingPoints,
    required int minutes,
  }) {
    return '''
【开场 · AI披露】
家人们好，欢迎来到直播间。先跟大家说清楚：本场主播是人工智能技术生成的数字人，讲解内容基于商家提供的商品资料。有问题可以打在公屏，我们按事实回答。

【痛点】
做$industry的老板都懂，真人主播排班难、话术不稳定，晚上和午间黄金档经常空场。今天用数字人帮大家把「$product」讲清楚。

【讲解 · 约$minutes分钟节奏】
卖点一句话先给到：$sellingPoints
接下来按「是什么 → 适合谁 → 怎么用/怎么到店」拆开说，每一段都会对照商品页参数，不夸大、不包治、不承诺稳赚。

【互动】
想了解规格/套餐/配送范围的，扣「1」；想对比同类的，扣「对比」。我只引用已绑定的商品库字段。

【促单】
现在下单/到店核销的家人们，按直播间挂链或门店活动走。库存与价格以页面实时显示为准。

【收尾 · 合规】
再次提醒：本场人物形象与语音由 AI 技术生成。感谢收看，我们下播见。
'''.trim();
  }
}
