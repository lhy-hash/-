import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_role.dart';
import '../models/analytics_snapshot.dart';
import '../models/checklist_item.dart';
import '../models/digital_human_config.dart';
import '../models/live_script.dart';
import '../services/compliance_service.dart';
import '../services/digital_human_engine.dart';
import '../services/llm_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    LlmService? llmService,
    ComplianceService? complianceService,
    DigitalHumanEngine? digitalHumanEngine,
  })  : llm = llmService ?? LlmService(),
        compliance = complianceService ?? ComplianceService(),
        dhEngine = digitalHumanEngine ?? DigitalHumanEngine() {
    checklist = compliance.createGoLiveChecklist();
    scripts = _seedScripts();
    analytics = _seedAnalytics();
  }

  final LlmService llm;
  final ComplianceService compliance;
  final DigitalHumanEngine dhEngine;


  int tabIndex = 0;
  bool aiLabelEnabled = true;
  bool isLive = false;
  bool generating = false;
  String? lastError;
  String shopName = '喜乐本地生活旗舰店';
  String selectedAvatar = '小乐 · 邻家讲解员';

  late List<LiveScript> scripts;
  late List<ChecklistItem> checklist;
  late AnalyticsSnapshot analytics;

  Future<void> init() async {
    await llm.load();
    await _loadDhConfig();
    // 统一：电脑 LiveTalking 真人出镜（用户已选电脑引擎）
    dhEngine.config.provider = DhProvider.local;
    dhEngine.config.enabled = true;
    if (isAdminApp) {
      dhEngine.config.engineBaseUrl = 'http://127.0.0.1:8010';
    } else {
      final cur = dhEngine.config.engineBaseUrl.trim();
      // USB 调试时 adb reverse tcp:8010 tcp:8010 已把手机 127.0.0.1:8010 转发到电脑引擎。
      // 默认走 127.0.0.1 最稳；若 reverse 失效，大厅探测会自动切到热点网段地址。
      if (cur.isEmpty || cur.contains('192.168.100.103')) {
        dhEngine.config.engineBaseUrl = 'http://127.0.0.1:8010';
      }
    }
    await _persistDhConfig(dhEngine.config);
    notifyListeners();
  }

  void setTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  void setAiLabel(bool value) {
    aiLabelEnabled = value;
    notifyListeners();
  }

  void toggleChecklist(String id, bool value) {
    checklist = checklist
        .map((e) => e.id == id ? e.copyWith(checked: value) : e)
        .toList();
    notifyListeners();
  }

  bool get canGoLive =>
      aiLabelEnabled && compliance.canGoLive(checklist);

  List<String> scanScript(String content) =>
      compliance.scanForbiddenClaims(content);

  Future<void> generateAndAddScript({
    required String industry,
    required String product,
    required String sellingPoints,
    required int minutes,
    required LiveScriptCategory category,
  }) async {
    generating = true;
    lastError = null;
    notifyListeners();
    try {
      final content = await llm.generateScript(
        industry: industry,
        product: product,
        sellingPoints: sellingPoints,
        minutes: minutes,
      );
      final hits = scanScript(content);
      final safeNote = hits.isEmpty
          ? ''
          : '\n\n【合规提示】检测到敏感词：${hits.join("、")}，请人工修订后再开播。';

      final sourceTag = llm.isLiveLlm ? '真实LLM' : '演示';
      scripts = [
        LiveScript(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '$product · AI话术',
          category: category,
          content: content + safeNote,
          durationMinutes: minutes,
          tags: [
            industry,
            sourceTag,
            if (llm.lastCallMeta != null) llm.lastCallMeta!,
            if (hits.isNotEmpty) '待审',
          ],
        ),
        ...scripts,
      ];
    } catch (e) {
      lastError = e.toString();
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  void deleteScript(String id) {
    scripts = scripts.where((e) => e.id != id).toList();
    notifyListeners();
  }

  void addGeneratedContent({
    required String title,
    required String content,
    required LiveScriptCategory category,
    List<String> tags = const [],
    int durationMinutes = 3,
  }) {
    final hits = scanScript(content);
    final safeNote = hits.isEmpty
        ? ''
        : '\n\n【合规提示】检测到敏感词：${hits.join("、")}，请人工修订后再开播。';
    scripts = [
      LiveScript(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        category: category,
        content: content + safeNote,
        durationMinutes: durationMinutes,
        tags: [
          ...tags,
          llm.isLiveLlm ? '真实LLM' : '演示',
          if (hits.isNotEmpty) '待审',
        ],
      ),
      ...scripts,
    ];
    notifyListeners();
  }

  void startLive() {
    if (!canGoLive) return;
    isLive = true;
    notifyListeners();
  }

  void stopLive() {
    isLive = false;
    notifyListeners();
  }

  Future<void> saveLlmSettings({
    required String apiKey,
    required String baseUrl,
    required String model,
    required bool demoMode,
    String? providerId,
  }) async {
    await llm.save(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      demoMode: demoMode,
      providerId: providerId,
    );
    notifyListeners();
  }

  void saveDigitalHumanConfig(DigitalHumanConfig config) {
    dhEngine.updateConfig(config);
    unawaited(_persistDhConfig(config));
    notifyListeners();
  }

  Future<void> _loadDhConfig() async {
    try {
      final f = await _dhSettingsFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map<String, dynamic>) {
        dhEngine.updateConfig(DigitalHumanConfig.fromJson(raw));
      } else if (raw is Map) {
        dhEngine.updateConfig(
          DigitalHumanConfig.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
    } catch (_) {}
  }

  Future<void> _persistDhConfig(DigitalHumanConfig config) async {
    try {
      final f = await _dhSettingsFile();
      await f.writeAsString(jsonEncode(config.toJson()));
    } catch (_) {}
  }

  Future<File> _dhSettingsFile() async {
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
    return File('${dir.path}${Platform.pathSeparator}dh_settings.json');
  }

  List<LiveScript> _seedScripts() {
    return [
      LiveScript(
        id: 's1',
        title: '喜乐鲜味礼盒·15分钟带货',
        category: LiveScriptCategory.ecommerce,
        durationMinutes: 15,
        tags: const ['美食', '礼盒', '带货'],
        content: '''
家人们好，本场主播是人工智能技术生成的数字人。
今天主推喜乐鲜味礼盒。
直播间九九元。
九-九-元到手。
卖点：食材扎实、做法省事、分量够分享、家常鲜香。
开播流程：先播视频原声口型，再自动循环本场15分钟口播。
觉得划算的扣1，想要的扣想要。
''',
      ),
      LiveScript(
        id: 's2',
        title: '春季薄外套卖点讲解',
        category: LiveScriptCategory.ecommerce,
        durationMinutes: 20,
        tags: const ['服饰', '带货'],
        content: '''
【开场 · AI披露】
大家好，当前讲解形象由 AI 技术生成。这件薄外套的面料、尺码表都来自商品详情，不额外承诺效果。

【讲解】
轻薄透气，适合换季通勤；颜色按页面色卡展示，建议对照尺码表下单。

【互动】
想看细节扣色号，想问面料扣「面料」。
''',
      ),
    ];
  }

  AnalyticsSnapshot _seedAnalytics() {
    return const AnalyticsSnapshot(
      liveHours: 28.5,
      avgViewers: 186,
      inquiries: 412,
      orders: 97,
      aiCostYuan: 286.4,
      weekTrend: [
        DayMetric(dayLabel: '一', viewers: 120, orders: 8),
        DayMetric(dayLabel: '二', viewers: 160, orders: 12),
        DayMetric(dayLabel: '三', viewers: 210, orders: 15),
        DayMetric(dayLabel: '四', viewers: 180, orders: 11),
        DayMetric(dayLabel: '五', viewers: 240, orders: 19),
        DayMetric(dayLabel: '六', viewers: 320, orders: 22),
        DayMetric(dayLabel: '日', viewers: 280, orders: 10),
      ],
    );
  }
}
