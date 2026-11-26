import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/core/daily_copy.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/pages/sub_pages.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';

class MinePage extends StatelessWidget {
  const MinePage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final daily = DailyCopy.now();

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final topTrackName = store.history.isNotEmpty
            ? store.history.first.title
            : (store.library.isNotEmpty ? store.library.first.title : '暂无播放记录');
        final totalMinutes = store.totalListenSeconds ~/ 60;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                _buildDailyGreetingCard(context, colorScheme, daily),
                const SizedBox(height: 14),
                _buildListenRankCard(
                  context: context,
                  colorScheme: colorScheme,
                  totalTracks: store.library.length,
                  totalMinutes: totalMinutes,
                  topTrackName: topTrackName,
                ),
                const SizedBox(height: 14),
                _buildQuickGrid(context, colorScheme),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    '专业工具与扩展',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                _buildProToolsCard(context, colorScheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyGreetingCard(
    BuildContext context,
    ColorScheme colorScheme,
    DailyGreeting daily,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.22),
            colorScheme.secondary.withValues(alpha: 0.14),
          ],
        ),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bubble_chart_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                daily.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            daily.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListenRankCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required int totalTracks,
    required int totalMinutes,
    required String topTrackName,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _pushPage(
          context,
          ListenRankPage(store: store, onOpenPlayer: onOpenPlayer),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.leaderboard_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '气泡水听歌榜',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatMetric(
                      label: '曲库总计',
                      value: '$totalTracks 首',
                      colorScheme: colorScheme,
                    ),
                  ),
                  Expanded(
                    child: _StatMetric(
                      label: '累计听歌',
                      value: '$totalMinutes 分钟',
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '常听单曲：$topTrackName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickGrid(BuildContext context, ColorScheme colorScheme) {
    final items = [
      _QuickGridItem(
        title: '我喜欢',
        subtitle: '${store.favoriteTracks.length} 首',
        icon: Icons.favorite_rounded,
        accent: Colors.pinkAccent,
        onTap: () => _pushPage(
          context,
          FavoriteTracksPage(store: store, onOpenPlayer: onOpenPlayer),
        ),
      ),
      _QuickGridItem(
        title: '播放历史',
        subtitle: '${store.history.length} 条',
        icon: Icons.history_rounded,
        accent: colorScheme.primary,
        onTap: () => _pushPage(
          context,
          HistoryPage(store: store, onOpenPlayer: onOpenPlayer),
        ),
      ),
      _QuickGridItem(
        title: '本地音乐',
        subtitle: '${store.library.length} 首',
        icon: Icons.library_music_rounded,
        accent: colorScheme.tertiary,
        onTap: () => _pushPage(
          context,
          LocalMusicPage(store: store, onOpenPlayer: onOpenPlayer),
        ),
      ),
      _QuickGridItem(
        title: '我的歌单',
        subtitle: '${store.playlists.length} 个',
        icon: Icons.queue_music_rounded,
        accent: colorScheme.secondary,
        onTap: () => _pushPage(
          context,
          MyPlaylistsPage(store: store, onOpenPlayer: onOpenPlayer),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.65,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: item.onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, size: 20, color: item.accent),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProToolsCard(BuildContext context, ColorScheme colorScheme) {
    final tools = [
      _ToolEntry(
        icon: Icons.dynamic_feed_rounded,
        title: '灵动岛 & 逐字歌词中心',
        onTap: () => _pushPage(
          context,
          IslandSettingsPage(bridge: store.bridge),
        ),
      ),
      _ToolEntry(
        icon: Icons.equalizer_rounded,
        title: '音效均衡器 (5段 DSP)',
        onTap: () => showSoundEffectSheet(context, store),
      ),
      _ToolEntry(
        icon: Icons.extension_rounded,
        title: '音源插件管理 (LX / MusicFree)',
        onTap: () => _pushPage(context, PluginManagerPage(store: store)),
      ),
      _ToolEntry(
        icon: Icons.palette_rounded,
        title: '皮肤与播放布局',
        onTap: () => showSkinAndLayoutSheet(context, store),
      ),
      _ToolEntry(
        icon: Icons.directions_car_rounded,
        title: '车载 / 驾驶模式',
        onTap: () => _pushPage(context, DrivePage(store: store)),
      ),
      _ToolEntry(
        icon: Icons.settings_backup_restore_rounded,
        title: '备份与还原',
        onTap: () => _showBackupSheet(context),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(22) : Radius.zero,
                  bottom: i == tools.length - 1
                      ? const Radius.circular(22)
                      : Radius.zero,
                ),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  tools[i].icon,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              title: Text(
                tools[i].title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onTap: tools[i].onTap,
            ),
            if (i < tools.length - 1)
              Divider(
                height: 1,
                indent: 58,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
          ],
        ],
      ),
    );
  }

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _showBackupSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '备份与还原',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor:
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  leading: Icon(
                    Icons.file_upload_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('导出备份文件'),
                  subtitle: const Text('将歌单、收藏与设置导出为 JSON 文件'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await store.exportBackupToFile();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已导出备份文件')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor:
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  leading: Icon(
                    Icons.content_paste_go_rounded,
                    color: colorScheme.secondary,
                  ),
                  title: const Text('粘贴 JSON 还原'),
                  subtitle: const Text('从剪贴板或文本粘贴备份数据恢复'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showImportJsonDialog(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showImportJsonDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('粘贴 JSON 还原'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '在此粘贴备份 JSON 内容...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final raw = controller.text.trim();
                if (raw.isEmpty) return;
                Navigator.of(dialogContext).pop();
                await store.importBackupJson(raw);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('备份还原已完成')),
                  );
                }
              },
              child: const Text('确认还原'),
            ),
          ],
        );
      },
    );
  }
}

class _StatMetric extends StatelessWidget {
  const _StatMetric({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _QuickGridItem {
  const _QuickGridItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

class _ToolEntry {
  const _ToolEntry({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}
