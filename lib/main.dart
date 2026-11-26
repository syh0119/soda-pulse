import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soda_pulse/services/native_bridge.dart';
import 'package:soda_pulse/lyrics/lyric_parser.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/pages/library_page.dart';
import 'package:soda_pulse/ui/pages/player_page.dart';

void main() => runApp(const SodaPulseApp());

class SodaPulseApp extends StatelessWidget {
  const SodaPulseApp({super.key});

  static const Color _seedBlue = Color(0xFF38BDF8);
  static const Color _bgNight = Color(0xFF0B1120);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedBlue,
      brightness: Brightness.dark,
      primary: _seedBlue,
      surface: const Color(0xFF111827),
    );

    return MaterialApp(
      title: 'SodaPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _bgNight,
        appBarTheme: const AppBarTheme(
          backgroundColor: _bgNight,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0F172A),
          indicatorColor: const Color(0x2E38BDF8),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _seedBlue : const Color(0xFF94A3B8),
            );
          }),
        ),
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  final NativePlayerBridge _bridge = NativePlayerBridge();

  int _navIndex = 0;
  List<Track> _queue = <Track>[];
  int _currentIndex = -1;
  bool _scanning = false;
  StreamSubscription<PlaybackState>? _stateSub;
  bool _handlingCompletion = false;

  Track? get _currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _stateSub = _bridge.stateStream.listen(_onPlaybackStateChanged);
    _initAndScan();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _initAndScan() async {
    await _bridge.requestPermissions();
    await _rescanLibrary();
  }

  Future<void> _rescanLibrary() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final scanned = await _bridge.scanLocalAudio();
      if (!mounted) return;
      setState(() {
        _queue = scanned;
        if (_currentIndex >= _queue.length) {
          _currentIndex = _queue.isEmpty ? -1 : 0;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    if (state.isCompleted && !_handlingCompletion && _queue.isNotEmpty) {
      _handlingCompletion = true;
      _playNextTrack().whenComplete(() {
        _handlingCompletion = false;
      });
    }
  }

  Future<void> _playNextTrack() async {
    if (_queue.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % _queue.length;
    await _selectAndPlayTrack(nextIndex);
  }

  Future<void> _selectAndPlayTrack(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final track = _queue[index];
    setState(() => _currentIndex = index);

    final rawLyric = await _bridge.readTrackLyrics(
      filePath: track.filePath,
      uri: track.uri,
    );
    final rawText = (rawLyric['raw'] as String?) ?? '';
    final parsed = LyricParser.parse(
      rawText,
      translationRaw: rawLyric['translation'] as String?,
      romaRaw: rawLyric['roma'] as String?,
      durationMs: track.durationMs,
    );
    final lyricPayload = parsed.lines.isEmpty
        ? null
        : parsed.toNativePayload(
            songId: track.id,
            songName: track.title,
            artist: track.artist,
            album: track.album,
            durationMs: track.durationMs,
            rawSource: rawText,
          );
    await _bridge.loadAndPlay(
      track,
      parsedLyrics: parsed,
      lyricPayload: lyricPayload,
    );
  }

  Future<void> _playDemo() async {
    final demoTrack = await _bridge.prepareDemoAudio();
    final existingIdx = _queue.indexWhere((t) => t.id == demoTrack.id);
    int targetIndex;
    if (existingIdx >= 0) {
      targetIndex = existingIdx;
    } else {
      setState(() {
        _queue = <Track>[demoTrack, ..._queue];
      });
      targetIndex = 0;
    }

    setState(() => _currentIndex = targetIndex);
    final demoParsed = LyricParser.demoLyrics();
    final demoPayload = demoParsed.toNativePayload(
      songId: demoTrack.id,
      songName: demoTrack.title,
      artist: demoTrack.artist,
      album: demoTrack.album,
      durationMs: demoTrack.durationMs,
      rawSource: '',
    );
    await _bridge.loadAndPlay(
      demoTrack,
      parsedLyrics: demoParsed,
      lyricPayload: demoPayload,
    );
    if (mounted) {
      _openPlayerPage();
    }
  }

  void _openPlayerPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          bridge: _bridge,
          track: _currentTrack,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.bubble_chart_rounded,
              color: Color(0xFF38BDF8),
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'SodaPulse',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
          ],
        ),
        actions: [
          if (_currentTrack != null)
            IconButton(
              onPressed: _openPlayerPage,
              tooltip: '正在播放',
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          IconButton(
            onPressed: () => setState(() => _navIndex = 1),
            tooltip: '灵动岛与逐字设置',
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          LibraryPage(
            bridge: _bridge,
            queue: _queue,
            currentTrack: _currentTrack,
            onSelectTrack: (index) => _selectAndPlayTrack(index),
            onPlayDemo: _playDemo,
            onRescan: _rescanLibrary,
            scanning: _scanning,
          ),
          IslandSettingsPage(bridge: _bridge),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: '曲库',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.settings_input_component_rounded),
            label: '灵动岛',
          ),
        ],
      ),
    );
  }
}
