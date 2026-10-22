import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/architecture_catalog.dart';
import '../models/content_factory.dart';
import '../models/live_script.dart';
import '../services/content_factory_service.dart';
import '../services/live_room_controller.dart';
import '../services/platform_bridge.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// 创作工坊：架构方案 + 短视频提示词 + 黄金三段式话术
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SectionHeader(
                title: '创作工坊',
                subtitle: '架构 · 短视频提示词 · 带货话术 全部落地',
              ),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabs,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.brand,
              tabs: const [
                Tab(text: '架构'),
                Tab(text: '短视频'),
                Tab(text: '话术'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _ArchitecturePane(),
                  _VideoPromptPane(),
                  _HostScriptPane(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchitecturePane extends StatefulWidget {
  const _ArchitecturePane();

  @override
  State<_ArchitecturePane> createState() => _ArchitecturePaneState();
}

class _ArchitecturePaneState extends State<_ArchitecturePane> {
  String _bridgeLog = PlatformBridge.instance.lastStatus;
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _Card(
          title: '核心技术栈',
          child: Column(
            children: [
              for (final row in ArchitectureCatalog.stackRows) ...[
                _StackTile(row: row),
                const Divider(height: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: '完整数据链路',
          child: SelectableText(
            ArchitectureCatalog.pipeline.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Consolas',
                  height: 1.45,
                  color: AppColors.textPrimary,
                ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Flutter Platform Channel',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in ArchitectureCatalog.flutterChannels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.type}  ${c.name}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          )),
                      Text(c.usage, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text('联调桩状态：$_bridgeLog',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _pushing
                          ? null
                          : () async {
                              setState(() => _pushing = true);
                              final r = await PlatformBridge.instance.startPush(
                                rtmpUrl: 'rtmp://live.example.com/xile/demo',
                                roomId: 'xile-room-001',
                              );
                              setState(() {
                                _pushing = false;
                                _bridgeLog = '${r['message'] ?? r}';
                              });
                            },
                      child: Text(_pushing ? '推流中…' : '模拟 startPush'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final r = await PlatformBridge.instance.stopPush();
                        setState(() => _bridgeLog = '${r['message'] ?? r}');
                      },
                      child: const Text('模拟 stopPush'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final r = await PlatformBridge.instance.sendSpeak(
                    text: '家人们好，我是喜乐 AI 数字人。',
                    motion: 'wave',
                  );
                  setState(() => _bridgeLog = '${r['message'] ?? r}');
                },
                child: const Text('模拟 AI speak 通道'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: '开发路径建议',
          child: Text(
            ArchitectureCatalog.pathAdvice.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: '7×24 高可用清单',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tip in ArchitectureCatalog.haTips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(color: AppColors.brand)),
                      Expanded(child: Text(tip)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StackTile extends StatelessWidget {
  const _StackTile({required this.row});
  final ArchitectureStackRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.layer, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('开源：${row.openSource}', style: Theme.of(context).textTheme.bodySmall),
        Text('商业：${row.commercial}', style: Theme.of(context).textTheme.bodySmall),
        Text('建议：${row.suggest}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _VideoPromptPane extends StatefulWidget {
  const _VideoPromptPane();

  @override
  State<_VideoPromptPane> createState() => _VideoPromptPaneState();
}

class _VideoPromptPaneState extends State<_VideoPromptPane> {
  final _subject = TextEditingController(
    text: '28岁干练女性，职业套装，气质亲和专业，AI数字人主播小乐',
  );
  final _script = TextEditingController(
    text: '还在为熬夜加班导致没时间好好吃饭发愁吗？试试喜乐午市双人套餐，到店扫码就能吃，出餐快，适合上班族。本场主播为人工智能技术生成的数字人。',
  );
  final _scene = TextEditingController(
    text: '简约明亮的现代直播间，背景有柔和的动态氛围灯',
  );
  final _dynamics = TextEditingController(
    text: '口型100%同步，面部自然微笑和眨眼，手部有指向屏幕侧方商品的动作',
  );
  final _camera = TextEditingController(text: '中景，缓慢向前推镜，全程稳定无抖动');
  final _constraints = TextEditingController(
    text: '4K超清，60帧，面部五官清晰不扭曲，动作流畅无卡顿，真人质感；必须保留AI数字人标识',
  );

  String? _output;
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _script.dispose();
    _scene.dispose();
    _dynamics.dispose();
    _camera.dispose();
    _constraints.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final app = context.read<AppState>();
    final factory = ContentFactoryService(app.llm);
    setState(() => _busy = true);
    try {
      final out = await factory.generateVideoPrompt(
        VideoPromptInput(
          subject: _subject.text.trim(),
          script: _script.text.trim(),
          scene: _scene.text.trim(),
          dynamics: _dynamics.text.trim(),
          camera: _camera.text.trim(),
          constraints: _constraints.text.trim(),
        ),
      );
      setState(() => _output = out);
    } catch (e) {
      setState(() => _output = '生成失败：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Text('万能公式：主体 + 台词 + 动态 + 场景 + 镜头 + 约束'),
        const SizedBox(height: 12),
        _field('主体设定', _subject),
        _field('口播台词', _script, maxLines: 4),
        _field('面部与肢体动态', _dynamics, maxLines: 2),
        _field('场景与光影', _scene, maxLines: 2),
        _field('镜头运动', _camera),
        _field('画质与约束', _constraints, maxLines: 2),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.movie_filter_outlined),
          label: Text(_busy ? '生成中…' : '生成短视频提示词'),
        ),
        if (_output != null) ...[
          const SizedBox(height: 12),
          _Card(
            title: '输出结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(_output!),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _output!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制提示词')),
                            );
                          }
                        },
                        child: const Text('复制'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          context.read<AppState>().addGeneratedContent(
                                title:
                                    '短视频提示词 · ${_short(_subject.text.trim(), 12)}',
                                content: _output!,
                                category: LiveScriptCategory.ecommerce,
                                tags: const ['短视频', '提示词'],
                                durationMinutes: 1,
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已保存到脚本库')),
                          );
                        },
                        child: const Text('存入脚本库'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  String _short(String s, int n) => s.length <= n ? s : s.substring(0, n);
}

class _HostScriptPane extends StatefulWidget {
  const _HostScriptPane();

  @override
  State<_HostScriptPane> createState() => _HostScriptPaneState();
}

class _HostScriptPaneState extends State<_HostScriptPane> {
  final _name = TextEditingController(text: '小美');
  final _personality = TextEditingController(text: '热情、真诚、语速轻快');
  final _product = TextEditingController(text: '便携式榨汁杯');
  final _price = TextEditingController(text: '59元');
  final _points = TextEditingController(text: '一键清洗、便携、适合上班族');
  final _audience = TextEditingController(text: '20-30岁上班族，追求健康但怕麻烦');

  HostScriptResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _personality.dispose();
    _product.dispose();
    _price.dispose();
    _points.dispose();
    _audience.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final app = context.read<AppState>();
    final factory = ContentFactoryService(app.llm);
    setState(() => _busy = true);
    try {
      final out = await factory.generateHostScript(
        HostScriptInput(
          hostName: _name.text.trim(),
          personality: _personality.text.trim(),
          product: _product.text.trim(),
          price: _price.text.trim(),
          sellingPoints: _points.text.trim(),
          audience: _audience.text.trim(),
        ),
      );
      setState(() => _result = out);
    } catch (e) {
      setState(() {
        _result = HostScriptResult(
          fullScript: '生成失败：$e',
          danmakuReplies: const [],
          source: 'error',
        );
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Text('黄金三段式：3秒痛点 + 15秒卖点 + 5秒逼单；含弹幕自动回复'),
        const SizedBox(height: 12),
        _field('主播名', _name),
        _field('性格', _personality),
        _field('产品', _product),
        _field('售价', _price),
        _field('卖点', _points, maxLines: 2),
        _field('目标人群', _audience, maxLines: 2),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.record_voice_over_outlined),
          label: Text(_busy ? '生成中…' : '生成带货话术'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          _Card(
            title: '完整脚本（${_result!.source}）',
            child: SelectableText(_result!.fullScript),
          ),
          const SizedBox(height: 12),
          _Card(
            title: '弹幕高情商回复',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _result!.danmakuReplies) ...[
                  Text('Q: ${r.question}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      )),
                  Text('A: ${r.answer}'),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final buf = StringBuffer(_result!.fullScript)
                      ..writeln()
                      ..writeln('【弹幕回复】');
                    for (final r in _result!.danmakuReplies) {
                      buf.writeln('${r.question}：${r.answer}');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制话术+弹幕回复')),
                      );
                    }
                  },
                  child: const Text('复制全部'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final buf = StringBuffer(_result!.fullScript)
                      ..writeln()
                      ..writeln('【弹幕回复】');
                    for (final r in _result!.danmakuReplies) {
                      buf.writeln('${r.question}：${r.answer}');
                    }
                    context.read<AppState>().addGeneratedContent(
                          title: '${_name.text} · ${_product.text} 黄金三段式',
                          content: buf.toString(),
                          category: LiveScriptCategory.ecommerce,
                          tags: const ['黄金三段式', '弹幕回复', '带货'],
                          durationMinutes: 1,
                        );
                    context.read<LiveRoomController>().applyHostPack(
                          product: _product.text.trim(),
                          price: _price.text.trim(),
                          sellingPoints: _points.text.trim(),
                          hostName: _name.text.trim(),
                          replies: _result!.danmakuReplies,
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已保存到脚本库，并同步直播间话术包')),
                    );
                  },
                  child: const Text('存入脚本库'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _result == null
                ? null
                : () async {
                    await PlatformBridge.instance.sendSpeak(
                      text: _result!.fullScript
                          .replaceAll(RegExp(r'（[^）]*）'), ' ')
                          .split('\n')
                          .where((e) => e.contains('「') || e.contains('」') || e.trim().startsWith('「'))
                          .take(2)
                          .join(' '),
                      motion: 'point',
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已通过 Platform Channel 试读首段')),
                    );
                  },
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('试读首段（Platform Channel）'),
          ),
        ],
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
