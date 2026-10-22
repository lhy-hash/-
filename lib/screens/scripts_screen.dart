import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/live_script.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  LiveScriptCategory? filter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = filter == null
        ? state.scripts
        : state.scripts.where((e) => e.category == filter).toList();

    return GradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SectionHeader(
                title: '脚本库',
                subtitle: 'LLM 生成 + 合规扫描',
                action: FilledButton.tonalIcon(
                  onPressed: state.generating
                      ? null
                      : () => _openGenerateSheet(context),
                  icon: state.generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(state.generating ? '生成中' : 'AI 生成'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: filter == null,
                    onSelected: () => setState(() => filter = null),
                  ),
                  ...LiveScriptCategory.values.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _FilterChip(
                        label: switch (c) {
                          LiveScriptCategory.localLife => '本地生活',
                          LiveScriptCategory.ecommerce => '电商',
                          LiveScriptCategory.knowledge => '知识',
                        },
                        selected: filter == c,
                        onSelected: () => setState(() => filter = c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final script = list[index];
                  return _ScriptCard(
                    script: script,
                    onOpen: () => _openDetail(context, script),
                    onDelete: () => state.deleteScript(script.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGenerateSheet(BuildContext context) async {
    final industryCtrl = TextEditingController(text: '本地餐饮');
    final productCtrl = TextEditingController(text: '午市双人套餐');
    final pointsCtrl = TextEditingController(text: '性价比高、出餐快、适合办公午休');
    var minutes = 15;
    var category = LiveScriptCategory.localLife;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('AI 生成直播话术', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextField(
                      controller: industryCtrl,
                      decoration: const InputDecoration(labelText: '行业'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: productCtrl,
                      decoration: const InputDecoration(labelText: '商品/套餐'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointsCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '卖点'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LiveScriptCategory>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: '类目'),
                      items: LiveScriptCategory.values
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(e == LiveScriptCategory.localLife
                                  ? '本地生活'
                                  : e == LiveScriptCategory.ecommerce
                                      ? '电商带货'
                                      : '知识口播'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setModal(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    Text('时长：$minutes 分钟'),
                    Slider(
                      value: minutes.toDouble(),
                      min: 5,
                      max: 45,
                      divisions: 8,
                      label: '$minutes',
                      onChanged: (v) => setModal(() => minutes = v.round()),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await context.read<AppState>().generateAndAddScript(
                              industry: industryCtrl.text.trim(),
                              product: productCtrl.text.trim(),
                              sellingPoints: pointsCtrl.text.trim(),
                              minutes: minutes,
                              category: category,
                            );
                        if (context.mounted) {
                          final err = context.read<AppState>().lastError;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err ?? '话术已生成并入库'),
                            ),
                          );
                        }
                      },
                      child: const Text('开始生成'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context, LiveScript script) {
    final hits = context.read<AppState>().scanScript(script.content);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                Text(script.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${script.categoryLabel} · ${script.durationMinutes} 分钟',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (hits.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text('合规告警：${hits.join("、")}'),
                  ),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  script.content,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({
    required this.script,
    required this.onOpen,
    required this.onDelete,
  });

  final LiveScript script;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgPanel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      script.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              Text(
                '${script.categoryLabel} · ${script.durationMinutes} 分钟',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(
                script.content.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: script.tags
                    .map(
                      (t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(t, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
