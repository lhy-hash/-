/// 喜乐 AI 数字人直播 — 架构方案静态内容（App 内可浏览）
class ArchitectureCatalog {
  static const stackRows = <ArchitectureStackRow>[
    ArchitectureStackRow(
      layer: 'LLM',
      openSource: 'Qwen / DeepSeek（OpenAI 兼容）+ 规则闸门',
      commercial: '通义、文心、Moonshot',
      suggest: 'DeepSeek/通义 API + 商品 RAG + 禁售词拦截',
    ),
    ArchitectureStackRow(
      layer: 'TTS',
      openSource: 'CosyVoice / GPT-SoVITS / Fish-Speech',
      commercial: '火山豆包、阿里云、腾讯云 TTS',
      suggest: '先云 TTS；要克隆音色再上 CosyVoice',
    ),
    ArchitectureStackRow(
      layer: '实时渲染',
      openSource: 'LiveTalking（Wav2Lip/MuseTalk）',
      commercial: '即构数字人、百度慧播星、腾讯云数智人',
      suggest: '前 3 月 PaaS；自建用 LiveTalking 底座',
    ),
    ArchitectureStackRow(
      layer: '推流',
      openSource: 'SRS / Nginx-RTMP + FFmpeg',
      commercial: '即构/声网 RTC；平台直播云',
      suggest: '预览 WebRTC；上平台 RTMP/官方 SDK',
    ),
    ArchitectureStackRow(
      layer: '控台',
      openSource: 'Flutter（喜乐 App）',
      commercial: '—',
      suggest: 'Flutter 只做控制编排，不跑重推理',
    ),
    ArchitectureStackRow(
      layer: '编排',
      openSource: 'FastAPI / Go + Redis',
      commercial: '云 Kafka（大规模）',
      suggest: 'FastAPI 网关串 LLM→TTS→渲染→推流',
    ),
  ];

  static const pipeline = '''
[观众弹幕/语音]
    → 平台 Webhook / 控台输入 / ASR
[接入层 Ingress]
    → 鉴权、限流、roomId、合规预检
[AI 大脑 Orchestrator]
    → 意图分类 → RAG 商品事实 → LLM 流式回复 → 敏感词过滤
[语音层 TTS]
    → 文本转音频流（可带情绪）
[数字人驱动 Engine]
    → 口型 / 表情 / 动作编排 → 合成音视频帧
[推流层 Media Gateway]
    → WebRTC 预览（Flutter）
    → RTMP / 平台 SDK → 抖音/视频号/快手
[合规旁路]
    → AI 标识水印、话术与切片留存、一键停播
''';

  static const flutterChannels = <ChannelSpec>[
    ChannelSpec(
      name: 'com.xile/media',
      type: 'MethodChannel',
      usage: '开播/停播、切线路、设 RTMP URL、切形象',
    ),
    ChannelSpec(
      name: 'com.xile/ai',
      type: 'MethodChannel',
      usage: '下发话术、打断、动作指令（挥手/指向）',
    ),
    ChannelSpec(
      name: 'com.xile/media_events',
      type: 'EventChannel',
      usage: '推流码率、断线、观众数、渲染 FPS',
    ),
    ChannelSpec(
      name: 'com.xile/danmaku',
      type: 'EventChannel',
      usage: '弹幕 / ASR 文本流',
    ),
  ];

  static const pathAdvice = '''
结论：采用「开源底座 + PaaS 接口」二次开发，不要从零自研底层算法。

• 从零自研口型/渲染/推流：12–24 月，ROI 差
• 开源底座 + PaaS：1–3 月可商用试点（推荐）
• 纯全托管 SaaS：最快验证，后期再混合降本

分阶段
P0  Flutter 控台 + 模拟直播间 + LLM/TTS 互动（已完成）
P1  接云数字人 + RTMP 测试流
P2  弹幕平台接入、商品 RAG、7×24 主备
P3  自建 LiveTalking 降本、多房间调度
''';

  static const haTips = [
    '双路渲染（主备 GPU / 双实例）',
    '推流断线自动重连 + 脚本队列保底口播',
    '人工一键接管',
    'AI 角标常驻与直播日志留存',
  ];
}

class ArchitectureStackRow {
  const ArchitectureStackRow({
    required this.layer,
    required this.openSource,
    required this.commercial,
    required this.suggest,
  });

  final String layer;
  final String openSource;
  final String commercial;
  final String suggest;
}

class ChannelSpec {
  const ChannelSpec({
    required this.name,
    required this.type,
    required this.usage,
  });

  final String name;
  final String type;
  final String usage;
}
