import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';
import 'package:soda_pulse/ui/widgets/star_skin_bg.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.store});

  final AppStore store;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  Timer? _lyricTimer;

  @override
  void initState() {
    super.initState();
    _lyricTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && widget.store.isPlaying) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lyricTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SodaTheme.bgDeep,
      body: StarSkinBackground(
        accentColor: widget.store.accentColor,
        skin: widget.store.skin,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              return CarLayout(
                store: widget.store,
                onExit: () => Navigator.of(context).maybePop(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class CarLayout extends StatelessWidget {
  const CarLayout({
    super.key,
    required this.store,
    required this.onExit,
  });

  final AppStore store;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    return OrientationBuilder(
      builder: (context, builderOrientation) {
        final isLandscape = orientation == Orientation.landscape ||
            builderOrientation == Orientation.landscape;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 32 : 24,
            vertical: isLandscape ? 20 : 16,
          ),
          child: Column(
            children: [
              _buildTopBar(context),
              const SizedBox(height: 16),
              Expanded(
                child: isLandscape
                    ? _buildLandscapeBody(context)
                    : _buildPortraitBody(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_car_filled_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '驾驶模式',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onExit,
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '退出驾驶模式',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = (constraints.maxWidth * 0.68).clamp(200.0, 320.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildCover(coverSize),
            const SizedBox(height: 16),
            _buildTrackInfo(context, centered: true),
            const SizedBox(height: 16),
            _buildLyricsBlock(context, centered: true),
            const SizedBox(height: 20),
            _buildControls(context),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildLandscapeBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = (constraints.maxHeight * 0.78).clamp(200.0, 340.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildCover(coverSize),
            const SizedBox(width: 36),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTrackInfo(context, centered: false),
                  _buildLyricsBlock(context, centered: false),
                  _buildControls(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCover(double size) {
    final track = store.currentTrack;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.48),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: CoverArtWidget(
          track: track,
          size: size,
          accentColor: store.accentColor,
        ),
      ),
    );
  }

  Widget _buildTrackInfo(BuildContext context, {required bool centered}) {
    final track = store.currentTrack;
    final align = centered ? TextAlign.center : TextAlign.start;
    final crossAlign =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: crossAlign,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track?.title ?? '未在播放',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          track?.artist ?? '选择一首歌曲开始驾驶之旅',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsBlock(BuildContext context, {required bool centered}) {
    final currentLine = store.currentLyricLine?.text ?? '';
    final nextLine = store.nextLyricLine?.text ?? '';
    final align = centered ? TextAlign.center : TextAlign.start;
    final crossAlign =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: crossAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              currentLine.isNotEmpty ? currentLine : '♪ 纯音乐 / 暂无歌词',
              key: ValueKey<String>(currentLine),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: TextStyle(
                color: accent,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.28,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final isPlaying = store.isPlaying;
    final isFavorite = store.isCurrentFavorite;
    final accent = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _DriveActionButton(
          size: 60,
          icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: isFavorite ? const Color(0xFFFF4D6D) : Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          onTap: () {
            final t = store.currentTrack;
            if (t != null) store.toggleFavorite(t);
          },
          tooltip: '喜欢',
        ),
        _DriveActionButton(
          size: 64,
          icon: Icons.skip_previous_rounded,
          iconSize: 36,
          iconColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          onTap: () => store.previous(),
          tooltip: '上一首',
        ),
        _DriveActionButton(
          size: 84,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          iconSize: 48,
          iconColor: Colors.black,
          backgroundColor: accent,
          onTap: () => store.togglePlay(),
          tooltip: isPlaying ? '暂停' : '播放',
          elevated: true,
        ),
        _DriveActionButton(
          size: 64,
          icon: Icons.skip_next_rounded,
          iconSize: 36,
          iconColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          onTap: () => store.next(),
          tooltip: '下一首',
        ),
      ],
    );
  }
}

class _DriveActionButton extends StatelessWidget {
  const _DriveActionButton({
    required this.size,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.onTap,
    required this.tooltip,
    this.iconSize = 30,
    this.elevated = false,
  });

  final double size;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final VoidCallback onTap;
  final String tooltip;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: Colors.white.withValues(alpha: elevated ? 0.32 : 0.18),
                width: 1.4,
              ),
              boxShadow: elevated
                  ? [
                      BoxShadow(
                        color: backgroundColor.withValues(alpha: 0.42),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
