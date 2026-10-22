import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checklist_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class GoLiveScreen extends StatelessWidget {
  const GoLiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            SectionHeader(
              title: '开播检查',
              subtitle: '必选项未完成禁止开播',
              action: LiveBadge(live: state.isLive),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 生成持续标识', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '角标「AI数字人」+ 定时口播提示',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: state.aiLabelEnabled,
                    activeThumbColor: AppColors.textPrimary,
                    activeTrackColor: AppColors.brand,
                    onChanged: state.setAiLabel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...state.checklist.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ChecklistTile(
                    item: item,
                    onChanged: (v) => state.toggleChecklist(item.id, v),
                  ),
                )),
            const SizedBox(height: 12),
            if (!state.aiLabelEnabled)
              const _WarnBanner(text: '未开启 AI 标识，依法不得开播。'),
            if (state.aiLabelEnabled && !state.canGoLive)
              const _WarnBanner(text: '仍有必选项未勾选，请完成后再开播。'),
            if (state.canGoLive)
              const _OkBanner(text: '检查通过。开播后将持续展示 AI 标识并留存日志。'),
            const SizedBox(height: 16),
            if (!state.isLive)
              FilledButton.icon(
                onPressed: state.canGoLive
                    ? () {
                        state.startLive();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已进入直播中（演示模式，可对接推流 SDK）')),
                        );
                      }
                    : null,
                icon: const Icon(Icons.sensors),
                label: const Text('确认开播'),
              )
            else
              OutlinedButton.icon(
                onPressed: () {
                  state.stopLive();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已下播，日志已标记结束')),
                  );
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('一键停播'),
              ),
            const SizedBox(height: 20),
            if (state.isLive) const _LivePreviewMock(),
          ],
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({required this.item, required this.onChanged});

  final ChecklistItem item;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final required = item.kind == ChecklistKind.required;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.checked,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: AppColors.brand,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: required
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        required ? '必须' : '建议',
                        style: TextStyle(
                          fontSize: 11,
                          color: required ? AppColors.accent : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Text(text),
    );
  }
}

class _OkBanner extends StatelessWidget {
  const _OkBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Text(text),
    );
  }
}

class _LivePreviewMock extends StatelessWidget {
  const _LivePreviewMock();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 14,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E3D34), Color(0xFF0E1A16)],
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face_retouching_natural, size: 72, color: AppColors.brand),
                  const SizedBox(height: 12),
                  Text('数字人预览', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('可对接云厂商实时渲染 SDK', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.7)),
                ),
                child: const Text(
                  'AI数字人 · 人工智能生成',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
