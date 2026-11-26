import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/services/native_bridge.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    this.bridge,
    this.track,
    this.lyrics,
    this.accentColor = const Color(0xFF4CE0B3),
  });

  final NativePlayerBridge? bridge;
  final Track? track;
  final ParsedLyric? lyrics;
  final Color accentColor;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _haloController;
  Timer? _uiTimer;

  int _currentPage = 0;
  double? _dragPositionMs;
  int _localOffsetMs = 0;
  bool _floatingLyricEnabled = false;

  NativePlayerBridge get _bridge => widget.bridge ?? NativePlayerBridge.instance;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _localOffsetMs = _bridge.lyricOffsetMs;
    _floatingLyricEnabled = _bridge.floatingLyricEnabled;

    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _haloController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Track? get _activeTrack => widget.track ?? _bridge.currentTrack;

  ParsedLyric? get _activeLyrics => widget.lyrics ?? _bridge.currentLyrics;

  int get _positionMs => _bridge.positionMs;

  int get _durationMs {
    final trackDuration = _activeTrack?.durationMs ?? 0;
    return math.max(1, trackDuration > 0 ? trackDuration : _bridge.durationMs);
  }

  bool get _isPlaying => _bridge.isPlaying;

  void _togglePage() {
    final target = _currentPage == 0 ? 1 : 0;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  String _formatBadgeLabel(ParsedLyric? lyric) {
    if (lyric == null) return 'AUDIO';
    switch (lyric.format) {
      case LyricFormat.yrcQrc:
        return 'YRC/QRC 逐字';
      case LyricFormat.krc:
        return 'KRC 逐字';
      case LyricFormat.enhancedLrc:
        return 'eLRC 逐字';
      case LyricFormat.plainLrc:
        return 'LRC';
      case LyricFormat.plainText:
        return 'TEXT';
    }
  }

  String _islandModeLabel(LyricIslandMode mode) {
    switch (mode) {
      case LyricIslandMode.superLyric:
        return 'SuperLyric';
      case LyricIslandMode.lyricInfo:
        return 'lyricInfo';
      case LyricIslandMode.ticker:
        return 'Ticker';
      default:
        return '灵动岛';
    }
  }

  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 359999);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  List<String> _currentTwoPreviewLines() {
    final lines = _activeLyrics?.lines;
    if (lines == null || lines.isEmpty) {
      return const <String>['纯音乐 · 沉浸聆听', ''];
    }
    final effectivePos = _positionMs + _localOffsetMs;
    int idx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startMs <= effectivePos) {
        idx = i;
      } else {
        break;
      }
    }
    final first = lines[idx].text;
    final second = idx + 1 < lines.length ? lines[idx + 1].text : '';
    return <String>[first, second];
  }

  Future<void> _openIslandSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IslandSettingsPage(bridge: _bridge),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _showOffsetSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        int tempOffset = _localOffsetMs;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28.0),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141821).withValues(alpha: 0.88),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 38.0,
                        height: 4.0,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      ),
                      const SizedBox(height: 18.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            '歌词时间微调',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${tempOffset >= 0 ? '+' : ''}${tempOffset}ms',
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 15.0,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14.0),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: widget.accentColor,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                          thumbColor: Colors.white,
                          overlayColor: widget.accentColor.withValues(alpha: 0.22),
                          trackHeight: 3.5,
                        ),
                        child: Slider(
                          min: -500,
                          max: 500,
                          divisions: 20,
                          value: tempOffset.toDouble().clamp(-500, 500),
                          onChanged: (double val) {
                            final rounded = val.round();
                            setSheetState(() => tempOffset = rounded);
                            setState(() => _localOffsetMs = rounded);
                            _bridge.setLyricOffset(rounded);
                          },
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _OffsetQuickButton(
                            label: '-50ms',
                            onTap: () {
                              final next = (tempOffset - 50).clamp(-500, 500);
                              setSheetState(() => tempOffset = next);
                              setState(() => _localOffsetMs = next);
                              _bridge.setLyricOffset(next);
                            },
                          ),
                          _OffsetQuickButton(
                            label: '归零',
                            accentColor: widget.accentColor,
                            onTap: () {
                              setSheetState(() => tempOffset = 0);
                              setState(() => _localOffsetMs = 0);
                              _bridge.setLyricOffset(0);
                            },
                          ),
                          _OffsetQuickButton(
                            label: '+50ms',
                            onTap: () {
                              final next = (tempOffset + 50).clamp(-500, 500);
                              setSheetState(() => tempOffset = next);
                              setState(() => _localOffsetMs = next);
                              _bridge.setLyricOffset(next);
                            },
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
      },
    );
  }

  void _toggleFloatingLyric() {
    final next = !_floatingLyricEnabled;
    setState(() {
      _floatingLyricEnabled = next;
    });
    _bridge.setFloatingLyricEnabled(next);
  }

  @override
  Widget build(BuildContext context) {
    final track = _activeTrack;
    final lyrics = _activeLyrics;
    final accent = widget.accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: Stack(
        children: <Widget>[
          _SodaDynamicBackground(
            animation: _haloController,
            accentColor: accent,
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 48.0, sigmaY: 48.0),
            child: Container(
              color: Colors.black.withValues(alpha: 0.32),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(lyrics, accent),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (int index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    children: <Widget>[
                      _buildCoverStage(track, accent),
                      KaraokeLyricView(
                        lyrics: lyrics,
                        positionProvider: () => _positionMs,
                        offsetMs: _localOffsetMs,
                        accentColor: accent,
                        onSeekToMs: (int ms) => _bridge.seekTo(ms),
                      ),
                    ],
                  ),
                ),
                _buildPageIndicator(accent),
                const SizedBox(height: 10.0),
                _buildBottomControls(track, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ParsedLyric? lyrics, Color accent) {
    final islandMode = _bridge.islandMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: <Widget>[
          _GlassIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10.0),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 5.0,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              _formatBadgeLabel(lyrics),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _openIslandSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 12.0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 7.0,
                    height: 7.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: accent.withValues(alpha: 0.8),
                          blurRadius: 6.0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7.0),
                  Text(
                    _islandModeLabel(islandMode),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15.0,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverStage(Track? track, Color accent) {
    final preview = _currentTwoPreviewLines();
    final coverUrl = track?.albumArtUri;

    return GestureDetector(
      onTap: _togglePage,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _haloController,
              builder: (BuildContext context, Widget? child) {
                final pulse = _haloController.value;
                return Container(
                  width: 268.0,
                  height: 268.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32.0),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.16 + 0.14 * pulse),
                        blurRadius: 42.0 + 18.0 * pulse,
                        spreadRadius: 2.0 + 4.0 * pulse,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28.0,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (coverUrl != null && coverUrl.isNotEmpty)
                      Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _CoverPlaceholder(accentColor: accent),
                      )
                    else
                      _CoverPlaceholder(accentColor: accent),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32.0),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30.0),
            Text(
              preview[0],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent.withValues(alpha: 0.95),
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6.0),
            Text(
              preview[1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageIndicator(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(2, (int index) {
        final selected = _currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          width: selected ? 18.0 : 6.0,
          height: 6.0,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(3.0),
          ),
        );
      }),
    );
  }

  Widget _buildBottomControls(Track? track, Color accent) {
    final durationMs = _durationMs.toDouble();
    final currentPos = (_dragPositionMs ?? _positionMs.toDouble())
        .clamp(0.0, durationMs);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 4.0, 24.0, 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            track?.title ?? '未在播放',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            track?.artist ?? 'SodaPulse',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 14.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14.0),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
              thumbColor: Colors.white,
              overlayColor: accent.withValues(alpha: 0.20),
              trackHeight: 3.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              min: 0.0,
              max: durationMs,
              value: currentPos,
              onChanged: (double value) {
                setState(() {
                  _dragPositionMs = value;
                });
              },
              onChangeEnd: (double value) {
                setState(() {
                  _dragPositionMs = null;
                });
                _bridge.seekTo(value.round());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _formatDuration(currentPos.round()),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.54),
                    fontSize: 11.5,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  _formatDuration(_durationMs),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.54),
                    fontSize: 11.5,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _GlassIconButton(
                icon: Icons.tune_rounded,
                tooltip: '歌词偏移微调',
                isActive: _localOffsetMs != 0,
                activeColor: accent,
                onTap: _showOffsetSheet,
              ),
              IconButton(
                onPressed: _bridge.skipToPrevious,
                iconSize: 34.0,
                color: Colors.white.withValues(alpha: 0.9),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              GestureDetector(
                onTap: _bridge.togglePlayPause,
                child: Container(
                  width: 66.0,
                  height: 66.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        accent,
                        accent.withValues(alpha: 0.75),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.42),
                        blurRadius: 22.0,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: const Color(0xFF0A0D12),
                    size: 36.0,
                  ),
                ),
              ),
              IconButton(
                onPressed: _bridge.skipToNext,
                iconSize: 34.0,
                color: Colors.white.withValues(alpha: 0.9),
                icon: const Icon(Icons.skip_next_rounded),
              ),
              _GlassIconButton(
                icon: Icons.subtitles_rounded,
                tooltip: '桌面悬浮歌词',
                isActive: _floatingLyricEnabled,
                activeColor: accent,
                onTap: _toggleFloatingLyric,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SodaDynamicBackground extends StatelessWidget {
  const _SodaDynamicBackground({
    required this.animation,
    required this.accentColor,
  });

  final Animation<double> animation;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final t = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF101722),
                    Color(0xFF090C11),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -80 + 28 * t,
              left: -60 + 20 * t,
              child: Container(
                width: 300.0,
                height: 300.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.18 + 0.08 * t),
                ),
              ),
            ),
            Positioned(
              bottom: 60 - 24 * t,
              right: -70 + 18 * t,
              child: Container(
                width: 260.0,
                height: 260.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF5B7FFF).withValues(alpha: 0.14 + 0.06 * t),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accentColor.withValues(alpha: 0.32),
            const Color(0xFF171D29),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 86.0,
          color: Colors.white.withValues(alpha: 0.38),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.isActive = false,
    this.activeColor = const Color(0xFF4CE0B3),
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool isActive;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40.0,
        height: 40.0,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Icon(
          icon,
          size: 20.0,
          color: isActive ? activeColor : Colors.white.withValues(alpha: 0.86),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _OffsetQuickButton extends StatelessWidget {
  const _OffsetQuickButton({
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 9.0),
        decoration: BoxDecoration(
          color: (accentColor ?? Colors.white).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(
            color: (accentColor ?? Colors.white).withValues(alpha: 0.24),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accentColor ?? Colors.white.withValues(alpha: 0.9),
            fontSize: 13.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
