import '../models/checklist_item.dart';

/// 合规闸门：对齐《直播电商监督管理办法》AI 标识与虚假宣传要求
class ComplianceService {
  static const blockedPhrases = [
    '包治',
    '根治',
    '国家级',
    '最高级',
    '第一品牌',
    '稳赚不赔',
    '百分之百',
    '医疗级',
    '药到病除',
  ];

  List<String> scanForbiddenClaims(String text) {
    final hits = <String>[];
    for (final phrase in blockedPhrases) {
      if (text.contains(phrase)) hits.add(phrase);
    }
    return hits;
  }

  List<ChecklistItem> createGoLiveChecklist() {
    return const [
      ChecklistItem(
        id: 'ai_label',
        title: 'AI 生成持续标识',
        description: '画面角标「AI数字人」已开启，并配置定时口播提示。',
        kind: ChecklistKind.required,
      ),
      ChecklistItem(
        id: 'disclosure',
        title: '开场披露话术',
        description: '开播前 30 秒告知观众当前为人工智能技术生成形象。',
        kind: ChecklistKind.required,
      ),
      ChecklistItem(
        id: 'auth',
        title: '形象与声音授权',
        description: '已上传数字人形象/声音授权材料，未克隆未授权名人。',
        kind: ChecklistKind.required,
      ),
      ChecklistItem(
        id: 'product_bind',
        title: '商品信息绑定',
        description: '话术仅引用商品库事实字段，禁止 AI 自由编造参数。',
        kind: ChecklistKind.required,
      ),
      ChecklistItem(
        id: 'audit',
        title: '禁售词与夸大拦截',
        description: '脚本已通过合规扫描，无绝对化用语与功效承诺。',
        kind: ChecklistKind.required,
      ),
      ChecklistItem(
        id: 'human_watch',
        title: '人工值守（高风险类目）',
        description: '食药妆等类目建议真人盯场，一键停播可用。',
        kind: ChecklistKind.recommended,
      ),
      ChecklistItem(
        id: 'log',
        title: '直播日志留存',
        description: '脚本版本、操作记录、标识状态将自动留存备查。',
        kind: ChecklistKind.recommended,
      ),
    ];
  }

  bool canGoLive(List<ChecklistItem> items) {
    return items
        .where((e) => e.kind == ChecklistKind.required)
        .every((e) => e.checked);
  }
}
