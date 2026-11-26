import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/plugin/plugin_manager.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

class ListenRankPage extends StatelessWidget {
  const ListenRankPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌排行'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          final rankedTracks = store.topPlayedTracks;
          final hourlyCounts = List<int>.generate(
            24,
            (h) => store.hourlyCounts[h] ?? 0,
          );

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _HourlyDistributionCard(counts: hourlyCounts),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '播放次数排行',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (rankedTracks.isNotEmpty)
                        Text(
                          '共 ${rankedTracks.length} 首',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (rankedTracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyPlaceholder(
                    icon: Icons.bar_chart_rounded,
                    message: '暂无听歌排行数据',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: rankedTracks.length,
                  itemBuilder: (context, index) {
                    final track = rankedTracks[index];
                    final rank = index + 1;
                    final count = store.playCountFor(track.id);
                    return _RankedTrackTile(
                      rank: rank,
                      track: track,
                      playCount: count,
                      isPlaying: store.currentTrack?.id == track.id,
                      onTap: () {
                        store.playTrack(track, queue: rankedTracks);
                        onOpenPlayer();
                      },
                      onMore: () => showTrackOptionsSheet(
                        context,
                        store,
                        track,
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _HourlyDistributionCard extends StatelessWidget {
  const _HourlyDistributionCard({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final normalized = List<int>.generate(
      24,
      (index) => index < counts.length ? counts[index] : 0,
    );
    final maxCount = normalized.fold<int>(0, math.max);
    final totalCount = normalized.fold<int>(0, (sum, value) => sum + value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '24小时听歌分布',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '累计 $totalCount 次',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                final count = normalized[hour];
                final ratio = maxCount > 0 ? count / maxCount : 0.0;
                final barHeight = maxCount > 0
                    ? math.max(6.0, ratio * 84.0)
                    : 6.0;
                final isPeak = maxCount > 0 && count == maxCount;

                return Expanded(
                  child: Tooltip(
                    message: '${hour.toString().padLeft(2, '0')}:00 · $count 次',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: isPeak
                                  ? colors.primary
                                  : colors.primary.withValues(
                                      alpha: count > 0 ? 0.55 : 0.16,
                                    ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hour % 6 == 0 || hour == 23 ? '$hour' : '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: colors.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankedTrackTile extends StatelessWidget {
  const _RankedTrackTile({
    required this.rank,
    required this.track,
    required this.playCount,
    required this.isPlaying,
    required this.onTap,
    required this.onMore,
  });

  final int rank;
  final Track track;
  final int playCount;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMore;

  Color _badgeColor(ColorScheme colors) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFB300);
      case 2:
        return const Color(0xFF90A4AE);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return colors.onSurface.withValues(alpha: 0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isTopThree = rank <= 3;

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isTopThree
              ? _badgeColor(colors).withValues(alpha: 0.18)
              : colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: isTopThree
              ? Border.all(color: _badgeColor(colors).withValues(alpha: 0.7))
              : null,
        ),
        child: Text(
          '#$rank',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: isTopThree
                ? _badgeColor(colors)
                : colors.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
          color: isPlaying ? colors.primary : null,
        ),
      ),
      subtitle: Text(
        '${track.artist} · ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$playCount 次',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('最近播放'),
        actions: [
          ListenableBuilder(
            listenable: store,
            builder: (context, child) {
              if (store.history.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton.icon(
                onPressed: () => store.clearHistory(),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清空记录'),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          final history = store.history;
          if (history.isEmpty) {
            return const _EmptyPlaceholder(
              icon: Icons.history_rounded,
              message: '暂无播放历史记录',
            );
          }

          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              final track = store.library.firstWhere(
                (t) => t.id == entry.trackId,
                orElse: () => Track(
                  id: entry.trackId,
                  title: entry.title,
                  artist: entry.artist,
                  album: '最近播放',
                  durationMs: 0,
                  uri: '',
                ),
              );
              return _StandardTrackTile(
                track: track,
                isPlaying: store.currentTrack?.id == track.id,
                onTap: () {
                  store.playTrack(track);
                  onOpenPlayer();
                },
                onMore: () => showTrackOptionsSheet(
                  context,
                  store,
                  track,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FavoriteTracksPage extends StatelessWidget {
  const FavoriteTracksPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我喜欢的音乐'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          final favorites = store.favoriteTracks;
          if (favorites.isEmpty) {
            return const _EmptyPlaceholder(
              icon: Icons.favorite_border_rounded,
              message: '还没有收藏的歌曲',
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        store.playTrack(favorites.first, queue: favorites);
                        onOpenPlayer();
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${favorites.length} 首歌曲',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final track = favorites[index];
                    return _StandardTrackTile(
                      track: track,
                      isPlaying: store.currentTrack?.id == track.id,
                      onTap: () {
                        store.playTrack(track, queue: favorites);
                        onOpenPlayer();
                      },
                      onMore: () => showTrackOptionsSheet(
                        context,
                        store,
                        track,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends State<LocalMusicPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _scanning = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRescan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await widget.store.rescanLibrary();
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          TextButton.icon(
            onPressed: _scanning ? null : _handleRescan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重新扫描'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, child) {
          final allTracks = widget.store.library;
          final lowerQuery = _query.trim().toLowerCase();
          final filtered = lowerQuery.isEmpty
              ? allTracks
              : allTracks.where((track) {
                  return track.title.toLowerCase().contains(lowerQuery) ||
                      track.artist.toLowerCase().contains(lowerQuery) ||
                      track.album.toLowerCase().contains(lowerQuery);
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索本地歌曲、歌手或专辑',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyPlaceholder(
                        icon: Icons.library_music_outlined,
                        message: allTracks.isEmpty
                            ? '暂无本地音乐，点击右上角重新扫描'
                            : '未找到匹配的本地歌曲',
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final track = filtered[index];
                          return _StandardTrackTile(
                            track: track,
                            isPlaying: widget.store.currentTrack?.id == track.id,
                            onTap: () {
                              widget.store.playTrack(track, queue: filtered);
                              widget.onOpenPlayer();
                            },
                            onMore: () => showTrackOptionsSheet(
                              context,
                              widget.store,
                              track,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MyPlaylistsPage extends StatelessWidget {
  const MyPlaylistsPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入歌单名称',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      store.createPlaylist(name);
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    String playlistId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入新的歌单名称',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      store.renamePlaylist(playlistId, newName);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String playlistId,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除歌单'),
          content: Text('确定要删除歌单“$name”吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      store.deletePlaylist(playlistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的歌单'),
        actions: [
          IconButton(
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建歌单',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          final playlists = store.playlists;
          if (playlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _EmptyPlaceholder(
                    icon: Icons.queue_music_rounded,
                    message: '还没有自建歌单',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showCreateDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建歌单'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final tracks = store.tracksInPlaylist(playlist.id);

              return ListTile(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => PlaylistDetailPage(
                        store: store,
                        playlistId: playlist.id,
                        onOpenPlayer: onOpenPlayer,
                      ),
                    ),
                  );
                },
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: colors.primary,
                  ),
                ),
                title: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${tracks.length} 首歌曲'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      _showRenameDialog(context, playlist.id, playlist.name);
                    } else if (value == 'delete') {
                      _confirmDelete(context, playlist.id, playlist.name);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('重命名'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除歌单'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({
    super.key,
    required this.store,
    required this.playlistId,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final String playlistId;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, child) {
        final playlist = store.playlistById(playlistId);
        if (playlist == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('歌单详情')),
            body: const _EmptyPlaceholder(
              icon: Icons.queue_music_rounded,
              message: '歌单不存在或已被删除',
            ),
          );
        }

        final tracks = store.tracksInPlaylist(playlistId);

        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name),
          ),
          body: tracks.isEmpty
              ? const _EmptyPlaceholder(
                  icon: Icons.music_note_rounded,
                  message: '歌单里还没有歌曲',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              store.playTrack(tracks.first, queue: tracks);
                              onOpenPlayer();
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('播放全部'),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${tracks.length} 首歌曲',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.65),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return _StandardTrackTile(
                            track: track,
                            isPlaying: store.currentTrack?.id == track.id,
                            onTap: () {
                              store.playTrack(track, queue: tracks);
                              onOpenPlayer();
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: '从歌单移除',
                              onPressed: () {
                                store.removeTrackFromPlaylist(
                                  playlistId,
                                  track.id,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class PluginManagerPage extends StatelessWidget {
  const PluginManagerPage({
    super.key,
    required this.store,
  });

  final AppStore store;

  Future<void> _showUrlImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('从链接导入插件'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://example.com/plugin.js',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (url != null && url.isNotEmpty) {
      await store.importPluginFromUrl(url);
    }
  }

  Future<void> _showTextImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final script = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴插件脚本'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              maxLines: 10,
              minLines: 6,
              decoration: const InputDecoration(
                hintText: '粘贴 LX Music 或 MusicFree 插件 JS 代码',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (script != null && script.isNotEmpty) {
      await store.importPluginFromText(script);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音源插件管理'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          final plugins = store.plugins;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => store.importPluginFromFile(),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('本地 .js 文件'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showUrlImportDialog(context),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('从链接导入'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showTextImportDialog(context),
                      icon: const Icon(Icons.code_rounded, size: 18),
                      label: const Text('粘贴脚本'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: plugins.isEmpty
                    ? const _EmptyPlaceholder(
                        icon: Icons.extension_off_rounded,
                        message: '暂无已安装插件，点击上方按钮导入',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: plugins.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final plugin = plugins[index];
                          final isLx = plugin.type == PluginType.lx;
                          final badgeColor =
                              isLx ? SodaTheme.accent : colors.secondary;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest
                                  .withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colors.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withValues(
                                                alpha: 0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isLx ? 'LX' : 'MusicFree',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: badgeColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              plugin.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '作者: ${plugin.author} · 版本: ${plugin.version}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      if (plugin.platforms.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: plugin.platforms
                                              .map(
                                                (platform) => Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: colors.surface
                                                        .withValues(alpha: 0.7),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      999,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    platform,
                                                    style: theme
                                                        .textTheme.labelSmall,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: plugin.enabled,
                                      activeThumbColor: colors.primary,
                                      onChanged: (enabled) =>
                                          store.setPluginEnabled(
                                        plugin.id,
                                        enabled,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: colors.error,
                                      ),
                                      tooltip: '删除插件',
                                      onPressed: () =>
                                          store.removePlugin(plugin.id),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StandardTrackTile extends StatelessWidget {
  const _StandardTrackTile({
    required this.track,
    required this.isPlaying,
    required this.onTap,
    this.onMore,
    this.trailing,
  });

  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isPlaying
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
          color: isPlaying
              ? colors.primary
              : colors.onSurface.withValues(alpha: 0.65),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
          color: isPlaying ? colors.primary : null,
        ),
      ),
      subtitle: Text(
        '${track.artist} · ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          (onMore != null
              ? IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onPressed: onMore,
                )
              : null),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: colors.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
