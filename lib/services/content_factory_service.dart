import '../models/content_factory.dart';
import 'llm_service.dart';

/// 短视频提示词 + 黄金三段式话术工厂（演示模板 / 真实 LLM）
class ContentFactoryService {
  ContentFactoryService(this.llm);

  final LlmService llm;

  /// 万能公式：【主体】+【台词】+【动态】+【场景】+【镜头】+【约束】
  String buildVideoPromptLocal(VideoPromptInput input) {
    return '''
【主体设定】${input.subject}
【口播台词】${input.script}
【面部与肢体动态】${input.dynamics}
【场景与光影】${input.scene}
【镜头运动】${input.camera}
【画质与约束】${input.constraints}
'''.trim();
  }

  Future<String> generateVideoPrompt(VideoPromptInput input) async {
    final local = buildVideoPromptLocal(input);
    if (!llm.isLiveLlm) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      llm.lastCallMeta = 'demo video-prompt';
      return local;
    }

    final refined = await llm.generateRaw(
      system: '你是AI数字人短视频提示词工程师。只输出提示词正文，不要解释。'
          '必须保留AI数字人合规标识约束，禁止写“无AI痕迹以规避标识”。',
      user: '请基于下列字段润色为一段可直接用于视频生成的中文提示词，'
          '严格使用【主体设定】【口播台词】【面部与肢体动态】【场景与光影】【镜头运动】【画质与约束】六段标题：\n\n$local',
      temperature: 0.6,
      maxTokens: 900,
    );
    return refined;
  }

  HostScriptResult buildHostScriptLocal(HostScriptInput input) {
    final script = '''
你现在是专业的抖音带货AI主播，名叫${input.hostName}。性格：${input.personality}。
产品：${input.product}，售价${input.price}，卖点：${input.sellingPoints}
目标人群：${input.audience}

—— 黄金三段式脚本 ——

【3秒痛点引入】
（身体微微前倾，眼神看镜头，语气急切但亲切）
「家人们！还在为「懒得折腾/没时间弄」发愁吗？有没有！」

【15秒卖点展示与场景代入】
（举起商品轻轻展示，微笑眨眼）
「看这个${input.product}，只要${input.price}。${input.sellingPoints}。
（比划使用场景）
特别适合${input.audience}。参数以商品页为准哈——我是AI数字人${input.hostName}，给你们讲清楚再决定。」

【5秒限时福利逼单】
（手指下方小黄车，语速加快半拍）
「直播间价${input.price}，库存就这波！点小黄车拍下！犹豫的扣1，我教你下单！」
'''.trim();

    final replies = [
      DanmakuReply(
        question: '怎么买',
        answer:
            '「扣个1我看见啦！点下方小黄车，选规格下单就行～有问题再喊我，我是AI数字人${input.hostName}。」',
      ),
      DanmakuReply(
        question: '能用多久',
        answer:
            '「正常按说明使用、好好保养能陪你很久；具体质保以商品页为准，我不瞎承诺年限～」',
      ),
      DanmakuReply(
        question: '有运费险吗',
        answer: '「运费险以小黄车商品页和店铺说明为准哈；下单前滑到保障那里看一眼最稳！」',
      ),
    ];

    return HostScriptResult(
      fullScript: script,
      danmakuReplies: replies,
      source: 'local-template',
    );
  }

  Future<HostScriptResult> generateHostScript(HostScriptInput input) async {
    final local = buildHostScriptLocal(input);
    if (!llm.isLiveLlm) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      llm.lastCallMeta = 'demo host-script';
      return local;
    }

    final raw = await llm.generateRaw(
      system: '你是抖音带货AI主播编剧。输出极度口语化中文短句。'
          '必须用括号标注动作与情绪。开场需披露AI数字人身份。'
          '禁止绝对化功效与虚假承诺。',
      user: '''
主播名：${input.hostName}
性格：${input.personality}
产品：${input.product}
价格：${input.price}
卖点：${input.sellingPoints}
人群：${input.audience}

请生成完整直播话术：
1) 黄金三段式（3秒痛点 + 15秒卖点场景 + 5秒逼单）
2) 预设3条弹幕回复：怎么买 / 能用多久 / 有运费险吗

格式：
【脚本】
...
【弹幕回复】
怎么买：...
能用多久：...
有运费险吗：...
''',
      temperature: 0.75,
      maxTokens: 1400,
    );

    return _parseHostScript(raw, fallback: local);
  }

  HostScriptResult _parseHostScript(String raw, {required HostScriptResult fallback}) {
    final replies = <DanmakuReply>[];
    final lines = raw.split('\n');
    for (final line in lines) {
      final t = line.trim();
      for (final q in ['怎么买', '能用多久', '有运费险吗']) {
        if (t.startsWith(q)) {
          final ans = t.contains('：')
              ? t.split('：').skip(1).join('：').trim()
              : t.contains(':')
                  ? t.split(':').skip(1).join(':').trim()
                  : t;
          if (ans.isNotEmpty) {
            replies.add(DanmakuReply(question: q, answer: ans));
          }
        }
      }
    }

    final scriptPart = raw.contains('【弹幕回复】')
        ? raw.split('【弹幕回复】').first.replaceFirst('【脚本】', '').trim()
        : raw.trim();

    if (scriptPart.isEmpty) return fallback;

    return HostScriptResult(
      fullScript: scriptPart,
      danmakuReplies: replies.length >= 3 ? replies.take(3).toList() : fallback.danmakuReplies,
      source: 'llm',
    );
  }
}
