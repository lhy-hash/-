/// 站立 / 坐播主播形象目录：每人一个形象，男女声强制匹配
class HostPresenceProfile {
  const HostPresenceProfile({
    required this.id,
    required this.label,
    required this.avatarId,
    required this.voiceProfileId,
    required this.pose,
    required this.gender,
    this.actionsConfig = '',
    this.hint = '',
  });

  final String id;
  final String label;
  final String avatarId;
  final String voiceProfileId;
  final HostPose pose;
  final HostGender gender;
  final String actionsConfig;
  final String hint;

  bool get isMale => gender == HostGender.male;
  bool get isFemale => gender == HostGender.female;

  /// 上传视频生成的真人形象（口型配对）+ 原第 3 个：喜喜
  static const presets = <HostPresenceProfile>[
    HostPresenceProfile(
      id: 'host_upload',
      label: '上传形象 · 原声口型',
      avatarId: 'user_upload_host',
      voiceProfileId: 'upload_natural',
      pose: HostPose.stand,
      gender: HostGender.female,
      actionsConfig: 'data/xile_actions_upload_host.json',
      hint: '视频原声开播 · 慢速口型 · 挥手点头',
    ),
    HostPresenceProfile(
      id: 'host_xixi',
      label: '喜喜 · 站立美食',
      avatarId: 'dh_xixi',
      voiceProfileId: 'xixi_sweet',
      pose: HostPose.stand,
      gender: HostGender.female,
      hint: '女站立 · 甜感女声',
    ),
  ];

  static HostPresenceProfile? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  static HostPresenceProfile? byAvatarId(String? avatarId) {
    if (avatarId == null || avatarId.isEmpty) return null;
    for (final p in presets) {
      if (p.avatarId == avatarId) return p;
    }
    if (avatarId == 'user_upload_host' || avatarId == 'host_upload') {
      return byId('host_upload');
    }
    if (avatarId == 'dh_xixi' || avatarId == 'host_xixi') {
      return byId('host_xixi');
    }
    return null;
  }

  static HostPresenceProfile get defaultHost => presets.first;

  static const audiotypeIdle = 1;
  static const audiotypeWave = 2;
  static const audiotypeNod = 3;
  static const audiotypePoint = 4;
  /// 服务端用 /api/xile/play_original 播原声（非 set_audiotype）
  static const audiotypeOriginal = 5;
}

enum HostPose { stand, sit }

enum HostGender { female, male }
