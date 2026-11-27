import 'package:soda_pulse/models/track.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.store,
    required this.onOpenPlayer,
    this.openSearchOnStart = false,
  });

  final AppStore store;
  final VoidCallback onOpenPlayer;
  final bool openSearchOnStart;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  static const Color _bgTop = Color(0xFF10281E);
  static const Color _bgBottom = Color(0xFF0A0D0E);
  static const Color _emerald = Color(0xFF2FE08B);
  static const Color _emeraldBox = Color(0xFF123626);
  static const Color _cardSurface = Color(0xFF151A1C);

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  late bool _searchOpen;
  String _query = '';
  bool _isSearchingOnline = false;
  List<Track> _onlineResults = const <Track>[];

  @override
  void initState() {
    super.initState();
    _searchOpen = widget.openSearchOnStart;
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    if (widget.openSearchOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      if (_searchOpen || _query.isNotEmpty) {
        _searchOpen = false;
        _query = '';
        _searchController.clear();
        _searchFocusNode.unfocus();
      } else {
        _searchOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _searchFocusNode.requestFocus();
          }
        });
      }
    });
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
    });
  }

  Future<void> _submitSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      _isSearchingOnline = true;
    });
    _searchFocusNode.unfocus();
    try {
      final res = await widget.store.searchOnlineTracks(q);
      if (mounted) setState(() => _onlineResults = res);
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingOnline = false;
        });
      }
    }
  }

  void _applyRecentSearch(String term) {
    _searchController.text = term;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: term.length),
    );
    _submitSearch(term);
  }

  void _handleBack() {
    Navigator.maybePop(context).then((popped) {
      if (!popped && mounted) {
        widget.onOpenPlayer();
      }
    });
  }

  void _playTrackList(List<dynamic> tracks, {int index = 0}) {
    if (tracks.isEmpty) {
      widget.store.playDemo();
      widget.onOpenPlayer();
      return;
    }
    widget.store.playQueue(tracks.cast(), initialIndex: index);
    widget.onOpenPlayer();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final showSearchPanel =
            _searchOpen || widget.openSearchOnStart || _query.isNotEmpty;

        return Scaffold(
          backgroundColor: _bgBottom,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bgTop, _bgBottom],
                stops: [0.0, 0.34],
              ),
            ),
            child: Column(
              children: [
                _buildTopHeader(showSearchPanel),
                if (showSearchPanel) _buildFrostedSearchBar(),
                Expanded(
                  child: _query.isNotEmpty
                      ? _buildSearchResults()
                      : _buildDiscoverFeed(showSearchPanel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(bool showSearchPanel) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            _CircleGlassButton(
              icon: Icons.chevron_left_rounded,
              onTap: _handleBack,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '发现',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '编辑部 · 每天换一批',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _CircleGlassButton(
              icon: showSearchPanel
                  ? Icons.close_rounded
                  : Icons.search_rounded,
              onTap: _toggleSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onQueryChanged,
                    onSubmitted: _submitSearch,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: _emerald,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '搜索本地曲库、简繁歌词或在线曲库...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onQueryChanged('');
                    },
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSearchChips() {
    final recents = widget.store.recentSearches;
    if (recents.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '最近搜索',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => widget.store.clearSearchHistory(),
                child: Text(
                  '清空',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recents.map((term) {
              return GestureDetector(
                onTap: () => _applyRecentSearch(term),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    term,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final localResults = widget.store.searchLocalTracks(_query);
    final onlineResults = _onlineResults;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        if (widget.store.recentSearches.isNotEmpty) ...[
          _buildRecentSearchChips(),
        ],
        Row(
          children: [
            Text(
              '本地曲库匹配 (${localResults.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _isSearchingOnline ? null : () => _submitSearch(_query),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _emeraldBox,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearchingOnline)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _emerald,
                        ),
                      )
                    else
                      const Icon(
                        Icons.travel_explore_rounded,
                        size: 14,
                        color: _emerald,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      _isSearchingOnline ? '搜索中...' : '搜在线曲库',
                      style: const TextStyle(
                        color: _emerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (localResults.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '本地曲库暂无匹配，可点击右上角搜索在线曲库',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 13,
              ),
            ),
          )
        else
          ...List.generate(localResults.length, (index) {
            final track = localResults[index];
            return _SearchTrackTile(
              track: track,
              badge: '本地',
              onTap: () => _playTrackList(localResults, index: index),
            );
          }),
        if (onlineResults.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            '在线搜索结果 (${onlineResults.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(onlineResults.length, (index) {
            final track = onlineResults[index];
            return _SearchTrackTile(
              track: track,
              badge: '在线',
              onTap: () => _playTrackList(onlineResults, index: index),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildDiscoverFeed(bool showSearchPanel) {
    final library = widget.store.library;
    final playlists = widget.store.playlists;
    final albumMap = <String, List<Track>>{};
    for (final t in library) {
      final key = t.album.trim().isEmpty ? '未知专辑' : t.album;
      albumMap.putIfAbsent(key, () => <Track>[]).add(t);
    }
    final albums = albumMap.entries.map((e) => (name: e.key, tracks: e.value)).toList();

    final collections = <_PlaylistGridItem>[
      _PlaylistGridItem(
        title: '深夜放空 · 城市漫游',
        trackCount: math.max(library.length, 12),
        gradientColors: const [Color(0xFF1E3A5F), Color(0xFF0E1826)],
        coverTrack: library.isNotEmpty ? library.first : null,
        onTap: () => _playTrackList(library),
      ),
      _PlaylistGridItem(
        title: '晨跑节奏 · 能量补给',
        trackCount: math.max(library.length, 18),
        gradientColors: const [Color(0xFF1B4332), Color(0xFF0D1F18)],
        coverTrack: library.length > 1 ? library[1] : null,
        onTap: () => _playTrackList(library.reversed.toList()),
      ),
      _PlaylistGridItem(
        title: '专注工作 · 轻电子白噪',
        trackCount: math.max(library.length, 15),
        gradientColors: const [Color(0xFF3C2A4D), Color(0xFF17101E)],
        coverTrack: library.length > 2 ? library[2] : null,
        onTap: () => _playTrackList(library),
      ),
      _PlaylistGridItem(
        title: '逐字歌词 · 精选示范',
        trackCount: 8,
        gradientColors: const [Color(0xFF4A2511), Color(0xFF1D1008)],
        coverTrack: library.length > 3 ? library[3] : null,
        onTap: () {
          widget.store.playDemo();
          widget.onOpenPlayer();
        },
      ),
      for (final pl in playlists)
        _PlaylistGridItem(
          title: pl.name,
          trackCount: widget.store.tracksInPlaylist(pl.id).length,
          gradientColors: const [Color(0xFF1E2D30), Color(0xFF101719)],
          coverTrack: widget.store.tracksInPlaylist(pl.id).isNotEmpty ? widget.store.tracksInPlaylist(pl.id).first : null,
          onTap: () => _playTrackList(widget.store.tracksInPlaylist(pl.id)),
        ),
      for (final album in albums)
        _PlaylistGridItem(
          title: album.name,
          trackCount: album.tracks.length,
          gradientColors: const [Color(0xFF2B253A), Color(0xFF12101A)],
          coverTrack: album.tracks.isNotEmpty ? album.tracks.first : null,
          onTap: () => _playTrackList(album.tracks),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        if (showSearchPanel) _buildRecentSearchChips(),
        _SectionHeader(
          icon: Icons.show_chart_rounded,
          title: '曲库排行榜',
          subtitle: '实时榜 · 每小时更新',
        ),
        const SizedBox(height: 14),
        _buildHotChartHeroCard(library),
        const SizedBox(height: 10),
        _ChartRowCard(
          title: '新歌榜',
          subtitle: '实时榜单 · 整榜播放',
          track: library.length > 1
              ? library[1]
              : (library.isNotEmpty ? library.first : null),
          fallbackGradient: const [Color(0xFF1D3E4E), Color(0xFF0F2028)],
          onTap: () => _playTrackList(library.reversed.toList()),
        ),
        const SizedBox(height: 10),
        _ChartRowCard(
          title: '逐字演示榜',
          subtitle: '实时榜单 · 整榜播放',
          track: library.length > 2
              ? library[2]
              : (library.isNotEmpty ? library.first : null),
          fallbackGradient: const [Color(0xFF1B4530), Color(0xFF0D2117)],
          onTap: () {
            widget.store.playDemo();
            widget.onOpenPlayer();
          },
        ),
        const SizedBox(height: 26),
        _SectionHeader(
          icon: Icons.grid_view_rounded,
          title: '精选歌单',
          subtitle: '按心情与场景挑好 · 点开即整单播放',
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: collections.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            return _PlaylistGridCard(item: collections[index]);
          },
        ),
      ],
    );
  }

  Widget _buildHotChartHeroCard(List<dynamic> library) {
    return GestureDetector(
      onTap: () => _playTrackList(library),
      child: Container(
        height: 188,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF162229), Color(0xFF11181C)],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: 22,
              child: SizedBox(
                width: 220,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _FannedCoverCard(
                      angle: -0.18,
                      offset: const Offset(-42, 12),
                      track: library.length > 2 ? library[2] : null,
                      fallbackColors: const [
                        Color(0xFF284654),
                        Color(0xFF14242C),
                      ],
                    ),
                    _FannedCoverCard(
                      angle: 0.14,
                      offset: const Offset(42, 10),
                      track: library.length > 1 ? library[1] : null,
                      fallbackColors: const [
                        Color(0xFF2C4A3A),
                        Color(0xFF13241B),
                      ],
                    ),
                    _FannedCoverCard(
                      angle: -0.02,
                      offset: const Offset(0, 0),
                      track: library.isNotEmpty
                          ? library.first
                          : null,
                      fallbackColors: const [
                        Color(0xFF2FE08B),
                        Color(0xFF135035),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF11181C).withValues(alpha: 0.92),
                      const Color(0xFF11181C).withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.48, 0.88],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF183B29),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🔥 HOT',
                      style: TextStyle(
                        color: _emerald,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '热歌榜',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '实时热度 · 点开整榜播放',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
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

class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF123626),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF2FE08B),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FannedCoverCard extends StatelessWidget {
  const _FannedCoverCard({
    required this.angle,
    required this.offset,
    required this.track,
    required this.fallbackColors,
  });

  final double angle;
  final Offset offset;
  final dynamic track;
  final List<Color> fallbackColors;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 106,
          height: 106,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: fallbackColors,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: track != null
              ? CoverArtWidget(
                  accentColor: const Color(0xFF2FE08B),
                  track: track,
                  size: 106,
                  borderRadius: 18,
                )
              : Center(
                  child: Icon(
                    Icons.music_note_rounded,
                    color: Colors.white.withValues(alpha: 0.72),
                    size: 36,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ChartRowCard extends StatelessWidget {
  const _ChartRowCard({
    required this.title,
    required this.subtitle,
    required this.track,
    required this.fallbackGradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final dynamic track;
  final List<Color> fallbackGradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF151A1C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: fallbackGradient,
                ),
              ),
              child: track != null
                  ? CoverArtWidget(
                  accentColor: const Color(0xFF2FE08B),
                      track: track,
                      size: 56,
                      borderRadius: 14,
                    )
                  : Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 26,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.45),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistGridItem {
  const _PlaylistGridItem({
    required this.title,
    required this.trackCount,
    required this.gradientColors,
    required this.coverTrack,
    required this.onTap,
  });

  final String title;
  final int trackCount;
  final List<Color> gradientColors;
  final dynamic coverTrack;
  final VoidCallback onTap;
}

class _PlaylistGridCard extends StatelessWidget {
  const _PlaylistGridCard({required this.item});

  final _PlaylistGridItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: item.gradientColors,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.coverTrack != null)
              Opacity(
                opacity: 0.85,
                child: CoverArtWidget(
                  accentColor: const Color(0xFF2FE08B),
                  track: item.coverTrack,
                  size: 180,
                  borderRadius: 20,
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.82),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Text(
                  '▶ 歌单',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.trackCount} 首歌曲',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
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

class _SearchTrackTile extends StatelessWidget {
  const _SearchTrackTile({
    required this.track,
    required this.badge,
    required this.onTap,
  });

  final dynamic track;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF151A1C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            CoverArtWidget(
                  accentColor: const Color(0xFF2FE08B),
              track: track,
              size: 46,
              borderRadius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
