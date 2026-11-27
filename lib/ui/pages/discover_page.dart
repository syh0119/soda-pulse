import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searchingOnline = false;
  List<Track> _onlineResults = const <Track>[];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _triggerOnlineSearch() async {
    final q = _query.trim();
    if (q.isEmpty || _searchingOnline) return;
    widget.store.addSearchQuery(q);
    setState(() => _searchingOnline = true);
    try {
      final res = await widget.store.searchOnlineTracks(q);
      if (mounted) {
        setState(() => _onlineResults = res);
      }
    } finally {
      if (mounted) {
        setState(() => _searchingOnline = false);
      }
    }
  }

  String _recommendModeLabel(dynamic mode) {
    final raw = mode.toString();
    if (raw.contains('familiar') || raw.contains('熟悉')) {
      return '熟悉模式';
    }
    if (raw.contains('fresh') || raw.contains('新鲜')) {
      return '新鲜模式';
    }
    return '默认模式';
  }

  Map<String, List<Track>> _groupAlbums(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final track in tracks) {
      final albumName = track.album.trim().isEmpty ? '未知专辑' : track.album;
      map.putIfAbsent(albumName, () => <Track>[]).add(track);
    }
    return map;
  }

  void _playTracks(List<Track> tracks, {int initialIndex = 0}) {
    if (tracks.isEmpty) return;
    widget.store.playQueue(tracks, initialIndex: initialIndex);
    widget.onOpenPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final trimmed = _query.trim().toLowerCase();
        final library = widget.store.library;
        final recentSearches = widget.store.recentSearches;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + 12,
                  16,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFrostedSearchBar(colorScheme),
                    if (recentSearches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '最近搜索',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: widget.store.clearSearchHistory,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(
                              '清空',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: recentSearches.map((term) {
                          return ActionChip(
                            label: Text(term),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.85),
                            ),
                            backgroundColor:
                                colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                            side: BorderSide(
                              color: colorScheme.outline.withValues(alpha: 0.15),
                            ),
                            onPressed: () {
                              _searchController.text = term;
                              _searchController.selection = TextSelection.fromPosition(
                                TextPosition(offset: term.length),
                              );
                              setState(() {
                                _query = term;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (trimmed.isNotEmpty)
              ..._buildSearchResults(context, trimmed)
            else
              ..._buildDiscoverContent(context, library),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }

  Widget _buildFrostedSearchBar(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
            decoration: InputDecoration(
              hintText: '歌名 / 歌手 / 歌单',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.45),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchResults(BuildContext context, String query) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final matchedTracks = widget.store.searchLocalTracks(query);
    final hasEnabledPlugins = widget.store.plugins.any((p) => p.enabled);

    final matchedPlaylists = widget.store.playlists.where((playlist) {
      return playlist.name.toLowerCase().contains(query);
    }).toList();

    return [
      if (hasEnabledPlugins)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _searchingOnline ? null : _triggerOnlineSearch,
                  icon: _searchingOnline
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(_searchingOnline ? '正在通过插件搜索...' : '用已启用插件全网搜索'),
                ),
                const SizedBox(width: 8),
                if (_onlineResults.isNotEmpty)
                  Text(
                    '找到 ${_onlineResults.length} 首',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (_onlineResults.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '插件在线搜索结果 (${_onlineResults.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = _onlineResults[index];
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.cloud_queue_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} · ${track.sourcePlatform ?? "插件音源"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.play_circle_filled_rounded),
                onTap: () => _playTracks(_onlineResults, initialIndex: index),
              );
            },
            childCount: _onlineResults.length,
          ),
        ),
      ],
      if (matchedTracks.isEmpty &&
          matchedPlaylists.isEmpty &&
          _onlineResults.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                hasEnabledPlugins
                    ? '本地未匹配，可点击上方按钮用已导入插件搜索'
                    : '未找到匹配的歌曲或歌单（支持繁简互搜）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
      if (matchedPlaylists.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '匹配歌单 (${matchedPlaylists.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final playlist = matchedPlaylists[index];
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                title: Text(playlist.name),
                subtitle: Text('${widget.store.tracksInPlaylist(playlist.id).length} 首歌曲'),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => _playTracks(widget.store.tracksInPlaylist(playlist.id)),
              );
            },
            childCount: matchedPlaylists.length,
          ),
        ),
      ],
      if (matchedTracks.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '匹配歌曲 (${matchedTracks.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = matchedTracks[index];
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: colorScheme.secondary,
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} · ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.play_circle_outline_rounded),
                onTap: () => _playTracks(matchedTracks, initialIndex: index),
              );
            },
            childCount: matchedTracks.length,
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildDiscoverContent(BuildContext context, List<Track> library) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeLabel = _recommendModeLabel(widget.store.recommendMode);
    final albums = _groupAlbums(library).entries.toList();

    final recentTracks = List<Track>.from(library);
    final freshTracks = List<Track>.from(library.reversed);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.92),
                  colorScheme.tertiary.withValues(alpha: 0.84),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        modeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '今日推荐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '根据你的本地听歌偏好实时生成专属队列',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        widget.store.setRecommendMode(widget.store.recommendMode);
                        widget.onOpenPlayer();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        '立即播放',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        showSmartRecommendSheet(context, widget.store);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('切换模式'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              widget.store.playDemo();
              widget.onOpenPlayer();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
                border: Border.all(
                  color: colorScheme.secondary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lyrics_rounded,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '一键演示 (ColorOS 17 逐字/灵动岛实测)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Text(
            '本地精选合集',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _CuratedCard(
                  title: '全部本地音乐',
                  subtitle: '${library.length} 首',
                  icon: Icons.library_music_rounded,
                  accent: colorScheme.primary,
                  onTap: () => _playTracks(library),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CuratedCard(
                  title: '最近常听',
                  subtitle: '${recentTracks.length} 首',
                  icon: Icons.history_rounded,
                  accent: colorScheme.secondary,
                  onTap: () => _playTracks(recentTracks),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CuratedCard(
                  title: '新鲜未听',
                  subtitle: '${freshTracks.length} 首',
                  icon: Icons.explore_rounded,
                  accent: colorScheme.tertiary,
                  onTap: () => _playTracks(freshTracks),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            '本地专辑',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      if (albums.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '暂无本地专辑',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        )
      else
        SliverToBoxAdapter(
          child: SizedBox(
            height: 176,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: albums.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = albums[index];
                final albumTracks = entry.value;
                final firstTrack = albumTracks.first;

                return GestureDetector(
                  onTap: () => _playTracks(albumTracks),
                  child: SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 132,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary.withValues(alpha: 0.25),
                                colorScheme.tertiary.withValues(alpha: 0.18),
                              ],
                            ),
                            border: Border.all(
                              color: colorScheme.onSurface.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Icon(
                                  Icons.album_rounded,
                                  size: 48,
                                  color: colorScheme.primary.withValues(alpha: 0.8),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface.withValues(alpha: 0.85),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${firstTrack.artist} · ${albumTracks.length}首',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ];
  }
}

class _CuratedCard extends StatelessWidget {
  const _CuratedCard({
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
          border: Border.all(
            color: accent.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
