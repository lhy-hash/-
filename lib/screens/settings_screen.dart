import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/digital_human_config.dart';
import '../models/host_presence_profile.dart';
import '../models/host_voice_profile.dart';
import '../services/live_room_controller.dart';
import '../services/llm_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _engineUrl;
  late final TextEditingController _avatarId;
  late final TextEditingController _rtmpUrl;
  late final TextEditingController _baiduAppId;
  late final TextEditingController _baiduAppKey;
  late final TextEditingController _baiduFigureId;
  late final TextEditingController _baiduAsrApiKey;
  late final TextEditingController _baiduAsrSecret;
  late String _voiceProfileId;
  late String _hostPresenceId;
  late bool _demoMode;
  late bool _dhEnabled;
  late String _providerId;
  late String _platform;
  late DhProvider _dhProvider;
  bool _testing = false;
  bool _pinging = false;
  bool _obscure = true;
  bool _obscureBaidu = true;
  bool _obscureAsr = true;
  String? _testMessage;
  String? _pingMessage;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final llm = state.llm;
    final dh = state.dhEngine.config;
    _apiKey = TextEditingController(text: llm.apiKey);
    _baseUrl = TextEditingController(text: llm.baseUrl);
    _model = TextEditingController(text: llm.model);
    _demoMode = llm.demoMode;
    _providerId = llm.providerId;
    _dhEnabled = dh.enabled;
    _dhProvider = dh.provider;
    _engineUrl = TextEditingController(text: dh.engineBaseUrl);
    _avatarId = TextEditingController(text: dh.avatarId);
    _rtmpUrl = TextEditingController(text: dh.rtmpUrl);
    _platform = dh.platformHint;
    _baiduAppId = TextEditingController(text: dh.baiduAppId);
    _baiduAppKey = TextEditingController(text: dh.baiduAppKey);
    _baiduFigureId = TextEditingController(text: dh.baiduFigureId);
    _baiduAsrApiKey = TextEditingController(text: dh.baiduAsrApiKey);
    _baiduAsrSecret = TextEditingController(text: dh.baiduAsrSecretKey);
    _voiceProfileId = dh.voiceProfileId.isNotEmpty
        ? dh.voiceProfileId
        : HostVoiceProfile.resolve(avatarId: dh.avatarId).id;
    _hostPresenceId = dh.hostPresenceId.isNotEmpty
        ? dh.hostPresenceId
        : (HostPresenceProfile.byAvatarId(dh.avatarId)?.id ?? 'host_xixi');
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _engineUrl.dispose();
    _avatarId.dispose();
    _rtmpUrl.dispose();
    _baiduAppId.dispose();
    _baiduAppKey.dispose();
    _baiduFigureId.dispose();
    _baiduAsrApiKey.dispose();
    _baiduAsrSecret.dispose();
    super.dispose();
  }

  void _applyPreset(LlmProviderPreset preset) {
    setState(() {
      _providerId = preset.id;
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.model;
    });
  }

  Future<void> _saveLlm(AppState state) async {
    await state.saveLlmSettings(
      apiKey: _apiKey.text,
      baseUrl: _baseUrl.text,
      model: _model.text,
      demoMode: _demoMode,
      providerId: _providerId,
    );
    if (!mounted) return;
    try {
      unawaited(context.read<LiveRoomController>().refreshHostVoice());
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.llm.isLiveLlm
              ? 'LLM 已保存 · ${state.llm.model}（应用宝语音将走云识别）'
              : 'LLM 已保存 · 演示模式',
        ),
      ),
    );
  }

  void _saveDh(AppState state) {
    final presence = HostPresenceProfile.byId(_hostPresenceId) ??
        HostPresenceProfile.defaultHost;
    final voice = HostVoiceProfile.byId(presence.voiceProfileId) ??
        HostVoiceProfile.byId(_voiceProfileId) ??
        HostVoiceProfile.presets.first;
    // 男女形象强制匹配音色
    final lockedVoice = presence.isMale
        ? (voice.gender == VoiceGender.male
            ? voice
            : HostVoiceProfile.byId('ale_steady')!)
        : (voice.gender == VoiceGender.female
            ? voice
            : HostVoiceProfile.byId(presence.voiceProfileId)!);
    state.saveDigitalHumanConfig(
      DigitalHumanConfig(
        enabled: _dhEnabled,
        provider: _dhProvider,
        engineBaseUrl: _engineUrl.text.trim(),
        avatarId: presence.avatarId,
        hostPresenceId: presence.id,
        rtmpUrl: _rtmpUrl.text.trim(),
        platformHint: _platform,
        baiduAppId: _baiduAppId.text.trim(),
        baiduAppKey: _baiduAppKey.text.trim(),
        baiduFigureId: _baiduFigureId.text.trim().isEmpty
            ? 'A2A_V2-muqing'
            : _baiduFigureId.text.trim(),
        baiduTtsPer: lockedVoice.baiduPer,
        baiduTtsSpd: lockedVoice.baiduSpd,
        baiduTtsPit: lockedVoice.baiduPit,
        baiduTtsVol: lockedVoice.baiduVol,
        voiceProfileId: lockedVoice.id,
        baiduAsrApiKey: _baiduAsrApiKey.text.trim(),
        baiduAsrSecretKey: _baiduAsrSecret.text.trim(),
      ),
    );
    _avatarId.text = presence.avatarId;
    _voiceProfileId = lockedVoice.id;
    try {
      unawaited(
        context.read<LiveRoomController>().applyPresence(presence),
      );
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !_dhEnabled
              ? '已关闭真实引擎（本地演示）'
              : _dhProvider == DhProvider.baidu
                  ? '已切换为百度曦灵 · 音色「${lockedVoice.label}」'
                  : '已切换「${presence.label}」· ${lockedVoice.label}',
        ),
      ),
    );
  }

  Future<void> _testLlm(AppState state) async {
    await _saveLlm(state);
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    final result = await state.llm.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testMessage = result.ok
          ? '${result.message}（${result.latencyMs}ms）\n回复：${result.sample}'
          : result.message;
    });
  }

  Future<void> _pingEngine(AppState state) async {
    _saveDh(state);
    setState(() {
      _pinging = true;
      _pingMessage = null;
    });
    final health = await state.dhEngine.ping();
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _pingMessage = health.ok
          ? '${health.message}（${health.latencyMs}ms）'
          : health.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            const SectionHeader(
              title: '设置',
              subtitle: '电脑后台 · 实时数字人 + LLM',
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '实时数字人引擎',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      '当前：电脑 LiveTalking 引擎（真人出镜 + 口型）。\n'
                      '【你这种用法】手机开热点，电脑连手机 Wi‑Fi：\n'
                      '1. 电脑启动引擎（监听 8010）\n'
                      '2. 引擎地址填电脑在热点里的 IP：\n'
                      '   http://192.168.40.241:8010\n'
                      '3. 回到直播间等「真实数字人」接通\n'
                      '说明：画面走热点局域网；USB 只能辅助调试。',
                      style: TextStyle(height: 1.45),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用真实数字人引擎'),
                    value: _dhEnabled,
                    activeThumbColor: AppColors.textPrimary,
                    activeTrackColor: AppColors.brand,
                    onChanged: (v) => setState(() => _dhEnabled = v),
                  ),
                  Text('引擎类型', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('百度曦灵 · 实时直播'),
                        selected: _dhProvider == DhProvider.baidu,
                        onSelected: (_) => setState(() => _dhProvider = DhProvider.baidu),
                      ),
                      ChoiceChip(
                        label: const Text('本地 LiveTalking'),
                        selected: _dhProvider == DhProvider.local,
                        onSelected: (_) => setState(() => _dhProvider = DhProvider.local),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_dhProvider == DhProvider.baidu) ...[
                    TextField(
                      controller: _baiduAppId,
                      decoration: const InputDecoration(
                        labelText: '百度 AppID',
                        hintText: '曦灵开放平台应用 ID',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baiduAppKey,
                      obscureText: _obscureBaidu,
                      decoration: InputDecoration(
                        labelText: '百度 AppKey',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscureBaidu = !_obscureBaidu),
                          icon: Icon(_obscureBaidu ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baiduFigureId,
                      decoration: const InputDecoration(
                        labelText: '形象 figureId',
                        hintText: 'A2A_V2-muqing',
                      ),
                    ),
                  ] else ...[
                    Text('站立 / 坐播形象（男女声自动匹配）',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in HostPresenceProfile.presets)
                          ChoiceChip(
                            label: Text(p.label),
                            selected: _hostPresenceId == p.id,
                            onSelected: (_) => setState(() {
                              _hostPresenceId = p.id;
                              _avatarId.text = p.avatarId;
                              _voiceProfileId = p.voiceProfileId;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      HostPresenceProfile.byId(_hostPresenceId)?.hint ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _engineUrl,
                      decoration: const InputDecoration(
                        labelText: '本地引擎地址',
                        hintText: 'http://192.168.40.241:8010',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _avatarId,
                      decoration: const InputDecoration(
                        labelText: 'Avatar ID（随形象包自动填写）',
                        hintText: 'wav2lip_avatar_female_model',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _rtmpUrl,
                      decoration: const InputDecoration(
                        labelText: '平台 RTMP（可选备注）',
                        hintText: 'rtmp://... 抖音/快手开播地址',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: HostVoiceProfile.byId(_voiceProfileId)?.id ??
                        HostVoiceProfile.presets.first.id,
                    decoration: const InputDecoration(
                      labelText: '数字人音色（每人不同）',
                      helperText: '不同主播自动错开；也可在此指定固定音色',
                    ),
                    items: [
                      for (final v in HostVoiceProfile.presets)
                        DropdownMenuItem(
                          value: v.id,
                          child: Text('${v.label} · ${v.styleHint}'),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => _voiceProfileId = id);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '语音提问（应用宝必看）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '应用宝没有系统语音识别。可填下方百度语音 Key，或在 LLM 里用通义千问（非 DeepSeek）并关闭演示模式。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _baiduAsrApiKey,
                    obscureText: _obscureAsr,
                    decoration: InputDecoration(
                      labelText: '百度语音 API Key',
                      hintText: '控制台 → 语音技术 → 应用列表',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureAsr = !_obscureAsr),
                        icon: Icon(
                          _obscureAsr
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baiduAsrSecret,
                    obscureText: _obscureAsr,
                    decoration: const InputDecoration(
                      labelText: '百度语音 Secret Key',
                      hintText: '与上面 API Key 成对',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('目标平台', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in const [
                        ('douyin', '抖音'),
                        ('kuaishou', '快手'),
                        ('other', '其他'),
                      ])
                        ChoiceChip(
                          label: Text(p.$2),
                          selected: _platform == p.$1,
                          onSelected: (_) => setState(() => _platform = p.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _saveDh(state),
                          child: const Text('保存引擎配置'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pinging ? null : () => _pingEngine(state),
                          child: _pinging
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('检测引擎'),
                        ),
                      ),
                    ],
                  ),
                  if (_pingMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(_pingMessage!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Panel(
              title: 'LLM 大模型',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '应用宝语音请选「通义千问」：关闭演示模式，填阿里云百炼 API Key。DeepSeek 不能转语音。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('演示模式'),
                    subtitle: const Text('开启后不走真实 LLM / 不通义语音识别'),
                    value: _demoMode,
                    activeThumbColor: AppColors.textPrimary,
                    activeTrackColor: AppColors.brand,
                    onChanged: (v) => setState(() => _demoMode = v),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: LlmService.presets.map((p) {
                      return ChoiceChip(
                        label: Text(p.name),
                        selected: _providerId == p.id,
                        onSelected: (_) => _applyPreset(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKey,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: _providerId == 'dashscope'
                          ? '通义千问 API Key（阿里云百炼 sk-）'
                          : 'API Key',
                      hintText: _providerId == 'dashscope'
                          ? 'https://bailian.console.aliyun.com'
                          : null,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(labelText: 'Base URL'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _saveLlm(state),
                          child: const Text('保存 LLM'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _testing ? null : () => _testLlm(state),
                          child: Text(_testing ? '测试中' : '测试联调'),
                        ),
                      ),
                    ],
                  ),
                  if (_testMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(_testMessage!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
