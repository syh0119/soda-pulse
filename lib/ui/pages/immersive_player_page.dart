import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/ui/pages/full_lyrics_page.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/pages/sub_pages.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';
import 'package:soda_pulse/ui/widgets/star_skin_bg.dart';

class ImmersivePlayerPage extends StatefulWidget {
  const ImmersivePlayerPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ImmersivePlayerPage> createState() => _ImmersivePlayerPageState();
}

class _ImmersivePlayerPageState extends State<ImmersivePlayerPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _breathController;
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);

  Timer? _progressTimer;
  double? _dragValueMs;
  int _lastSyncedIndex = -1;
  bool _isProgrammaticJump = false;

  @override
  void initState() {
    super.initState();
    final int initialIndex = _clampedCurrentIndex();
    _lastSyncedIndex = initialIndex;
    _pageController = PageController(initialPage: initialIndex);

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    if (widget.store.isPlaying) {
      _breathController.repeat(reverse: true);
    }

    _progressTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      if (widget.store.isPlaying && _dragValueMs == null) {
        _tickNotifier.value++;
      }
    });

    widget.store.addListener(_handleStoreChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChange);
    _progressTimer?.cancel();
    _breathController.dispose();
    _pageController.dispose();
    _tickNotifier.dispose();
    super.dispose();
  }

  int _clampedCurrentIndex() {
    final int count = widget.store.queue.length;
    if (count == 0) return 0;
    return widget.store.currentIndex.clamp(0, count - 1);
  }

  void _handleStoreChange() {
    if (!mounted) return;

    if (widget.store.isPlaying) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
    } else {
      if (_breathController.isAnimating) {
        _breathController.stop();
      }
    }

    final int targetIndex = _clampedCurrentIndex();
    if (_pageController.hasClients && targetIndex != _lastSyncedIndex) {
      _lastSyncedIndex = targetIndex;
      _isProgrammaticJump = true;
      _pageController
          .animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            _isProgrammaticJump = false;
          });
    }
  }

  void _openFullLyrics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullLyricsPage(store: widget.store),
      ),
    );
  }

  void _openArtistTracks(Track track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistTracksPage(
          store: widget.store,
          artistName: track.artist,
          onOpenPlayer: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openDrivePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrivePage(store: widget.store),
      ),
    );
  }

  void _openIslandSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IslandSettingsPage(bridge: widget.store.bridge),
      ),
    );
  }

  bool _isCarScale(BuildContext context) {
    final CarLayoutMode mode = widget.store.carLayoutMode;
    if (mode == CarLayoutMode.on) return true;
    if (mode == CarLayoutMode.off) return false;
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  String _formatLyricBadge(LyricFormat format) {
    switch (format) {
      case LyricFormat.yrcQrc:
        return 'YRC/QRC 逐字';
      case LyricFormat.krc:
        return 'KRC';
      case LyricFormat.enhancedLrc:
        return 'eLRC';
      case LyricFormat.plainLrc:
        return 'LRC';
      case LyricFormat.plainText:
        return 'TXT';
    }
  }

  String _formatDuration(int ms) {
    final int safeMs = math.max(0, ms);
    final int totalSeconds = safeMs ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final String m = minutes.toString().padLeft(2, '0');
    final String s = seconds.toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _findActiveLineIndex(ParsedLyric lyric, int positionMs) {
    final List<LyricLine> lines = lyric.lines;
    if (lines.isEmpty) return -1;
    int active = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startMs <= positionMs) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (BuildContext context, _) {
        final AppStore store = widget.store;
        final Color accent = store.accentColor;
        final EdgeInsets padding = MediaQuery.paddingOf(context);
        final bool carScale = _isCarScale(context);
        final double scale = carScale ? 1.25 : 1.0;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: StarSkinBackground(
            accentColor: accent,
            skin: store.skin,
            child: Padding(
              padding: EdgeInsets.only(top: padding.top),
              child: store.queue.isEmpty
                  ? _buildEmptyHero(context, store, accent, padding, scale)
                  : _buildPlayerBody(context, store, accent, padding, scale),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyHero(
    BuildContext context,
    AppStore store,
    Color accent,
    EdgeInsets padding,
    double scale,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          padding.bottom + 96,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 76 * scale,
                  height: 76 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[
                        accent.withValues(alpha: 0.88),
                        accent.withValues(alpha: 0.36),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 38 * scale,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Soda Pulse 沉浸播放',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '支持逐字歌词、灵动岛实况、车机自适应排版与多款流光皮肤。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5 * scale,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: store.playDemo,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: 14 * scale,
                        horizontal: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text(
                      '一键演示 (ColorOS 17 逐字/灵动岛实测)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: store.rescanLibrary,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: 14 * scale,
                        horizontal: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                      '扫描本地音乐',
                      style: TextStyle(
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerBody(
    BuildContext context,
    AppStore store,
    Color accent,
    EdgeInsets padding,
    double scale,
  ) {
    final Track? currentTrack = store.currentTrack;
    final double bottomClearance = padding.bottom + (store.pureMode ? 18 : 88);

    return Column(
      children: <Widget>[
        _buildTopHeader(context, store, accent, scale),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: store.queue.length,
            onPageChanged: (int index) {
              if (_isProgrammaticJump) return;
              _lastSyncedIndex = index;
              if (index != store.currentIndex) {
                store.playTrackFromQueue(index);
              }
            },
            itemBuilder: (BuildContext context, int index) {
              final Track track = store.queue[index];
              final bool isCurrent = index == store.currentIndex;
              return _buildTrackPage(
                context: context,
                store: store,
                track: track,
                isCurrent: isCurrent,
                accent: accent,
                scale: scale,
              );
            },
          ),
        ),
        if (currentTrack != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomClearance),
            child: store.pureMode
                ? _buildPureTransport(store, accent, scale)
                : _buildFullBottomControls(store, currentTrack, accent, scale),
          )
        else
          SizedBox(height: bottomClearance),
      ],
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
    AppStore store,
    Color accent,
    double scale,
  ) {
    if (store.pureMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            GestureDetector(
              onTap: () => store.setPureMode(false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.fullscreen_exit_rounded,
                      size: 16 * scale,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '退出纯净',
                      style: TextStyle(
                        fontSize: 12.5 * scale,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '驾驶模式',
            onPressed: _openDrivePage,
            icon: Icon(
              Icons.directions_car_rounded,
              size: 22 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          IconButton(
            tooltip: '灵动岛设置',
            onPressed: _openIslandSettings,
            icon: Icon(
              Icons.dynamic_feed_rounded,
              size: 21 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _playerStyleLabel(store.playerStyle),
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                Text(
                  '${_clampedCurrentIndex() + 1} / ${store.queue.length}',
                  style: TextStyle(
                    fontSize: 10.5 * scale,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '纯净模式',
            onPressed: () => store.setPureMode(true),
            icon: Icon(
              Icons.spa_outlined,
              size: 21 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          IconButton(
            tooltip: '皮肤与排版',
            onPressed: () => showSkinAndLayoutSheet(context, store),
            icon: Icon(
              Icons.palette_outlined,
              size: 21 * scale,
              color: accent.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  String _playerStyleLabel(PlayerStyle style) {
    switch (style) {
      case PlayerStyle.free:
        return 'FREE 沉浸';
      case PlayerStyle.immersive:
        return 'IMMERSIVE 黑胶';
      case PlayerStyle.recommend:
        return 'KARAOKE 逐字';
    }
  }

  Widget _buildTrackPage({
    required BuildContext context,
    required AppStore store,
    required Track track,
    required bool isCurrent,
    required Color accent,
    required double scale,
  }) {
    if (store.pureMode) {
      return _buildPurePage(store, track, accent, scale);
    }

    switch (store.playerStyle) {
      case PlayerStyle.free:
        return _buildFreeStylePage(store, track, isCurrent, accent, scale);
      case PlayerStyle.immersive:
        return _buildImmersiveStylePage(
          store,
          track,
          isCurrent,
          accent,
          scale,
        );
      case PlayerStyle.recommend:
        return _buildRecommendStylePage(
          store,
          track,
          isCurrent,
          accent,
          scale,
        );
    }
  }

  Widget _buildBreathingCover({
    required Track track,
    required AppStore store,
    required Color accent,
    required double size,
    required double borderRadius,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _breathController,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeInOut.transform(_breathController.value);
          final double animScale = store.isPlaying ? (0.985 + t * 0.032) : 0.98;
          return Transform.scale(
            scale: animScale,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, 14),
                spreadRadius: -6,
              ),
            ],
          ),
          child: CoverArtWidget(
            track: track,
            localPath: store.coverPathFor(track),
            accentColor: accent,
            size: size,
            borderRadius: borderRadius,
            showVinylRing: false,
          ),
        ),
      ),
    );
  }

  Widget _buildFreeStylePage(
    AppStore store,
    Track track,
    bool isCurrent,
    Color accent,
    double scale,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double coverSize = math.min(
          170 * scale,
          constraints.maxHeight * 0.34,
        );

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                const SizedBox(height: 6),
                _buildBreathingCover(
                  track: track,
                  store: store,
                  accent: accent,
                  size: coverSize,
                  borderRadius: 22,
                  onTap: _openFullLyrics,
                ),
                const SizedBox(height: 14),
                _buildFiveLineLyrics(store, isCurrent, accent, scale),
                const SizedBox(height: 14),
                _buildTrackMetadata(
                  store: store,
                  track: track,
                  accent: accent,
                  scale: scale,
                  centered: true,
                ),
                const SizedBox(height: 16),
                _buildFiveSquareActions(store, track, accent, scale),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFiveLineLyrics(
    AppStore store,
    bool isCurrent,
    Color accent,
    double scale,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: _tickNotifier,
      builder: (BuildContext context, int tick, Widget? child) {
        final ParsedLyric lyric = store.currentLyrics;
        if (!isCurrent || lyric.lines.isEmpty) {
          return GestureDetector(
            onTap: _openFullLyrics,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '轻触查看全屏逐字歌词',
                style: TextStyle(
                  fontSize: 14 * scale,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          );
        }

        final int effectiveMs =
            store.positionMs + store.bridge.lyricOffsetMs;
        final int activeIdx = _findActiveLineIndex(lyric, effectiveMs);

        return GestureDetector(
          onTap: _openFullLyrics,
          behavior: HitTestBehavior.opaque,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: <double>[0.0, 0.22, 0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(5, (int slot) {
                final int offset = slot - 2;
                final int lineIdx = activeIdx + offset;
                final bool valid =
                    lineIdx >= 0 && lineIdx < lyric.lines.length;
                final String text = valid ? lyric.lines[lineIdx].text : '';
                final bool isActive = offset == 0;
                final double alpha = isActive
                    ? 1.0
                    : (offset.abs() == 1 ? 0.56 : 0.28);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.5),
                  child: Text(
                    text.isEmpty ? ' ' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (isActive ? 17.5 : 14) * scale,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w400,
                      color: Colors.white.withValues(alpha: alpha),
                      shadows: isActive
                          ? <Shadow>[
                              Shadow(
                                color: accent.withValues(alpha: 0.65),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImmersiveStylePage(
    AppStore store,
    Track track,
    bool isCurrent,
    Color accent,
    double scale,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double coverSize = math.min(
          252 * scale,
          constraints.maxHeight * 0.45,
        );

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                const SizedBox(height: 8),
                _buildBreathingCover(
                  track: track,
                  store: store,
                  accent: accent,
                  size: coverSize,
                  borderRadius: 28,
                  onTap: _openFullLyrics,
                ),
                const SizedBox(height: 18),
                _buildTrackMetadata(
                  store: store,
                  track: track,
                  accent: accent,
                  scale: scale,
                  centered: true,
                ),
                const SizedBox(height: 12),
                _buildTwoLineLyricPreview(store, isCurrent, accent, scale),
                const SizedBox(height: 16),
                _buildFiveSquareActions(store, track, accent, scale),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTwoLineLyricPreview(
    AppStore store,
    bool isCurrent,
    Color accent,
    double scale,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: _tickNotifier,
      builder: (BuildContext context, int tick, Widget? child) {
        final ParsedLyric lyric = store.currentLyrics;
        if (!isCurrent || lyric.lines.isEmpty) {
          return GestureDetector(
            onTap: _openFullLyrics,
            child: Text(
              '点击封面或此处展开歌词',
              style: TextStyle(
                fontSize: 13.5 * scale,
                color: Colors.white.withValues(alpha: 0.52),
              ),
            ),
          );
        }

        final int effectiveMs =
            store.positionMs + store.bridge.lyricOffsetMs;
        final int activeIdx = _findActiveLineIndex(lyric, effectiveMs);
        final String currentLine = activeIdx >= 0
            ? lyric.lines[activeIdx].text
            : '';
        final String nextLine =
            (activeIdx + 1 < lyric.lines.length)
                ? lyric.lines[activeIdx + 1].text
                : '';

        return GestureDetector(
          onTap: _openFullLyrics,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                currentLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                nextLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5 * scale,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecommendStylePage(
    AppStore store,
    Track track,
    bool isCurrent,
    Color accent,
    double scale,
  ) {
    final bool isFav = store.isFavorite(track.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _buildBreathingCover(
                track: track,
                store: store,
                accent: accent,
                size: 64 * scale,
                borderRadius: 14,
                onTap: _openFullLyrics,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildTrackMetadata(
                  store: store,
                  track: track,
                  accent: accent,
                  scale: scale,
                  centered: false,
                ),
              ),
              IconButton(
                onPressed: () => store.toggleFavorite(track),
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 28 * scale,
                  color: isFav
                      ? accent
                      : Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _tickNotifier,
              builder: (BuildContext context, int tick, Widget? child) {
                return KaraokeLyricView(
                  lyrics: store.currentLyrics,
                  positionProvider: () => isCurrent ? store.positionMs : 0,
                  offsetMs: store.bridge.lyricOffsetMs,
                  accentColor: accent,
                  onSeekToMs: store.seekTo,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurePage(
    AppStore store,
    Track track,
    Color accent,
    double scale,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double coverSize = math.min(
          248 * scale,
          constraints.maxHeight * 0.54,
        );

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildBreathingCover(
                  track: track,
                  store: store,
                  accent: accent,
                  size: coverSize,
                  borderRadius: 28,
                  onTap: _openFullLyrics,
                ),
                const SizedBox(height: 26),
                _buildTrackMetadata(
                  store: store,
                  track: track,
                  accent: accent,
                  scale: scale,
                  centered: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackMetadata({
    required AppStore store,
    required Track track,
    required Color accent,
    required double scale,
    required bool centered,
  }) {
    final String badge = _formatLyricBadge(store.currentLyrics.format);

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: <Widget>[
            Flexible(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 0.8,
                ),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _openArtistTracks(track),
          child: Container(
            padding: const EdgeInsets.only(bottom: 1.5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.36),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16 * scale,
                  color: Colors.white.withValues(alpha: 0.56),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiveSquareActions(
    AppStore store,
    Track track,
    Color accent,
    double scale,
  ) {
    final bool isFav = store.isFavorite(track.id);
    final double btnHeight = 46 * scale;

    return Row(
      children: <Widget>[
        Expanded(
          child: _buildGlassSquareButton(
            height: btnHeight,
            filledColor: isFav ? accent.withValues(alpha: 0.34) : null,
            borderColor: isFav ? accent.withValues(alpha: 0.72) : null,
            onTap: () => store.toggleFavorite(track),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 21 * scale,
              color: isFav ? Colors.white : Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildGlassSquareButton(
            height: btnHeight,
            onTap: store.shareCurrentTrack,
            child: Icon(
              Icons.ios_share_rounded,
              size: 20 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildGlassSquareButton(
            height: btnHeight,
            onTap: () => showQueueSheet(context, store),
            child: Icon(
              Icons.queue_music_rounded,
              size: 22 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildGlassSquareButton(
            height: btnHeight,
            onTap: () {
              store.refreshRecommendQueue();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('已刷新待播推荐队列'),
                    duration: Duration(milliseconds: 1400),
                  ),
                );
            },
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20 * scale,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: btnHeight,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              color: const Color(0xFF1D2230),
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 22 * scale,
                color: Colors.white.withValues(alpha: 0.86),
              ),
              onSelected: (String value) {
                switch (value) {
                  case 'skin':
                    showSkinAndLayoutSheet(context, store);
                  case 'import_lyric':
                    store.importExternalLyric();
                  case 'desktop_lyric':
                    store.toggleDesktopLyric();
                  case 'drive':
                    _openDrivePage();
                  case 'island':
                    _openIslandSettings();
                  case 'pure':
                    store.setPureMode(true);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'skin',
                  child: Text(
                    '皮肤与播放样式',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'import_lyric',
                  child: Text(
                    '导入外部歌词',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'desktop_lyric',
                  child: Text(
                    store.desktopLyricEnabled ? '关闭桌面歌词' : '开启桌面歌词',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'drive',
                  child: Text(
                    '车机驾驶模式',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'island',
                  child: Text(
                    '灵动岛实时活动',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'pure',
                  child: Text(
                    '进入纯净模式',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassSquareButton({
    required double height,
    required VoidCallback onTap,
    required Widget child,
    Color? filledColor,
    Color? borderColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: filledColor ?? Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildPureTransport(AppStore store, Color accent, double scale) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: store.playPrevious,
          iconSize: 34 * scale,
          color: Colors.white,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 24),
        _buildPlayPauseCircle(store, accent, scale),
        const SizedBox(width: 24),
        IconButton(
          onPressed: store.playNext,
          iconSize: 34 * scale,
          color: Colors.white,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }

  Widget _buildFullBottomControls(
    AppStore store,
    Track track,
    Color accent,
    double scale,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ValueListenableBuilder<int>(
          valueListenable: _tickNotifier,
          builder: (BuildContext context, int tick, Widget? child) {
            final int durationMs = math.max(1, track.durationMs);
            final double currentMs = (_dragValueMs ??
                    store.positionMs.toDouble())
                .clamp(0, durationMs.toDouble());

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5 * scale,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: 6 * scale,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: 14 * scale,
                    ),
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                    thumbColor: Colors.white,
                    overlayColor: accent.withValues(alpha: 0.24),
                  ),
                  child: Slider(
                    min: 0,
                    max: durationMs.toDouble(),
                    value: currentMs,
                    onChanged: (double value) {
                      setState(() {
                        _dragValueMs = value;
                      });
                    },
                    onChangeEnd: (double value) {
                      setState(() {
                        _dragValueMs = null;
                      });
                      store.seekTo(value.round());
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        _formatDuration(currentMs.round()),
                        style: TextStyle(
                          fontSize: 11.5 * scale,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                      Text(
                        _formatDuration(durationMs),
                        style: TextStyle(
                          fontSize: 11.5 * scale,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              tooltip: '切换播放模式',
              onPressed: store.cyclePlayMode,
              iconSize: 23 * scale,
              color: Colors.white.withValues(alpha: 0.85),
              icon: Icon(_playModeIcon(store.playMode)),
            ),
            IconButton(
              onPressed: store.playPrevious,
              iconSize: 34 * scale,
              color: Colors.white,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            _buildPlayPauseCircle(store, accent, scale),
            IconButton(
              onPressed: store.playNext,
              iconSize: 34 * scale,
              color: Colors.white,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              tooltip: '全屏歌词',
              onPressed: _openFullLyrics,
              iconSize: 23 * scale,
              color: Colors.white.withValues(alpha: 0.85),
              icon: const Icon(Icons.lyrics_outlined),
            ),
          ],
        ),
      ],
    );
  }

  IconData _playModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequence:
        return Icons.repeat_rounded;
      case PlayMode.single:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
      case PlayMode.smart:
        return Icons.auto_awesome_motion_rounded;
    }
  }

  Widget _buildPlayPauseCircle(AppStore store, Color accent, double scale) {
    final double circleSize = 60 * scale;

    return GestureDetector(
      onTap: store.togglePlayPause,
      child: Container(
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: <Color>[
              accent,
              accent.withValues(alpha: 0.78),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.42),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          store.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 34 * scale,
          color: Colors.white,
        ),
      ),
    );
  }
}
