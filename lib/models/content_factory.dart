class VideoPromptInput {
  const VideoPromptInput({
    required this.subject,
    required this.script,
    required this.scene,
    this.dynamics =
        '口型与台词100%同步，面部自然微笑与眨眼，手部有指向屏幕侧方商品的动作',
    this.camera = '中景，缓慢向前推镜，全程稳定无抖动',
    this.constraints =
        '4K超清，60帧，面部五官清晰不扭曲，动作流畅无卡顿，真人质感；须保留AI数字人标识',
  });

  final String subject;
  final String script;
  final String scene;
  final String dynamics;
  final String camera;
  final String constraints;
}

class HostScriptInput {
  const HostScriptInput({
    required this.hostName,
    required this.personality,
    required this.product,
    required this.price,
    required this.sellingPoints,
    required this.audience,
  });

  final String hostName;
  final String personality;
  final String product;
  final String price;
  final String sellingPoints;
  final String audience;
}

class DanmakuReply {
  const DanmakuReply({required this.question, required this.answer});

  final String question;
  final String answer;
}

class HostScriptResult {
  const HostScriptResult({
    required this.fullScript,
    required this.danmakuReplies,
    required this.source,
  });

  final String fullScript;
  final List<DanmakuReply> danmakuReplies;
  final String source;
}
