import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/discover_page.dart';
import 'package:soda_pulse/ui/pages/immersive_player_page.dart';
import 'package:soda_pulse/ui/pages/mine_page.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  void _openDiscover({bool openSearch = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => DiscoverPage(
          store: widget.store,
          openSearchOnStart: openSearch,
          onOpenPlayer: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
  }

  void _openMine() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => MinePage(
          store: widget.store,
          onOpenPlayer: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final hideNavBar = widget.store.pureMode;
        final isGlassBar = widget.store.bottomBarStyle == BottomBarStyle.glass;
        final startupToast = widget.store.startupPluginToast;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          extendBody: true,
          backgroundColor: const Color(0xFF0A0D0E),
          body: Stack(
            children: [
              ImmersivePlayerPage(
                store: widget.store,
                onOpenDiscover: () => _openDiscover(openSearch: false),
                onOpenMine: _openMine,
                onOpenSearch: () => _openDiscover(openSearch: true),
              ),
              if (startupToast != null)
                Positioned(
                  right: 16,
                  bottom: bottomInset + (hideNavBar ? 24 : 96),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 280),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13171A).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: widget.store.accentColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.extension_rounded,
                              size: 14,
                              color: widget.store.accentColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              startupToast,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!hideNavBar && isGlassBar)
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: bottomInset + 10,
                  child: _GlassBottomBar(
                    accent: widget.store.accentColor,
                    onOpenDiscover: () => _openDiscover(openSearch: false),
                    onTogglePlay: widget.store.togglePlayPause,
                    isPlaying: widget.store.isPlaying,
                    onOpenMine: _openMine,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GlassBottomBar extends StatelessWidget {
  const _GlassBottomBar({
    required this.accent,
    required this.onOpenDiscover,
    required this.onTogglePlay,
    required this.isPlaying,
    required this.onOpenMine,
  });

  final Color accent;
  final VoidCallback onOpenDiscover;
  final VoidCallback onTogglePlay;
  final bool isPlaying;
  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(31),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(31),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onOpenDiscover,
                  child: Center(
                    child: Text(
                      '发现',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onTogglePlay,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.88),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onOpenMine,
                  child: Center(
                    child: Text(
                      '我的',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                      ),
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
}
