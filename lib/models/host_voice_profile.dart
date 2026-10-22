/// 每个数字人主播的独立音色：通义 Qwen TTS + EdgeTTS + 百度 per
class HostVoiceProfile {
  const HostVoiceProfile({
    required this.id,
    required this.label,
    required this.edgeVoice,
    required this.qwenVoice,
    required this.baiduPer,
    this.baiduSpd = 5,
    this.baiduPit = 5,
    this.baiduVol = 5,
    this.localRate = 0.52,
    this.localPitch = 1.0,
    this.edgeRate = '-18%',
    this.gender = VoiceGender.female,
    this.styleHint = '自然口语、像真人主播',
  });

  final String id;
  final String label;

  /// LiveTalking EdgeTTS 音色
  final String edgeVoice;

  /// 通义 Qwen3-TTS 真人音色（App 端主播口播）
  final String qwenVoice;

  /// 百度 TTS 发音人
  final String baiduPer;
  final int baiduSpd;
  final int baiduPit;
  final int baiduVol;

  final double localRate;
  final double localPitch;
  /// EdgeTTS 语速，-42% 让口型别抢
  final String edgeRate;
  final VoiceGender gender;
  final String styleHint;

  Map<String, dynamic> toBaiduTts() => {
        'per': int.tryParse(baiduPer) ?? 5118,
        'spd': baiduSpd.clamp(1, 15),
        'pit': baiduPit.clamp(1, 15),
        'vol': baiduVol.clamp(1, 15),
      };

  /// 引擎 TTS：优先 Edge 神经音色；附带 qwen 字段兼容旧引擎；rate 控制语速
  Map<String, dynamic> toEngineTts() => {
        'ref_file': edgeVoice,
        'voice': edgeVoice,
        'edge_voice': edgeVoice,
        'qwen_voice': qwenVoice,
        // EdgeTTS：负数更慢，上传原声形象默认更慢更自然
        'rate': edgeRate,
      };

  static const presets = <HostVoiceProfile>[
    HostVoiceProfile(
      id: 'mei_bright',
      label: '小美 · 清亮女声',
      edgeVoice: 'zh-CN-XiaoxiaoNeural',
      qwenVoice: 'Cherry',
      baiduPer: '0',
      baiduSpd: 6,
      baiduPit: 6,
      localRate: 0.55,
      localPitch: 1.10,
      gender: VoiceGender.female,
      styleHint: '阳光亲和，像真人带货主播',
    ),
    HostVoiceProfile(
      id: 'ale_steady',
      label: '阿乐 · 沉稳男声',
      edgeVoice: 'zh-CN-YunxiNeural',
      qwenVoice: 'Ethan',
      baiduPer: '1',
      baiduSpd: 5,
      baiduPit: 4,
      localRate: 0.50,
      localPitch: 0.92,
      gender: VoiceGender.male,
      styleHint: '沉稳可信，像真人讲解员',
    ),
    HostVoiceProfile(
      id: 'xixi_sweet',
      label: '喜喜 · 甜感女声',
      edgeVoice: 'zh-CN-XiaomengNeural',
      qwenVoice: 'Chelsie',
      baiduPer: '111',
      baiduSpd: 5,
      baiduPit: 7,
      localRate: 0.42,
      localPitch: 1.08,
      edgeRate: '-18%',
      gender: VoiceGender.female,
      styleHint: '稍慢、自然，贴近上传视频口吻',
    ),
    HostVoiceProfile(
      id: 'upload_natural',
      label: '上传形象 · 慢速自然',
      edgeVoice: 'zh-CN-XiaoxiaoNeural',
      qwenVoice: 'Cherry',
      baiduPer: '0',
      baiduSpd: 4,
      baiduPit: 5,
      localRate: 0.46,
      localPitch: 1.04,
      edgeRate: '-18%',
      gender: VoiceGender.female,
      styleHint: '开播用视频原声；互动慢速女声',
    ),
    HostVoiceProfile(
      id: 'ya_soft',
      label: '小雅 · 柔和女声',
      edgeVoice: 'zh-CN-XiaoyiNeural',
      qwenVoice: 'Serena',
      baiduPer: '4',
      baiduSpd: 5,
      baiduPit: 6,
      localRate: 0.50,
      localPitch: 1.12,
      gender: VoiceGender.female,
      styleHint: '温柔自然，像真人护肤顾问',
    ),
    HostVoiceProfile(
      id: 'ajie_clear',
      label: '阿杰 · 清晰男声',
      edgeVoice: 'zh-CN-YunyangNeural',
      qwenVoice: 'Moon',
      baiduPer: '106',
      baiduSpd: 6,
      baiduPit: 5,
      localRate: 0.53,
      localPitch: 0.95,
      gender: VoiceGender.male,
      styleHint: '字正腔圆，像真人运动达人',
    ),
    HostVoiceProfile(
      id: 'nuo_warm',
      label: '糯糯 · 温暖女声',
      edgeVoice: 'zh-CN-XiaochenNeural',
      qwenVoice: 'Maia',
      baiduPer: '5118',
      baiduSpd: 5,
      baiduPit: 5,
      localRate: 0.52,
      localPitch: 1.06,
      gender: VoiceGender.female,
      styleHint: '温暖亲切，像真人邻家主播',
    ),
  ];

