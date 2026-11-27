import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/sub_pages.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/ui/pages/full_lyrics_page.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';

class ImmersivePlayerPage extends StatefulWidget {
  const ImmersivePlayerPage({
    super.key,
    required this.store,
    this.onOpenDiscover,
    this.onOpenMine,
    this.onOpenSearch,
  });

  final AppStore store;
  final VoidCallback? onOpenDiscover;
  final VoidCallback? onOpenMine;
  final VoidCallback? onOpenSearch;

  @override
  State<ImmersivePlayerPage> createState() => _ImmersivePlayerPageState();
}

class _ImmersivePlayerPageState extends State<ImmersivePlayerPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late PageController _contentPageController;
  late final Ticker _lyricTicker;
  final ValueNotifier<int> _livePosNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _lyricsPageProgress = ValueNotifier<double>(0.0);
  int _lastSyncedIndex = -1;
  bool _isSyncingPage = false;
  bool _isOnLyricsTab = false;
  late bool _lastPureMode;
  late PlayerStyle _lastPlayerStyle;
  late bool _lastQueueEmpty;

  bool _isDraggingSlider = false;
  double _dragPositionMs = 0;
  bool _shownStartupToast = false;
  double _coverDragDx = 0;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _lastSyncedIndex = store.currentIndex;
    _lastPureMode = store.pureMode;
    _lastPlayerStyle = store.playerStyle;
    _lastQueueEmpty = store.queue.isEmpty;
    _pageController = PageController(
      initialPage: math.max(0, store.currentIndex),
    );
    _contentPageController = PageController(initialPage: 0)
      ..addListener(_onContentScroll);
    _livePosNotifier.value = store.livePositionMs;
    _lyricTicker = createTicker((_) {
      if (!mounted) return;
      final pos = store.livePositionMs;
      if (pos != _livePosNotifier.value) {
        _livePosNotifier.value = pos;
      }
    });
    if (store.isPlaying) {
      _lyricTicker.start();
    }
    store.addListener(_onStoreChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownStartupToast) return;
      final toast = store.startupPluginToast;
      if (toast != null && toast.isNotEmpty) {
        _shownStartupToast = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toast),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant ImmersivePlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
      _lastSyncedIndex = widget.store.currentIndex;
      _lastPureMode = widget.store.pureMode;
      _lastPlayerStyle = widget.store.playerStyle;
      _lastQueueEmpty = widget.store.queue.isEmpty;
    }
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _lyricTicker.dispose();
    _livePosNotifier.dispose();
    _lyricsPageProgress.dispose();
    _contentPageController.removeListener(_onContentScroll);
    _contentPageController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onContentScroll() {
    if (!_contentPageController.hasClients) return;
    final page = _contentPageController.page ?? (_isOnLyricsTab ? 1.0 : 0.0);
    _lyricsPageProgress.value = page.clamp(0.0, 1.0);
  }

  void _animateToLyricsTab() {
    if (_contentPageController.hasClients) {
      _contentPageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _openFullLyrics();
    }
  }

  void _animateToCoverTab() {
    if (_contentPageController.hasClients) {
      _contentPageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _recreatePageControllerForIndex(int targetIndex) {
    final oldCtrl = _pageController;
    _pageController = PageController(initialPage: math.max(0, targetIndex));
    _lastSyncedIndex = targetIndex;
    _isSyncingPage = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());
  }

  void _resetContentPageController() {
    final oldCtrl = _contentPageController;
    oldCtrl.removeListener(_onContentScroll);
    _contentPageController = PageController(initialPage: 0)
      ..addListener(_onContentScroll);
    _isOnLyricsTab = false;
    _lyricsPageProgress.value = 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());
  }

  void _scheduleJumpGuard(int targetIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (targetIndex == store.currentIndex &&
          targetIndex >= 0 &&
          targetIndex < store.queue.length) {
        final currentPage = _pageController.page?.round() ?? -1;
        if (currentPage != targetIndex) {
          _isSyncingPage = true;
          _pageController.jumpToPage(targetIndex);
          _lastSyncedIndex = targetIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isSyncingPage = false;
          });
        }
      }
    });
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (store.isPlaying) {
      if (!_lyricTicker.isActive) {
        _lyricTicker.start();
      }
    } else {
      if (_lyricTicker.isActive) {
        _lyricTicker.stop();
      }
      _livePosNotifier.value = store.livePositionMs;
    }

    final targetIndex = store.currentIndex;
    final modeChanged =
        store.pureMode != _lastPureMode || store.playerStyle != _lastPlayerStyle;
    final queueBecameNonEmpty = _lastQueueEmpty && store.queue.isNotEmpty;
    _lastPureMode = store.pureMode;
    _lastPlayerStyle = store.playerStyle;
    _lastQueueEmpty = store.queue.isEmpty;

    if (modeChanged || queueBecameNonEmpty) {
      _recreatePageControllerForIndex(targetIndex);
      if (modeChanged) {
        _resetContentPageController();
      }
      if (targetIndex >= 0 && targetIndex < store.queue.length) {
        _scheduleJumpGuard(targetIndex);
      }
      return;
    }

    if (targetIndex != _lastSyncedIndex &&
        targetIndex >= 0 &&
        targetIndex < store.queue.length) {
      if (_pageController.hasClients) {
        _lastSyncedIndex = targetIndex;
        final currentPage = _pageController.page?.round() ?? targetIndex;
        if (currentPage != targetIndex) {
          _isSyncingPage = true;
          _pageController
              .animateToPage(
                targetIndex,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() {
                _isSyncingPage = false;
              });
        }
      } else {
        _recreatePageControllerForIndex(targetIndex);
      }
    }
  }

  void _openFullLyrics() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullLyricsPage(store: store),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  void _onCoverHorizontalDragStart(DragStartDetails details) {
    _coverDragDx = 0;
  }

  void _onCoverHorizontalDragUpdate(DragUpdateDetails details) {
    _coverDragDx += details.delta.dx;
  }

  void _onCoverHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -220 || _coverDragDx < -56) {
      _openFullLyrics();
    }
    _coverDragDx = 0;
  }

  void _openIslandSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IslandSettingsPage(bridge: store.bridge),
      ),
    );
  }

  void _openDrivePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrivePage(store: store),
      ),
    );
  }

  void _openArtistTracks(Track track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistTracksPage(
          store: store,
          artistName: track.artist,
          onOpenPlayer: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    final totalSeconds = math.max(0, ms ~/ 1000);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }

  String? _currentLyricLine(int positionMs) {
    final lines = store.currentLyrics.lines;
    if (lines.isEmpty) return null;
    String? activeText;
    for (final line in lines) {
      if (line.startMs <= positionMs) {
        activeText = line.text;
      } else {
        break;
      }
    }
    return activeText ?? lines.first.text;
  }

  ({int activeIndex, List<LyricLine?> lines}) _fiveLineLyricWindow(int positionMs) {
    final lines = store.currentLyrics.lines;
    if (lines.isEmpty) {
      return (activeIndex: -1, lines: const <LyricLine?>[]);
    }
    final effectiveMs = positionMs + store.bridge.lyricOffsetMs;
    int activeIdx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startMs <= effectiveMs) {
        activeIdx = i;
      } else {
        break;
      }
    }
    final window = List<LyricLine?>.generate(5, (slot) {
      final idx = activeIdx + (slot - 2);
      if (idx < 0 || idx >= lines.length) return null;
      return lines[idx];
    });
    return (activeIndex: activeIdx, lines: window);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final scale = (media.size.width / 390.0).clamp(0.86, 1.12);
        final track = store.currentTrack;

        final bool isPureActive =
            store.pureMode && store.queue.isNotEmpty && track != null;

        return PopScope(
          canPop: !_isOnLyricsTab,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isOnLyricsTab) {
              _animateToCoverTab();
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0E1512),
            body: isPureActive
                ? _buildPureModeView(context, track, scale)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildAtmosphericBackground(track),
                      SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            _buildTopBar(context),
                            Expanded(
                              child: (store.queue.isEmpty || track == null)
                                  ? _buildEmptyHero(context, scale)
                                  : _buildPlayerBody(context, track, scale),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAtmosphericBackground(Track? track) {
    final accent = store.accentColor;
    final topTint = Color.lerp(const Color(0xFF18241F), accent, 0.34)!;
    final midTint = Color.lerp(const Color(0xFF111A16), accent, 0.22)!;
    const bottomTint = Color(0xFF0A0F0D);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (track != null)
          Opacity(
            opacity: store.playerStyle == PlayerStyle.immersive ? 0.52 : 0.32,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
              child: CoverArtWidget(
                track: track,
                localPath: store.coverPathFor(track),
                accentColor: accent,
                size: 420,
                borderRadius: 0,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                topTint.withValues(alpha: 0.72),
                midTint.withValues(alpha: 0.84),
                bottomTint.withValues(alpha: 0.96),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final track = store.currentTrack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _lyricsPageProgress,
              builder: (context, t, _) {
                final showLyricsHeader =
                    store.playerStyle == PlayerStyle.free && t > 0.5 && track != null;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: showLyricsHeader
                      ? GestureDetector(
                          key: const ValueKey<String>('lyrics_header'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _animateToCoverTab,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.chevron_left_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          key: const ValueKey<String>('mode_header'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showModeSelectSheet(context, store),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.menu_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 14),
                                Text(
                                  '模式选择',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
          if (store.carLayoutMode == CarLayoutMode.on ||
              (store.carLayoutMode == CarLayoutMode.auto &&
                  MediaQuery.orientationOf(context) == Orientation.landscape))
            IconButton(
              tooltip: '车载模式',
              onPressed: _openDrivePage,
              icon: const Icon(
                Icons.directions_car_rounded,
                size: 24,
                color: Colors.white,
              ),
            ),
          IconButton(
            onPressed: widget.onOpenSearch ?? widget.onOpenDiscover,
            icon: const Icon(
              Icons.search_rounded,
              size: 26,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Color _pureBackgroundColor() {
    final hsl = HSLColor.fromColor(store.accentColor);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.68))
        .withLightness(hsl.lightness.clamp(0.18, 0.28))
        .toColor();
  }

  Widget _buildPureModeView(
    BuildContext context,
    Track currentTrack,
    double scale,
  ) {
    final media = MediaQuery.of(context);
    final pureBg = _pureBackgroundColor();
    final topPad = media.padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 360),
          color: pureBg,
        ),
        PageView.builder(
          key: const ValueKey<String>('pure_vertical_pager'),
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: store.queue.length,
          onPageChanged: (index) {
            if (_isSyncingPage) return;
            _lastSyncedIndex = index;
            if (_isOnLyricsTab) {
              _isOnLyricsTab = false;
              _lyricsPageProgress.value = 0.0;
            }
            store.playTrackFromQueue(index);
          },
          itemBuilder: (context, index) {
            final track = store.queue[index];
            return _buildPureModePage(
              context,
              track: track,
              isActive: index == store.currentIndex,
              pureBg: pureBg,
              scale: scale,
            );
          },
        ),
        Positioned(
          top: topPad + 8,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<double>(
            valueListenable: _lyricsPageProgress,
            builder: (context, t, _) {
              final showLyricsBar = t > 0.5;
              return Row(
                children: [
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.24),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: showLyricsBar
                              ? _animateToCoverTab
                              : () => showModeSelectSheet(context, store),
                          child: SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(
                              showLyricsBar
                                  ? Icons.chevron_left_rounded
                                  : Icons.menu_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showLyricsBar) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _animateToCoverTab,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              currentTrack.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPureModePage(
    BuildContext context, {
    required Track track,
    required bool isActive,
    required Color pureBg,
    required double scale,
  }) {
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final bottomInset = media.padding.bottom;
    final isFav = store.isFavorite(track.id);

    final Widget coverStage = ValueListenableBuilder<double>(
      valueListenable: _lyricsPageProgress,
      builder: (context, t, child) {
        final double activeT = isActive ? t : 0.0;
        return Opacity(
          opacity: (1.0 - activeT * 0.45).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1.0 - activeT * 0.035,
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          GestureDetector(
            onTap: store.togglePlayPause,
            onLongPress: () => store.setPureMode(false),
            child: SizedBox(
              height: screenH * 0.50,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildFullBleedCover(track),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          pureBg.withValues(alpha: 0.65),
                          pureBg,
                        ],
                        stops: const [0.0, 0.60, 0.86, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21 * scale,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openArtistTracks(track),
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5 * scale,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildPureCircleButton(
                  icon: isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  onTap: () => store.toggleFavorite(track),
                ),
                const SizedBox(width: 10),
                _buildPureCircleButton(
                  icon: Icons.more_vert_rounded,
                  onTap: () => showMoreRoamSheet(
                    context,
                    store,
                    onOpenLyrics: _animateToLyricsTab,
                    onOpenIsland: _openIslandSettings,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: _buildPureThreeLineLyrics(
                context,
                isActive: isActive,
                scale: scale,
              ),
            ),
          ),
        ],
      ),
    );

    final Widget inlineLyricsStage = ValueListenableBuilder<double>(
      valueListenable: _lyricsPageProgress,
      builder: (context, t, child) {
        return Opacity(
          opacity: (0.2 + t * 0.8).clamp(0.0, 1.0),
          child: child,
        );
      },
      child: Column(
        children: [
          SizedBox(height: media.padding.top + 56),
          Expanded(
            child: KaraokeLyricView(
              lyrics: store.currentLyrics,
              positionProvider: () => store.livePositionMs,
              offsetMs: store.bridge.lyricOffsetMs,
              accentColor: store.accentColor,
              onSeekToMs: store.seekTo,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: store.importExternalLyric,
                  child: Text(
                    store.lyricSourceLabel.isNotEmpty
                        ? '词 ${store.lyricSourceLabel}'
                        : '导入歌词',
                    style: TextStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                _buildCapsuleButton(
                  label: '调轴/全屏',
                  onTap: _openFullLyrics,
                ),
                const SizedBox(width: 8),
                _buildCapsuleButton(
                  label: '封面',
                  onTap: _animateToCoverTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: isActive
              ? PageView(
                  controller: _contentPageController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() {
                      _isOnLyricsTab = page == 1;
                    });
                  },
                  children: [
                    coverStage,
                    inlineLyricsStage,
                  ],
                )
              : coverStage,
        ),
        _buildPureLowerProgressAndTransport(
          context,
          track,
          isActive: isActive,
          scale: scale,
          bottomInset: bottomInset,
        ),
      ],
    );
  }

  Widget _buildFullBleedCover(Track track) {
    final localPath = store.coverPathFor(track);
    final uri = track.albumArtUri;
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            store.accentColor.withValues(alpha: 0.72),
            const Color(0xFF141B22),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 88,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );

    if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    if (uri != null && uri.startsWith('http')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return fallback;
  }

  Widget _buildPureCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: Colors.white,
            size: 21,
          ),
        ),
      ),
    );
  }

  Widget _buildPureThreeLineLyrics(
    BuildContext context, {
    required bool isActive,
    required double scale,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _animateToLyricsTab,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: ValueListenableBuilder<int>(
            valueListenable: _livePosNotifier,
            builder: (context, livePos, _) {
              final effectivePos = livePos + store.bridge.lyricOffsetMs;
              final five = isActive
                  ? _fiveLineLyricWindow(livePos)
                  : (activeIndex: -1, lines: const <LyricLine?>[]);
              final hasLyrics = five.activeIndex >= 0 && five.lines.isNotEmpty;

              if (!hasLyrics) {
                return Text(
                  '暂无歌词 · 左滑或轻触查看歌词',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5 * scale,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                );
              }

              final three = <LyricLine?>[
                five.lines[1],
                five.lines[2],
                five.lines[3],
              ];

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: SizedBox(
                  key: ValueKey<int>(five.activeIndex),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(3, (slot) {
                      final lineObj = three[slot];
                      final lineText = lineObj?.text.trim() ?? '';
                      if (lineObj == null || lineText.isEmpty) {
                        return const SizedBox(height: 2);
                      }
                      if (slot == 1) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: KaraokeSingleLineSweep(
                            line: lineObj,
                            positionMs: effectivePos,
                            style: TextStyle(
                              fontSize: 17.5 * scale,
                              fontWeight: FontWeight.w700,
                              height: 1.30,
                            ),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withValues(alpha: 0.44),
                            glowColor: store.accentColor.withValues(alpha: 0.45),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          lineText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5 * scale,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.52),
                            height: 1.24,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPureLowerProgressAndTransport(
    BuildContext context,
    Track track, {
    required bool isActive,
    required double scale,
    required double bottomInset,
  }) {
    final durationMs = math.max(1, track.durationMs);
    final rawPos = isActive
        ? (_isDraggingSlider ? _dragPositionMs.round() : store.positionMs)
        : 0;
    final clampedPos = rawPos.clamp(0, durationMs);
    final remainingMs = math.max(0, durationMs - clampedPos);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, bottomInset + 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24 * scale,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.16),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                  elevation: 0,
                  pressedElevation: 2,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackShape: const _FullWidthTrackShape(),
              ),
              child: Slider(
                min: 0,
                max: durationMs.toDouble(),
                value: clampedPos.toDouble(),
                onChangeStart: (v) {
                  setState(() {
                    _isDraggingSlider = true;
                    _dragPositionMs = v;
                  });
                },
                onChanged: (v) {
                  setState(() {
                    _dragPositionMs = v;
                  });
                },
                onChangeEnd: (v) {
                  setState(() {
                    _isDraggingSlider = false;
                  });
                  store.seekTo(v.round());
                },
              ),
            ),
          ),
          Row(
            children: [
              Text(
                _formatDuration(clampedPos),
                style: TextStyle(
                  fontSize: 12 * scale,
                  color: Colors.white.withValues(alpha: 0.74),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showSoundEffectSheet(context, store),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    '高品质',
                    style: TextStyle(
                      fontSize: 12.5 * scale,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '-${_formatDuration(remainingMs)}',
                style: TextStyle(
                  fontSize: 12 * scale,
                  color: Colors.white.withValues(alpha: 0.74),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(height: 16 * scale),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: store.playPrevious,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    size: 38 * scale,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: store.togglePlayPause,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      store.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 52 * scale,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: store.playNext,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    size: 38 * scale,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHero(BuildContext context, double scale) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: store.accentColor.withValues(alpha: 0.22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '暂无正在播放的歌曲',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '可立即播放示例曲目，或扫描本地音乐库开启畅听',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5 * scale,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: store.playDemo,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF101814),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text(
                              '播放示例',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: store.rescanLibrary,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              '扫描曲库',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (store.bottomBarStyle == BottomBarStyle.native && !store.pureMode)
          Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: _buildNativeBottomRow(scale),
          )
        else
          SizedBox(height: bottomPad + 76),
      ],
    );
  }

  Widget _buildPlayerBody(BuildContext context, Track currentTrack, double scale) {
    final style = store.playerStyle;
    if (style == PlayerStyle.immersive) {
      return _buildImmersiveStyleBody(context, currentTrack, scale);
    }
    if (style == PlayerStyle.recommend) {
      return _buildRecommendStyleBody(context, currentTrack, scale);
    }
    return _buildFreeModeBody(context, scale);
  }

  Widget _buildFreeModeBody(BuildContext context, double scale) {
    return PageView.builder(
      key: const ValueKey<String>('free_vertical_pager'),
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: store.queue.length,
      onPageChanged: (index) {
        if (_isSyncingPage) return;
        _lastSyncedIndex = index;
        if (_isOnLyricsTab) {
          _isOnLyricsTab = false;
          _lyricsPageProgress.value = 0.0;
        }
        store.playTrackFromQueue(index);
      },
      itemBuilder: (context, index) {
        final track = store.queue[index];
        return _buildFreeModePage(context, track, index == store.currentIndex, scale);
      },
    );
  }

  Widget _buildFreeModePage(
    BuildContext context,
    Track track,
    bool isActive,
    double scale,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isGlassBar = store.bottomBarStyle == BottomBarStyle.glass;

    final Widget coverStage = LayoutBuilder(
      builder: (context, constraints) {
        final hasLyrics = isActive && store.currentLyrics.lines.isNotEmpty;
        final maxCoverW = (constraints.maxWidth - 50).clamp(160.0, 360.0);
        final reservedBelow = (hasLyrics ? 236.0 : 148.0) * scale;
        final coverSize = math
            .min(maxCoverW, constraints.maxHeight - reservedBelow)
            .clamp(150.0, maxCoverW);

        return ValueListenableBuilder<double>(
          valueListenable: _lyricsPageProgress,
          builder: (context, t, child) {
            final double activeT = isActive ? t : 0.0;
            return Opacity(
              opacity: (1.0 - activeT * 0.45).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.0 - activeT * 0.035,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: (hasLyrics ? 10 : 28) * scale),
              GestureDetector(
                onTap: store.togglePlayPause,
                onLongPress: () => store.setPureMode(!store.pureMode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: coverSize,
                  height: coverSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.36),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: CoverArtWidget(
                    track: track,
                    localPath: store.coverPathFor(track),
                    accentColor: store.accentColor,
                    size: coverSize,
                    borderRadius: 24,
                  ),
                ),
              ),
              SizedBox(height: (hasLyrics ? 16 : 14) * scale),
              _buildExposedLyricsPreview(
                context,
                isActive: isActive,
                scale: scale,
              ),
              const Spacer(),
              _buildMetadataBlock(context, track, scale),
              SizedBox(height: 12 * scale),
              _buildFiveActionButtons(context, track, scale),
              SizedBox(height: 6 * scale),
            ],
          ),
        );
      },
    );

    final Widget inlineLyricsStage = ValueListenableBuilder<double>(
      valueListenable: _lyricsPageProgress,
      builder: (context, t, child) {
        return Opacity(
          opacity: (0.2 + t * 0.8).clamp(0.0, 1.0),
          child: child,
        );
      },
      child: Column(
        children: [
          Expanded(
            child: KaraokeLyricView(
              lyrics: store.currentLyrics,
              positionProvider: () => store.livePositionMs,
              offsetMs: store.bridge.lyricOffsetMs,
              accentColor: store.accentColor,
              onSeekToMs: store.seekTo,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: store.importExternalLyric,
                  child: Text(
                    store.lyricSourceLabel.isNotEmpty
                        ? '词 ${store.lyricSourceLabel}'
                        : '导入歌词',
                    style: TextStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.52),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                _buildCapsuleButton(
                  label: '调轴/全屏',
                  onTap: _openFullLyrics,
                ),
                const SizedBox(width: 8),
                _buildCapsuleButton(
                  label: '封面',
                  onTap: _animateToCoverTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: isActive
              ? PageView(
                  controller: _contentPageController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() {
                      _isOnLyricsTab = page == 1;
                    });
                  },
                  children: [
                    coverStage,
                    inlineLyricsStage,
                  ],
                )
              : coverStage,
        ),
        _buildBottomRegion(
          context,
          track,
          isActive: isActive,
          scale: scale,
          bottomInset: bottomInset,
          isGlassBar: isGlassBar,
        ),
      ],
    );
  }

  Widget _buildExposedLyricsPreview(
    BuildContext context, {
    required bool isActive,
    required double scale,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _animateToLyricsTab,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 0),
        child: SizedBox(
          width: double.infinity,
          child: ValueListenableBuilder<int>(
            valueListenable: _livePosNotifier,
            builder: (context, livePos, _) {
              final effectivePos = livePos + store.bridge.lyricOffsetMs;
              final window = isActive
                  ? _fiveLineLyricWindow(livePos)
                  : (activeIndex: -1, lines: const <LyricLine?>[]);
              final hasLyrics = window.activeIndex >= 0 && window.lines.isNotEmpty;

              if (!hasLyrics) {
                return Text(
                  '暂无歌词 · 左滑封面或轻触查看歌词',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5 * scale,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                );
              }

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: SizedBox(
                  key: ValueKey<int>(window.activeIndex),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(5, (slot) {
                      final lineObj = window.lines[slot];
                      final lineText = lineObj?.text.trim() ?? '';
                      if (lineObj == null || lineText.isEmpty) {
                        return const SizedBox(height: 2);
                      }
                      final bool isCenter = slot == 2;
                      final bool isNear = slot == 1 || slot == 3;
                      if (isCenter) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.2),
                          child: KaraokeSingleLineSweep(
                            line: lineObj,
                            positionMs: effectivePos,
                            style: TextStyle(
                              fontSize: 17.5 * scale,
                              fontWeight: FontWeight.w700,
                              height: 1.28,
                            ),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withValues(alpha: 0.44),
                            glowColor: store.accentColor.withValues(alpha: 0.45),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.4),
                        child: Text(
                          lineText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5 * scale,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(
                              alpha: isNear ? 0.56 : 0.44,
                            ),
                            height: 1.24,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataBlock(BuildContext context, Track track, double scale) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildCapsuleButton(
                label: '高品质',
                onTap: () => showSoundEffectSheet(context, store),
              ),
              const SizedBox(width: 6),
              _buildCapsuleButton(
                label: '原声',
                onTap: _animateToLyricsTab,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openArtistTracks(track),
                child: CustomPaint(
                  painter: _DottedUnderlinePainter(
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5 * scale,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                '  |  ',
                style: TextStyle(
                  fontSize: 14 * scale,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              Flexible(
                child: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15 * scale,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapsuleButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 0.9,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _buildFiveActionButtons(
    BuildContext context,
    Track track,
    double scale,
  ) {
    final isFav = store.isFavorite(track.id);
    final btnHeight = 52 * scale;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: _GlassActionSquare(
              height: btnHeight,
              onTap: () => store.toggleFavorite(track),
              child: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 24 * scale,
                color: isFav ? const Color(0xFFFF5A7E) : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlassActionSquare(
              height: btnHeight,
              onTap: store.shareCurrentTrack,
              child: Icon(
                Icons.ios_share_rounded,
                size: 22 * scale,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlassActionSquare(
              height: btnHeight,
              onTap: () => showQueueSheet(context, store),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 24 * scale,
                    color: Colors.white,
                  ),
                  Positioned(
                    top: -7,
                    right: -11,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A463E).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${store.queue.length}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.05,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlassActionSquare(
              height: btnHeight,
              onTap: () {
                store.refreshRecommendQueue();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已为你刷新智能漫游推荐队列'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 22 * scale,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlassActionSquare(
              height: btnHeight,
              onTap: () => showMoreRoamSheet(
                context,
                store,
                onOpenLyrics: _openFullLyrics,
                onOpenIsland: _openIslandSettings,
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 24 * scale,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRegion(
    BuildContext context,
    Track track, {
    required bool isActive,
    required double scale,
    required double bottomInset,
    required bool isGlassBar,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInlineProgressBar(track, isActive: isActive, scale: scale),
          if (store.bottomBarStyle == BottomBarStyle.native && !store.pureMode)
            _buildNativeBottomRow(scale)
          else if (isGlassBar && !store.pureMode)
            const SizedBox(height: 76)
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildInlineProgressBar(
    Track track, {
    required bool isActive,
    required double scale,
  }) {
    final durationMs = math.max(1, track.durationMs);
    final rawPos = isActive
        ? (_isDraggingSlider ? _dragPositionMs.round() : store.positionMs)
        : 0;
    final clampedPos = rawPos.clamp(0, durationMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          SizedBox(
            width: 40 * scale,
            child: Text(
              _formatDuration(clampedPos),
              style: TextStyle(
                fontSize: 12.5 * scale,
                color: Colors.white.withValues(alpha: 0.75),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 28 * scale,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.16),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 0,
                    pressedElevation: 2,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
                  trackShape: const _FullWidthTrackShape(),
                ),
                child: Slider(
                  min: 0,
                  max: durationMs.toDouble(),
                  value: clampedPos.toDouble(),
                  onChangeStart: (v) {
                    setState(() {
                      _isDraggingSlider = true;
                      _dragPositionMs = v;
                    });
                  },
                  onChanged: (v) {
                    setState(() {
                      _dragPositionMs = v;
                    });
                  },
                  onChangeEnd: (v) {
                    setState(() {
                      _isDraggingSlider = false;
                    });
                    store.seekTo(v.round());
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40 * scale,
            child: Text(
              _formatDuration(durationMs),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5 * scale,
                color: Colors.white.withValues(alpha: 0.75),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeBottomRow(double scale) {
    final playButtonSize = 54 * scale;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenDiscover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                '发现',
                style: TextStyle(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: store.togglePlayPause,
            child: Container(
              width: playButtonSize,
              height: playButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.6,
                ),
              ),
              child: Center(
                child: Icon(
                  store.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 28 * scale,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenMine,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                '我的',
                style: TextStyle(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImmersiveStyleBody(
    BuildContext context,
    Track track,
    double scale,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isGlassBar = store.bottomBarStyle == BottomBarStyle.glass;
    final lyricLine = _currentLyricLine(store.positionMs);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: store.togglePlayPause,
                  onHorizontalDragStart: _onCoverHorizontalDragStart,
                  onHorizontalDragUpdate: _onCoverHorizontalDragUpdate,
                  onHorizontalDragEnd: _onCoverHorizontalDragEnd,
                  child: Container(
                    width: 240 * scale,
                    height: 240 * scale,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.42),
                          blurRadius: 34,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: CoverArtWidget(
                      track: track,
                      localPath: store.coverPathFor(track),
                      accentColor: store.accentColor,
                      size: 260,
                      borderRadius: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _openFullLyrics,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      lyricLine ?? '轻触查看完整歌词 · 支持外挂歌词导入',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5 * scale,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        _buildMetadataBlock(context, track, scale),
        SizedBox(height: 14 * scale),
        _buildFiveActionButtons(context, track, scale),
        SizedBox(height: 10 * scale),
        _buildBottomRegion(
          context,
          track,
          isActive: true,
          scale: scale,
          bottomInset: bottomInset,
          isGlassBar: isGlassBar,
        ),
      ],
    );
  }

  Widget _buildRecommendStyleBody(
    BuildContext context,
    Track track,
    double scale,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isGlassBar = store.bottomBarStyle == BottomBarStyle.glass;
    final lyricLine = _currentLyricLine(store.positionMs);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
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
                          color: store.accentColor.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            SizedBox(width: 5),
                            Text(
                              '每日漫游推荐',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: store.importExternalLyric,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.lyrics_outlined, size: 16),
                        label: const Text('导入词', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: GestureDetector(
                          onTap: store.togglePlayPause,
                          onHorizontalDragStart: _onCoverHorizontalDragStart,
                          onHorizontalDragUpdate: _onCoverHorizontalDragUpdate,
                          onHorizontalDragEnd: _onCoverHorizontalDragEnd,
                          child: CoverArtWidget(
                            track: track,
                            localPath: store.coverPathFor(track),
                            accentColor: store.accentColor,
                            size: 260,
                            borderRadius: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (lyricLine != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        lyricLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: store.playPrevious,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: store.refreshRecommendQueue,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('换一批'),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: store.playNext,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildMetadataBlock(context, track, scale),
        SizedBox(height: 12 * scale),
        _buildFiveActionButtons(context, track, scale),
        SizedBox(height: 8 * scale),
        _buildBottomRegion(
          context,
          track,
          isActive: true,
          scale: scale,
          bottomInset: bottomInset,
          isGlassBar: isGlassBar,
        ),
      ],
    );
  }
}

class _GlassActionSquare extends StatelessWidget {
  const _GlassActionSquare({
    required this.height,
    required this.onTap,
    required this.child,
  });

  final double height;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _DottedUnderlinePainter extends CustomPainter {
  const _DottedUnderlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.fill;

    const dotWidth = 2.0;
    const gap = 3.0;
    final y = size.height - 1.0;

    double x = 0;
    while (x + dotWidth <= size.width) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y - 0.7, dotWidth, 1.4),
          const Radius.circular(0.7),
        ),
        paint,
      );
      x += dotWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedUnderlinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _FullWidthTrackShape extends RoundedRectSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.5;
    final trackLeft = offset.dx + 6;
    final trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = math.max(0.0, parentBox.size.width - 12);
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

