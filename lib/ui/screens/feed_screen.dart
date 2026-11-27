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
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final track = widget.store.currentTrack;
        final hideNavBar = _tabIndex == 0 && widget.store.pureMode;
        final isGlassBar = widget.store.bottomBarStyle == BottomBarStyle.glass;
        final showMiniPlayer = _tabIndex != 0 && track != null;
        final startupToast = widget.store.startupPluginToast;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              IndexedStack(
                index: _tabIndex,
                children: [
                  ImmersivePlayerPage(store: widget.store),
                  DiscoverPage(
                    store: widget.store,
                    onOpenPlayer: () => setState(() => _tabIndex = 0),
                  ),
                  MinePage(
                    store: widget.store,
                    onOpenPlayer: () => setState(() => _tabIndex = 0),
                  ),
                ],
              ),
              if (showMiniPlayer)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: bottomInset + (isGlassBar ? 86 : 92),
                  child: _MiniPlayerBar(
                    title: track.title,
                    artist: track.artist,
                    isPlaying: widget.store.isPlaying,
                    onTap: () => setState(() => _tabIndex = 0),
                    onTogglePlay: widget.store.togglePlay,
                    onNext: widget.store.next,
                  ),
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
                          color: const Color(0xFF151C2C).withValues(alpha: 0.88),
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
                  left: 24,
                  right: 24,
                  bottom: bottomInset + 12,
                  child: _GlassBottomBar(
                    selectedIndex: _tabIndex,
                    accent: widget.store.accentColor,
                    onSelect: (index) => setState(() => _tabIndex = index),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: (hideNavBar || isGlassBar)
              ? null
              : NavigationBar(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (index) {
                    setState(() => _tabIndex = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.music_note_rounded),
                      label: '听歌',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.explore_rounded),
                      label: '发现',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_rounded),
                      label: '我的',
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
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
  });

  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.music_note_rounded, label: '听歌'),
      (icon: Icons.explore_rounded, label: '发现'),
      (icon: Icons.person_rounded, label: '我的'),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF121826).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onSelect(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.22)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 20,
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: 0.65),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.65),
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
      ),
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.onTap,
    required this.onTogglePlay,
    required this.onNext,
  });

  final String title;
  final String artist;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF151821).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.9),
                          colorScheme.secondary.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onTogglePlay,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: onNext,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