  /// 形象 ID / 主播名 → 固定音色（二次审核绑定表）
  static const hostBindings = <String, String>{
    // avatarId
    'host_white_suit': 'mei_bright',
    'host_navy_suit': 'ale_steady',
    'wav2lip_avatar_female_model': 'mei_bright',
    'wav2lip_avatar_glass_man': 'ale_steady',
    'dh_xiaomei': 'mei_bright',
    'dh_ale': 'ale_steady',
    'user_upload_host': 'upload_natural',
    'host_upload': 'upload_natural',
    'dh_xixi': 'xixi_sweet',
    'dh_xiaoya': 'ya_soft',
    'dh_ajie': 'ajie_clear',
    'dh_nuonuo': 'nuo_warm',
    // hostName
    '白西装': 'mei_bright',
    '深蓝西装': 'ale_steady',
    '小美': 'mei_bright',
    '阿乐': 'ale_steady',
    '喜喜': 'xixi_sweet',
    '小雅': 'ya_soft',
    '阿杰': 'ajie_clear',
    '糯糯': 'nuo_warm',
    // roomId
    'room_beauty': 'mei_bright',
    'room_digital': 'ale_steady',
    'room_food': 'xixi_sweet',
    'room_skincare': 'ya_soft',
    'room_sport': 'ajie_clear',
    'room_home': 'nuo_warm',
  };

  static HostVoiceProfile? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 按主播名 / 形象 ID / 房间 稳定分配：同一主播始终同一把声
  static HostVoiceProfile resolve({
    String? hostName,
    String? avatarId,
    String? roomId,
    String? preferredId,
  }) {
    final preferred = byId(preferredId);
    if (preferred != null) return preferred;

    for (final key in [avatarId, hostName, roomId]) {
      final id = hostBindings[key ?? ''];
      final hit = byId(id);
      if (hit != null) return hit;
    }

    final name = (hostName ?? '').trim();
    // 明确男声主播名（避免「阿乐」因「乐」字误判成女声）
    if (RegExp(r'^(阿乐|阿杰|小宇|逍遥|博文)$').hasMatch(name) ||
        RegExp(r'(哥|先生|大叔)$').hasMatch(name)) {
      return byId('ale_steady')!;
    }
    if (RegExp(r'(姐|妹|美|雅|萌|娇|糯|喜)$').hasMatch(name) ||
        name.contains('小美') ||
        name.contains('小雅') ||
        name.contains('喜喜') ||
        name.contains('糯糯')) {
      return byId('mei_bright')!;
    }

    // 其余：按 avatarId 哈希在同性别池里错开（尽量不撞声）
    final key = '${hostName ?? ''}|${avatarId ?? ''}|${roomId ?? ''}'.toLowerCase();
    var hash = 0;
    for (final c in key.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final maleHint = RegExp(
      r'glass_man|dh_ale|dh_ajie|host_navy_suit|male|_man|男',
      caseSensitive: false,
    ).hasMatch(avatarId ?? '');
    final pool = presets
        .where((p) =>
            maleHint ? p.gender == VoiceGender.male : p.gender == VoiceGender.female)
        .toList();
    return pool[hash % pool.length];
  }
}

enum VoiceGender { female, male }
