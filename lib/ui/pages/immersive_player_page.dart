import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/ui/pages/full_lyrics_page.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/sheets/player_sheets.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';
import 'package:soda_pulse/ui/widgets/star_skin_bg.dart';

enum _MoreMenuAction {
  importLyric,
  addToPlaylist,
  toggleDesktopLyric,
  shareTrack,
}

class ImmersivePlayerPage extends StatefulWidget {
  const ImmersivePlayerPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ImmersivePlayerPage> createState() => _ImmersivePlayerPageState();
}

class _ImmersivePlayerPageState extends State<ImmersivePlayerPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late final AnimationController _breathController;
  Timer? _uiTimer;
  double? _dragPositionMs;
  bool _isSyncingPage = false;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.store.queue.isEmpty
        ? 0
        : widget.store.currentIndex.clamp(0, widget.store.queue.length - 1);
    _pageController = PageController(initialPage: initialIndex);
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
    widget.store.addListener(_onStoreChanged);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (widget.store.isPlaying && _dragPositionMs == null) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant ImmersivePlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
      _syncPageController();
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    widget.store.removeListener(_onStoreChanged);
    _pageController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncPageController();
    setState(() {});
  }

  void _syncPageController() {
    final store = widget.store;
    if (store.queue.isEmpty || !_pageController.hasClients) return;
    final target = store.currentIndex.clamp(0, store.queue.length - 1);
    final currentPage = _pageController.page?.round();
    if (currentPage != target) {
      _isSyncingPage = true;
      _pageController
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        _isSyncingPage = false;
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

  void _openDriveMode() {
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

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final accent = store.accentColor;

    return StarSkinBackground(
      accentColor: accent,
      skin: store.skin,
      child: SafeArea(
        child: store.queue.isEmpty
            ? _buildEmptyHero(context, store, accent)
            : _buildPlayerContent(context, store, accent),
      ),
    );
  }

  Widget _buildEmptyHero(
    BuildContext context,
    AppStore store,
    Color accent,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.55),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '欢迎来到 SodaPulse',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '本地无损音质 · 逐字卡拉OK歌词 · ColorOS 17 灵动岛联动',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: store.playDemo,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    '一键演示 (ColorOS 17 逐字/灵动岛实测)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: store.rescanLibrary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: const Text(
                    '扫描本地音乐',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent(
    BuildContext context,
    AppStore store,
    Color accent,
  ) {
    final track = store.currentTrack ?? store.queue[store.currentIndex];

    return Column(
      children: [
        if (store.pureMode)
          _buildPureTopBar(store)
        else
          _buildTopBar(context, store, accent),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: store.queue.length,
            onPageChanged: (idx) {
              if (!_isSyncingPage && idx != store.currentIndex) {
                store.playTrackFromQueue(idx);
              }
            },
            itemBuilder: (context, index) {
              final itemTrack = store.queue[index];
              if (store.pureMode ||
                  store.playerStyle == PlayerStyle.immersive) {
                return _buildImmersivePage(
                  context,
                  store,
                  itemTrack,
                  accent,
                );
              }
              return _buildFreeStylePage(
                context,
                store,
                itemTrack,
                accent,
              );
            },
          ),
        ),
        if (store.pureMode)
          _buildPureControls(store, accent)
        else
          _buildNormalBottomControls(context, store, track, accent),
      ],
    );
  }

  Widget _buildPureTopBar(AppStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _GlassPill(
            onTap: () => store.setPureMode(false),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  '退出纯净',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppStore store,
    Color accent,
  ) {
    final layoutLabel =
        store.playerStyle == PlayerStyle.immersive ? '沉浸式' : '封面在上';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          _GlassPill(
            onTap: () => showSkinAndLayoutSheet(context, store),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers_rounded, color: accent, size: 16),
                const SizedBox(width: 6),
                Text(
                  layoutLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 16,
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '驾驶模式',
            onPressed: _openDriveMode,
            icon: Icon(
              Icons.directions_car_rounded,
              color: Colors.white.withValues(alpha: 0.88),
              size: 22,
            ),
          ),
          const SizedBox(width: 4),
          _GlassPill(
            onTap: _openIslandSettings,
            backgroundColor: accent.withValues(alpha: 0.22),
            borderColor: accent.withValues(alpha: 0.45),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '灵动岛',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _GlassPill(
            onTap: () => store.setPureMode(!store.pureMode),
            child: Text(
              '纯净',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImmersivePage(
    BuildContext context,
    AppStore store,
    Track track,
    Color accent,
  ) {
    final badgeText = _formatBadgeLabel(store.currentLyrics.format);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              if (store.pureMode) {
                store.setPureMode(false);
              } else {
                _openFullLyrics();
              }
            },
            child: AnimatedBuilder(
              animation: _breathController,
              builder: (context, child) {
                final wave = math.sin(_breathController.value * math.pi);
                final scale = store.isPlaying ? 1.0 + 0.018 * wave : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: CoverArtWidget(
                track: track,
                size: 252,
                accentColor: accent,
                showVinylRing: store.skin == AppSkin.vinyl,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (badgeText != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!store.pureMode) ...[
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _openFullLyrics,
              behavior: HitTestBehavior.opaque,
              child: _buildTwoLineLyricPreview(store, accent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreeStylePage(
    BuildContext context,
    AppStore store,
    Track track,
    Color accent,
  ) {
    final badgeText = _formatBadgeLabel(store.currentLyrics.format);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: _openFullLyrics,
                child: CoverArtWidget(
                  track: track,
                  size: 72,
                  accentColor: accent,
                  showVinylRing: store.skin == AppSkin.vinyl,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: KaraokeLyricView(
            lyrics: store.currentLyrics,
            positionProvider: () => store.positionMs,
            offsetMs: store.bridge.lyricOffsetMs,
            accentColor: accent,
            onSeekToMs: store.seekTo,
          ),
        ),
      ],
    );
  }

  Widget _buildTwoLineLyricPreview(AppStore store, Color accent) {
    final lines = store.currentLyrics.lines;
    if (lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          '暂无歌词 · 点击进入全屏歌词页',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
      );
    }

    final effectiveMs = store.positionMs + store.bridge.lyricOffsetMs;
    var activeIdx = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startMs <= effectiveMs) {
        activeIdx = i;
      } else {
        break;
      }
    }

    final currentLine = lines[activeIdx].text;
    final nextLine =
        activeIdx + 1 < lines.length ? lines[activeIdx + 1].text : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nextLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPureControls(AppStore store, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: store.playPrevious,
            iconSize: 34,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          _PlayPauseCircleButton(
            isPlaying: store.isPlaying,
            accent: accent,
            onTap: store.togglePlayPause,
          ),
          IconButton(
            onPressed: store.playNext,
            iconSize: 34,
            color: Colors.white,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBottomControls(
    BuildContext context,
    AppStore store,
    Track track,
    Color accent,
  ) {
    final durationMs = math.max(1, track.durationMs);
    final currentPosMs = (_dragPositionMs ?? store.positionMs.toDouble())
        .clamp(0.0, durationMs.toDouble());

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionIconButton(
                icon: store.isFavorite(track.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: store.isFavorite(track.id)
                    ? const Color(0xFFFF4D6D)
                    : Colors.white.withValues(alpha: 0.85),
                label: '喜欢',
                onTap: () => store.toggleFavorite(track),
              ),
              _ActionIconButton(
                icon: Icons.equalizer_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                label: '音效',
                onTap: () => showSoundEffectSheet(context, store),
              ),
              _ActionIconButton(
                icon: Icons.timer_outlined,
                color: Colors.white.withValues(alpha: 0.85),
                label: '定时/倍速',
                onTap: () => showSleepAndSpeedSheet(context, store),
              ),
              _ActionIconButton(
                icon: Icons.queue_music_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                label: '队列',
                onTap: () => showQueueSheet(context, store),
              ),
              PopupMenuButton<_MoreMenuAction>(
                tooltip: '更多',
                color: const Color(0xFF1C1F2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                onSelected: (action) =>
                    _handleMoreAction(context, store, track, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _MoreMenuAction.importLyric,
                    child: Row(
                      children: [
                        Icon(Icons.subtitles_outlined,
                            color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Text('导入外部歌词', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MoreMenuAction.addToPlaylist,
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Text('加入歌单', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _MoreMenuAction.toggleDesktopLyric,
                    child: Row(
                      children: [
                        Icon(
                          store.desktopLyricEnabled
                              ? Icons.closed_caption_rounded
                              : Icons.closed_caption_off_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          store.desktopLyricEnabled
                              ? '关闭桌面悬浮歌词'
                              : '开启桌面悬浮歌词',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MoreMenuAction.shareTrack,
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Text('分享歌曲', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '更多',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              thumbColor: Colors.white,
              overlayColor: accent.withValues(alpha: 0.25),
            ),
            child: Slider(
              min: 0,
              max: durationMs.toDouble(),
              value: currentPosMs,
              onChanged: (val) {
                setState(() {
                  _dragPositionMs = val;
                });
              },
              onChangeEnd: (val) {
                setState(() {
                  _dragPositionMs = null;
                });
                store.seekTo(val.round());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  SodaTheme.formatDuration(currentPosMs.round()),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  SodaTheme.formatDuration(track.durationMs),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: '播放模式',
                onPressed: store.cyclePlayMode,
                icon: Icon(
                  _playModeIcon(store.playMode),
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 24,
                ),
              ),
              IconButton(
                tooltip: '上一首',
                onPressed: store.playPrevious,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              _PlayPauseCircleButton(
                isPlaying: store.isPlaying,
                accent: accent,
                onTap: store.togglePlayPause,
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: store.playNext,
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              IconButton(
                tooltip: '歌词页',
                onPressed: _openFullLyrics,
                icon: Icon(
                  Icons.lyrics_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMoreAction(
    BuildContext context,
    AppStore store,
    Track track,
    _MoreMenuAction action,
  ) {
    switch (action) {
      case _MoreMenuAction.importLyric:
        store.importExternalLyric();
        break;
      case _MoreMenuAction.addToPlaylist:
        showAddToPlaylistSheet(context, store, track);
        break;
      case _MoreMenuAction.toggleDesktopLyric:
        store.toggleDesktopLyric();
        break;
      case _MoreMenuAction.shareTrack:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已准备分享: ${track.title} - ${track.artist}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
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
        return Icons.auto_awesome_rounded;
    }
  }

  String? _formatBadgeLabel(LyricFormat format) {
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
        return null;
    }
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.onTap,
    required this.child,
    this.backgroundColor,
    this.borderColor,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseCircleButton extends StatelessWidget {
  const _PlayPauseCircleButton({
    required this.isPlaying,
    required this.accent,
    required this.onTap,
  });

  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent,
              accent.withValues(alpha: 0.7),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}
