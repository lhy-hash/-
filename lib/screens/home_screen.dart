import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final a = state.analytics;

    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '喜乐 · AI数字人',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.shopName,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                LiveBadge(live: state.isLive),
              ],
            ),
            const SizedBox(height: 24),
            _HeroPanel(state: state),
            const SizedBox(height: 20),
            SectionHeader(
              title: '本周概览',
              subtitle: '先看效果，再扩矩阵',
              action: TextButton(
                onPressed: () => state.setTab(3),
                child: const Text('详细数据'),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                StatTile(
                  label: '直播时长',
                  value: '${a.liveHours}h',
                  hint: '较上周 +12%',
                ),
                StatTile(
                  label: '平均在线',
                  value: '${a.avgViewers}',
                  hint: '午晚高峰更稳',
                ),
                StatTile(
                  label: '询单数',
                  value: '${a.inquiries}',
                  hint: '弹幕意图识别',
                ),
                StatTile(
                  label: 'AI 成本',
                  value: '¥${a.aiCostYuan.toStringAsFixed(0)}',
                  hint: '约 ¥${(a.aiCostYuan / a.liveHours).toStringAsFixed(1)}/时',
                  accent: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeader(
              title: '快捷动作',
              subtitle: '围绕开播闭环设计',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ActionChip(
                  icon: Icons.auto_awesome,
                  label: '生成话术',
                  onTap: () => state.setTab(1),
                ),
                _ActionChip(
                  icon: Icons.fact_check_outlined,
                  label: '开播检查',
                  onTap: () => state.setTab(2),
                ),
                _ActionChip(
                  icon: Icons.smart_toy_outlined,
                  label: '形象：${state.selectedAvatar.split(' · ').first}',
                  onTap: () => state.setTab(4),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('合规提醒', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '使用 AI 人物图像/视频从事直播电商，须依法显著标识并持续提示由人工智能技术生成。'
                    '未标识、虚假宣传、假冒他人均属红线。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A31), Color(0xFF12201C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天想开哪一场？',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '未勾选必选项与 AI 标识前，系统禁止开播。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => state.setTab(2),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(state.isLive ? '管理直播' : '去开播'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => state.setTab(1),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text('脚本库 ${state.scripts.length}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
