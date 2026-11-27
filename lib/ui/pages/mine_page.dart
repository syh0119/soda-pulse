import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/ui/pages/sub_pages.dart';

import 'package:soda_pulse/ui/pages/island_settings_page.dart';

import 'package:soda_pulse/ui/sheets/player_sheets.dart';

class MinePage extends StatelessWidget {
  const MinePage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  static const Color _accentGreen = Color(0xFF2FE08B);
  static const Color _bgTop = Color(0xFF10281E);
  static const Color _bgBottom = Color(0xFF0A0D0E);

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  void _handleBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    } else {
      onOpenPlayer();
    }
  }

  int _computeTotalMinutes() {
    if (store.history.isEmpty) return 0;
    return store.history.length * 3;
  }

  Future<void> _showBackupSheet(BuildContext context) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14191B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '备份与还原',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '导出当前歌单、收藏与播放历史为 JSON，或粘贴 JSON 恢复数据。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.56),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: const Color(0xFF0A140F),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final jsonStr = await store.exportBackupToFile() ?? '';
                    controller.text = jsonStr;
                    await Clipboard.setData(ClipboardData(text: jsonStr));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已导出备份 JSON 并复制到剪贴板')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text(
                    '导出 JSON 并复制',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 5,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '在此粘贴备份 JSON 内容...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0E1214),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accentGreen),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1F2B26),
                        foregroundColor: _accentGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        final raw = controller.text.trim();
                        if (raw.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先粘贴有效的备份 JSON')),
                          );
                          return;
                        }
                        try {
                          jsonDecode(raw);
                          store.importBackupJson(raw);
                          Navigator.of(sheetContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('备份恢复成功')),
                          );
                        } catch (_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('JSON 格式无效，请检查后重试')),
                          );
                        }
                      },
                      child: const Text(
                        '导入并恢复',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
            stops: [0.0, 0.36],
          ),
        ),
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final totalMinutes = _computeTotalMinutes();
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => _handleBack(context),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            tooltip: '返回',
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '我的',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildProfileStatsCard(context, totalMinutes),
                      const SizedBox(height: 14),
                      _buildPlaylistsCard(context),
                      const SizedBox(height: 14),
                      _buildToolsCard(context),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileStatsCard(BuildContext context, int totalMinutes) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12231B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _accentGreen.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2420),
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentGreen, width: 2),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: _accentGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SodaPulse 本地曲库',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '已收录 ${store.library.length} 首 · 累计听歌 $totalMinutes 分钟',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _pushPage(context, ListenRankPage(store: store, onOpenPlayer: onOpenPlayer)),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.10),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _StatColumn(
                    value: '${store.favoriteTracks.length}',
                    label: '我喜欢',
                    onTap: () => _pushPage(
                      context,
                      FavoriteTracksPage(store: store, onOpenPlayer: onOpenPlayer),
                    ),
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    value: '${store.library.length}',
                    label: '本地曲库',
                    onTap: () => _pushPage(
                      context,
                      LocalMusicPage(store: store, onOpenPlayer: onOpenPlayer),
                    ),
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    value: '${store.playlists.length}',
                    label: '本机歌单',
                    onTap: () => _pushPage(
                      context,
                      MyPlaylistsPage(store: store, onOpenPlayer: onOpenPlayer),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsCard(BuildContext context) {
    final previewPlaylists = store.playlists.take(3).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14191B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '我的本机歌单',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${store.playlists.length} 个',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.48),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _pushPage(context, MyPlaylistsPage(store: store, onOpenPlayer: onOpenPlayer)),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '全部',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.78),
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (previewPlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: Colors.white.withValues(alpha: 0.28),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '创建或导入歌单后，这里显示全部本地收藏歌单',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: previewPlaylists.map((playlist) {
                return InkWell(
                  onTap: () => _pushPage(context, MyPlaylistsPage(store: store, onOpenPlayer: onOpenPlayer)),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B2420),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: const Icon(
                            Icons.library_music_rounded,
                            color: _accentGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${playlist.trackIds.length} 首歌曲',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.36),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildToolsCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131719),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '常用',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ToolRow(
            icon: Icons.favorite_rounded,
            badgeBg: const Color(0xFF331B22),
            badgeFg: const Color(0xFFFF5A7E),
            title: '我喜欢的音乐',
            trailingText: '${store.favoriteTracks.length} 首',
            onTap: () => _pushPage(context, FavoriteTracksPage(store: store, onOpenPlayer: onOpenPlayer)),
          ),
          _ToolRow(
            icon: Icons.queue_music_rounded,
            badgeBg: const Color(0xFF1A2538),
            badgeFg: const Color(0xFF5B9BFF),
            title: '本机歌单',
            trailingText: '${store.playlists.length} 个',
            onTap: () => _pushPage(context, MyPlaylistsPage(store: store, onOpenPlayer: onOpenPlayer)),
          ),
          _ToolRow(
            icon: Icons.history_rounded,
            badgeBg: const Color(0xFF172B27),
            badgeFg: const Color(0xFF2FE08B),
            title: '播放历史',
            trailingText: '${store.history.length} 条',
            onTap: () => _pushPage(context, HistoryPage(store: store, onOpenPlayer: onOpenPlayer)),
          ),
          _ToolRow(
            icon: Icons.graphic_eq_rounded,
            badgeBg: const Color(0xFF302618),
            badgeFg: const Color(0xFFF5B74F),
            title: '音质与音效',
            trailingText: SoundFxPresets.all.firstWhere((p) => p.id == store.eqPresetId, orElse: () => SoundFxPresets.all.first).name,
            onTap: () => showSoundEffectSheet(context, store),
          ),
          _ToolRow(
            icon: Icons.extension_rounded,
            badgeBg: const Color(0xFF251D36),
            badgeFg: const Color(0xFFA78BFA),
            title: '音源插件',
            trailingText: '${store.plugins.length} 个已导入',
            onTap: () => _pushPage(context, PluginManagerPage(store: store)),
          ),
          _ToolRow(
            icon: Icons.auto_awesome_rounded,
            badgeBg: const Color(0xFF162C22),
            badgeFg: const Color(0xFF2FE08B),
            title: '刷新今日推荐',
            trailingText: '只换待播，不打断播放',
            onTap: () {
              store.refreshRecommendQueue();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已刷新今日推荐待播队列')),
              );
            },
          ),
          _ToolRow(
            icon: Icons.subtitles_rounded,
            badgeBg: const Color(0xFF162832),
            badgeFg: const Color(0xFF38BDF8),
            title: '灵动岛 & 逐字歌词',
            trailingText: 'ColorOS 17',
            onTap: () => _pushPage(
              context,
              IslandSettingsPage(bridge: store.bridge),
            ),
          ),
          _ToolRow(
            icon: Icons.directions_car_rounded,
            badgeBg: const Color(0xFF1E2238),
            badgeFg: const Color(0xFF818CF8),
            title: '驾驶模式',
            trailingText: '车机横屏',
            onTap: () => _pushPage(context, DrivePage(store: store)),
          ),
          _ToolRow(
            icon: Icons.palette_rounded,
            badgeBg: const Color(0xFF182B24),
            badgeFg: const Color(0xFF34D399),
            title: '皮肤与布局',
            trailingText: '播放器外观',
            onTap: () => showSkinAndLayoutSheet(context, store),
          ),
          _ToolRow(
            icon: Icons.backup_rounded,
            badgeBg: const Color(0xFF20252A),
            badgeFg: const Color(0xFFCBD5E1),
            title: '备份与还原',
            trailingText: 'JSON 导出/导入',
            onTap: () => _showBackupSheet(context),
          ),
          Divider(
            height: 20,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '播放页底栏样式',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SegmentedButton<BottomBarStyle>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return _accentGreen.withValues(alpha: 0.22);
                      }
                      return const Color(0xFF1A2023);
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return _accentGreen;
                      }
                      return Colors.white70;
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                  ),
                  segments: const [
                    ButtonSegment<BottomBarStyle>(
                      value: BottomBarStyle.native,
                      label: Text('原生', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<BottomBarStyle>(
                      value: BottomBarStyle.glass,
                      label: Text('玻璃', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {store.bottomBarStyle},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      store.setBottomBarStyle(selection.first);
                    }
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              '启动时自动续播上次歌曲',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeThumbColor: _accentGreen,
            activeTrackColor: _accentGreen.withValues(alpha: 0.35),
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            value: store.autoPlayOnLaunch,
            onChanged: store.setAutoPlayOnLaunch,
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.badgeBg,
    required this.badgeFg,
    required this.title,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final Color badgeBg;
  final Color badgeFg;
  final String title;
  final String trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: badgeFg, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                trailingText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.36),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
