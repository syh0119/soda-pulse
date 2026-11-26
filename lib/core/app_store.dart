import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/lyrics/lyric_parser.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/plugin/plugin_manager.dart';
import 'package:soda_pulse/services/native_bridge.dart';

enum PlayMode {
  sequence('顺序播放'),
  single('单曲循环'),
  shuffle('随机播放'),
  smart('心动漫游');

  const PlayMode(this.label);
  final String label;
}

enum PlayerStyle {
  immersive('沉浸式'),
  free('封面在上');

  const PlayerStyle(this.label);
  final String label;
}

enum AppSkin {
  star('星河'),
  soda('气泡'),
  vinyl('黑胶'),
  cover('封面取色');

  const AppSkin(this.label);
  final String label;
}

enum RecommendMode {
  balanced('默认模式'),
  familiar('熟悉模式'),
  fresh('新鲜模式');

  const RecommendMode(this.label);
  final String label;
}

class SoundFxPreset {
  const SoundFxPreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.gains,
    required this.preGain,
  });

  final String id;
  final String name;
  final String subtitle;
  final List<double> gains;
  final double preGain;
}

class SoundFxPresets {
  const SoundFxPresets._();

  static const List<SoundFxPreset> all = <SoundFxPreset>[
    SoundFxPreset(
      id: 'flat',
      name: '原声',
      subtitle: '无修饰平直响应',
      gains: <double>[0.0, 0.0, 0.0, 0.0, 0.0],
      preGain: 0.0,
    ),
    SoundFxPreset(
      id: 'vocal',
      name: '人声靠前',
      subtitle: '人声结像清晰',
      gains: <double>[-1.5, 1.0, 3.5, 2.5, 0.5],
      preGain: -1.0,
    ),
    SoundFxPreset(
      id: 'pop',
      name: '流行电音',
      subtitle: '适合流行与电音',
      gains: <double>[3.5, 1.5, -0.5, 2.5, 3.0],
      preGain: -2.0,
    ),
    SoundFxPreset(
      id: 'bass',
      name: '重低音',
      subtitle: '下潜深沉有力',
      gains: <double>[6.0, 3.5, 0.0, -0.5, 1.0],
      preGain: -3.0,
    ),
    SoundFxPreset(
      id: 'aurora',
      name: '极光环绕',
      subtitle: '宽阔声场与空气感',
      gains: <double>[2.0, -1.0, 1.5, 3.5, 4.5],
      preGain: -2.0,
    ),
    SoundFxPreset(
      id: 'night',
      name: '深夜纯净',
      subtitle: '柔和耐听不刺耳',
      gains: <double>[1.5, 1.0, 0.5, -1.5, -2.5],
      preGain: -0.5,
    ),
    SoundFxPreset(
      id: 'custom',
      name: '自定义',
      subtitle: '手动 5 段均衡',
      gains: <double>[0.0, 0.0, 0.0, 0.0, 0.0],
      preGain: 0.0,
    ),
  ];

  static SoundFxPreset byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return all.first;
  }
}

class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final int createdAtMs;

  UserPlaylist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    int? createdAtMs,
  }) {
    return UserPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? List<String>.from(this.trackIds),
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'trackIds': trackIds,
      'createdAtMs': createdAtMs,
    };
  }

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    final rawIds = json['trackIds'];
    return UserPlaylist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '未命名歌单').toString(),
      trackIds: rawIds is List
          ? rawIds.map((e) => e.toString()).toList()
          : <String>[],
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class HistoryEntry {
  const HistoryEntry({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.playedAtMs,
  });

  final String trackId;
  final String title;
  final String artist;
  final int playedAtMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'playedAtMs': playedAtMs,
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      trackId: (json['trackId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      playedAtMs: (json['playedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppStore extends ChangeNotifier {
  AppStore({NativePlayerBridge? bridge})
      : _bridge = bridge ?? NativePlayerBridge();

  static const String _prefsKey = 'soda_pulse_store_v1';
  static const Color _defaultAccent = Color(0xFF38BDF8);

  final NativePlayerBridge _bridge;
  final Random _random = Random();

  StreamSubscription<PlaybackSnapshot>? _stateSub;
  Timer? _ticker;
  int _ticksSinceSave = 0;

  List<Track> _library = <Track>[];
  List<Track> _queue = <Track>[];
  int _currentIndex = -1;
  ParsedLyric _currentLyrics = LyricParser.parse('');
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  bool _scanning = false;

  PlayMode _playMode = PlayMode.sequence;
  PlayerStyle _playerStyle = PlayerStyle.immersive;
  AppSkin _skin = AppSkin.soda;
  RecommendMode _recommendMode = RecommendMode.balanced;

  bool _pureMode = false;
  bool _showTranslation = true;
  bool _showPhonetic = false;
  double _lyricFontScale = 1.0;
  double _playbackSpeed = 1.0;

  Duration? _sleepTimerRemaining;
  bool _sleepAfterCurrentTrack = false;

  final Set<String> _favoriteIds = <String>{};
  final List<UserPlaylist> _playlists = <UserPlaylist>[];
  final List<HistoryEntry> _history = <HistoryEntry>[];
  final Map<String, int> _playCounts = <String, int>{};
  int _totalListenSeconds = 0;
  final Map<int, int> _hourlyCounts = <int, int>{};
  final List<String> _recentSearches = <String>[];

  String _eqPresetId = 'flat';
  List<double> _eqGains = <double>[0.0, 0.0, 0.0, 0.0, 0.0];
  double _eqPreGain = 0.0;

  final List<MusicSourcePlugin> _plugins = <MusicSourcePlugin>[];
  final Map<String, String> _coverPathCache = <String, String>{};
  final Map<String, Color> _coverColorCache = <String, Color>{};
  final Set<String> _coverLoadingIds = <String>{};

  NativePlayerBridge get bridge => _bridge;
  List<Track> get library => List<Track>.unmodifiable(_library);
  List<Track> get queue => List<Track>.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
  ParsedLyric get currentLyrics => _currentLyrics;
  PlaybackSnapshot get snapshot => _snapshot;
  Color get accentColor {
    final t = currentTrack;
    if (t != null && _coverColorCache.containsKey(t.id)) {
      return _coverColorCache[t.id]!;
    }
    return _defaultAccent;
  }
  int get currentLyricIndex => _currentLyrics.indexAt(positionMs);
  LyricLine? get currentLyricLine {
    final idx = currentLyricIndex;
    if (idx < 0 || idx >= _currentLyrics.lines.length) return null;
    return _currentLyrics.lines[idx];
  }
  LyricLine? get nextLyricLine {
    final idx = currentLyricIndex + 1;
    if (idx < 0 || idx >= _currentLyrics.lines.length) return null;
    return _currentLyrics.lines[idx];
  }
  bool get isCurrentFavorite =>
      currentTrack != null && isFavorite(currentTrack!.id);
  bool get desktopLyricEnabled => _bridge.floatingLyricEnabled;
  int? get sleepTimerMinutes => _sleepTimerRemaining?.inMinutes;
  bool get stopAfterCurrent => _sleepAfterCurrentTrack;
  AppSkin get appSkin => _skin;
  bool get isPlaying => _snapshot.isPlaying;
  int get positionMs => _snapshot.positionMs;
  int get durationMs => _snapshot.durationMs;
  bool get scanning => _scanning;

  PlayMode get playMode => _playMode;
  PlayerStyle get playerStyle => _playerStyle;
  AppSkin get skin => _skin;
  RecommendMode get recommendMode => _recommendMode;

  bool get pureMode => _pureMode;
  bool get showTranslation => _showTranslation;
  bool get showPhonetic => _showPhonetic;
  double get lyricFontScale => _lyricFontScale;
  double get playbackSpeed => _playbackSpeed;

  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  bool get sleepAfterCurrentTrack => _sleepAfterCurrentTrack;

  Set<String> get favoriteIds => Set<String>.unmodifiable(_favoriteIds);
  List<Track> get favoriteTracks =>
      _library.where((t) => _favoriteIds.contains(t.id)).toList();
  List<UserPlaylist> get playlists => List<UserPlaylist>.unmodifiable(_playlists);
  List<HistoryEntry> get history => List<HistoryEntry>.unmodifiable(_history);
  Map<String, int> get playCounts => Map<String, int>.unmodifiable(_playCounts);
  int get totalListenSeconds => _totalListenSeconds;
  Map<int, int> get hourlyCounts => Map<int, int>.unmodifiable(_hourlyCounts);
  List<String> get recentSearches => List<String>.unmodifiable(_recentSearches);

  String get eqPresetId => _eqPresetId;
  List<double> get eqGains => List<double>.unmodifiable(_eqGains);
  double get eqPreGain => _eqPreGain;
  List<MusicSourcePlugin> get plugins =>
      List<MusicSourcePlugin>.unmodifiable(_plugins);
  Map<String, String> get coverPathCache =>
      Map<String, String>.unmodifiable(_coverPathCache);
  Map<String, Color> get coverColorCache =>
      Map<String, Color>.unmodifiable(_coverColorCache);

  Future<void> init() async {
    await _loadPrefs();

    await _stateSub?.cancel();
    _stateSub = _bridge.stateStream.listen((snap) {
      _snapshot = snap;
      notifyListeners();
    });

    _bridge.onRemoteAction = (action, _) {
      unawaited(_handleRemoteAction(action));
    };

    await _bridge.requestPermissions();
    await rescanLibrary();
    await _applyEqToNative();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      var changed = false;
      if (isPlaying) {
        _totalListenSeconds += 1;
        final hour = DateTime.now().hour;
        _hourlyCounts[hour] = (_hourlyCounts[hour] ?? 0) + 1;
        _ticksSinceSave += 1;
        if (_ticksSinceSave >= 15) {
          _ticksSinceSave = 0;
          unawaited(_savePrefs());
        }
        changed = true;
      }
      if (_sleepTimerRemaining != null) {
        final next = _sleepTimerRemaining! - const Duration(seconds: 1);
        if (next <= Duration.zero) {
          _sleepTimerRemaining = null;
          unawaited(_bridge.pause());
        } else {
          _sleepTimerRemaining = next;
        }
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    });
  }

  Future<void> _handleRemoteAction(String action) async {
    switch (action) {
      case 'ended':
        if (_sleepAfterCurrentTrack) {
          _sleepAfterCurrentTrack = false;
          await _bridge.pause();
          notifyListeners();
          return;
        }
        await playNext(userInitiated: false);
      case 'next':
        await playNext(userInitiated: true);
      case 'previous':
        await playPrevious();
      case 'favorite':
        final track = currentTrack;
        if (track != null) {
          await toggleFavorite(track);
        }
    }
  }

  Future<void> rescanLibrary() async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    try {
      final scanned = await _bridge.scanLocalAudio();
      _library = scanned;
      if (_queue.isEmpty && _library.isNotEmpty) {
        _queue = _buildSmartQueue(_library, _recommendMode);
        if (_currentIndex < 0) {
          _currentIndex = 0;
        }
      }
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Color accentColorFor(Track? track) {
    if (track == null) return _defaultAccent;
    final cached = _coverColorCache[track.id];
    if (cached != null) return cached;

    final seed = '${track.id}:${track.title}';
    var hash = 0;
    for (final code in seed.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.72, 0.56).toColor();
  }

  String? coverPathFor(Track? track) {
    if (track == null) return null;
    return _coverPathCache[track.id];
  }

  Future<void> ensureCoverLoaded(Track track) async {
    if (_coverPathCache.containsKey(track.id) ||
        _coverLoadingIds.contains(track.id)) {
      return;
    }
    _coverLoadingIds.add(track.id);
    try {
      final info = await _bridge.getCoverArtInfo(track.albumArtUri);
      final path = info['path'] as String?;
      final domColor = (info['color'] as num?)?.toInt();
      var updated = false;
      if (path != null && path.isNotEmpty) {
        _coverPathCache[track.id] = path;
        updated = true;
      }
      if (domColor != null) {
        _coverColorCache[track.id] = Color(domColor);
        updated = true;
      }
      if (updated) {
        notifyListeners();
      }
    } finally {
      _coverLoadingIds.remove(track.id);
    }
  }

  Future<void> playTrackFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final track = _queue[index];

    final lyricMap = await _bridge.readTrackLyrics(
      filePath: track.filePath,
      uri: track.uri,
    );
    final rawLyric = (lyricMap['raw'] ??
            lyricMap['lyric'] ??
            lyricMap['lrc'] ??
            lyricMap['text'] ??
            '')
        .toString();
    if (rawLyric.trim().isNotEmpty) {
      _currentLyrics = LyricParser.parse(rawLyric);
    } else if (track.isDemo) {
      _currentLyrics = LyricParser.demoLyrics();
    } else {
      _currentLyrics = LyricParser.parse('');
    }
    _playCounts[track.id] = (_playCounts[track.id] ?? 0) + 1;

    _history.removeWhere((e) => e.trackId == track.id);
    _history.insert(
      0,
      HistoryEntry(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_history.length > 200) {
      _history.removeRange(200, _history.length);
    }

    notifyListeners();
    await _bridge.loadAndPlay(track, parsedLyrics: _currentLyrics);
    if (_playbackSpeed != 1.0) {
      await _bridge.setPlaybackSpeed(_playbackSpeed);
    }
    await _bridge.setFavorite(_favoriteIds.contains(track.id));
    unawaited(ensureCoverLoaded(track));
    unawaited(_savePrefs());
  }

  Future<void> playTrackList(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    _queue = List<Track>.from(tracks);
    final safeIndex = startIndex.clamp(0, _queue.length - 1);
    await playTrackFromQueue(safeIndex);
  }

  Future<void> playQueue(List<Track> tracks, {int initialIndex = 0}) =>
      playTrackList(tracks, initialIndex);

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    final targetQueue =
        (queue != null && queue.isNotEmpty) ? queue : <Track>[track];
    final idx = targetQueue.indexWhere((t) => t.id == track.id);
    await playTrackList(targetQueue, idx >= 0 ? idx : 0);
  }

  Future<void> playDemo() async {
    if (_library.isNotEmpty) {
      await playTrackList(_library, 0);
      return;
    }
    final demoTrack = await _bridge.prepareDemoAudio();
    await playTrackList(<Track>[demoTrack], 0);
  }

  Future<void> playNext({bool userInitiated = false}) async {
    if (_queue.isEmpty) return;
    if (!userInitiated && _playMode == PlayMode.single) {
      await playTrackFromQueue(_currentIndex < 0 ? 0 : _currentIndex);
      return;
    }
    if (_playMode == PlayMode.shuffle) {
      if (_queue.length == 1) {
        await playTrackFromQueue(0);
        return;
      }
      var next = _random.nextInt(_queue.length);
      if (next == _currentIndex) {
        next = (next + 1) % _queue.length;
      }
      await playTrackFromQueue(next);
      return;
    }
    final nextIndex = (_currentIndex + 1) % _queue.length;
    await playTrackFromQueue(nextIndex);
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    if (positionMs > 3000) {
      await seekTo(0);
      return;
    }
    final prevIndex = (_currentIndex - 1 + _queue.length) % _queue.length;
    await playTrackFromQueue(prevIndex);
  }

  Future<void> togglePlayPause() async {
    if (_queue.isEmpty) {
      await playDemo();
      return;
    }
    if (_currentIndex < 0) {
      await playTrackFromQueue(0);
      return;
    }
    if (isPlaying) {
      await _bridge.pause();
    } else {
      await _bridge.play();
    }
  }

  Future<void> seekTo(int ms) async {
    final clamped = ms < 0 ? 0 : ms;
    await _bridge.seekTo(clamped);
  }

  void cyclePlayMode() {
    const modes = PlayMode.values;
    final next = modes[(_playMode.index + 1) % modes.length];
    setPlayMode(next);
  }

  void setPlayMode(PlayMode m) {
    if (_playMode == m) return;
    _playMode = m;
    if (m == PlayMode.smart && _library.isNotEmpty) {
      final active = currentTrack;
      final smartQueue = _buildSmartQueue(_library, _recommendMode);
      if (active != null) {
        smartQueue.removeWhere((t) => t.id == active.id);
        smartQueue.insert(0, active);
        _currentIndex = 0;
      }
      _queue = smartQueue;
    }
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setPlayerStyle(PlayerStyle s) {
    if (_playerStyle == s) return;
    _playerStyle = s;
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setSkin(AppSkin s) {
    if (_skin == s) return;
    _skin = s;
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setPureMode(bool v) {
    if (_pureMode == v) return;
    _pureMode = v;
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setShowTranslation(bool v) {
    if (_showTranslation == v) return;
    _showTranslation = v;
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setShowPhonetic(bool v) {
    if (_showPhonetic == v) return;
    _showPhonetic = v;
    unawaited(_savePrefs());
    notifyListeners();
  }

  void setLyricFontScale(double v) {
    final clamped = v.clamp(0.8, 1.6);
    if (_lyricFontScale == clamped) return;
    _lyricFontScale = clamped;
    unawaited(_savePrefs());
    notifyListeners();
  }

  Future<void> setRecommendMode(RecommendMode m) async {
    _recommendMode = m;
    if (_library.isNotEmpty) {
      final active = currentTrack;
      final rebuilt = _buildSmartQueue(_library, m);
      if (active != null) {
        rebuilt.removeWhere((t) => t.id == active.id);
        rebuilt.insert(0, active);
        _currentIndex = 0;
      }
      _queue = rebuilt;
    }
    await _savePrefs();
    notifyListeners();
  }

  List<Track> _buildSmartQueue(List<Track> source, RecommendMode mode) {
    final list = List<Track>.from(source);
    if (list.length <= 1) return list;

    switch (mode) {
      case RecommendMode.balanced:
        list.shuffle(_random);
        list.sort((a, b) {
          final favCmp = (_favoriteIds.contains(b.id) ? 1 : 0)
              .compareTo(_favoriteIds.contains(a.id) ? 1 : 0);
          return favCmp;
        });
      case RecommendMode.familiar:
        list.sort((a, b) {
          final countB =
              (_playCounts[b.id] ?? 0) + (_favoriteIds.contains(b.id) ? 5 : 0);
          final countA =
              (_playCounts[a.id] ?? 0) + (_favoriteIds.contains(a.id) ? 5 : 0);
          return countB.compareTo(countA);
        });
      case RecommendMode.fresh:
        list.shuffle(_random);
        list.sort((a, b) {
          final countA = _playCounts[a.id] ?? 0;
          final countB = _playCounts[b.id] ?? 0;
          return countA.compareTo(countB);
        });
    }
    return list;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0);
    if (_playbackSpeed == clamped) return;
    _playbackSpeed = clamped;
    await _bridge.setPlaybackSpeed(clamped);
    await _savePrefs();
    notifyListeners();
  }

  void setSleepTimer(Duration? d) {
    _sleepTimerRemaining = d;
    if (d != null) {
      _sleepAfterCurrentTrack = false;
    }
    notifyListeners();
  }

  void setSleepAfterCurrentTrack(bool v) {
    _sleepAfterCurrentTrack = v;
    if (v) {
      _sleepTimerRemaining = null;
    }
    notifyListeners();
  }

  void setStopAfterCurrent(bool v) => setSleepAfterCurrentTrack(v);
  void setAppSkin(AppSkin s) => setSkin(s);
  Future<void> togglePlay() => togglePlayPause();
  Future<void> next() => playNext(userInitiated: true);
  Future<void> previous() => playPrevious();
  Future<void> toggleDesktopLyric() async {
    await _bridge.setFloatingLyricEnabled(!_bridge.floatingLyricEnabled);
    notifyListeners();
  }

  bool isFavorite(String id) => _favoriteIds.contains(id);
  int playCountFor(String id) => _playCounts[id] ?? 0;
  List<Track> get topPlayedTracks => topRankedTracks(limit: 50);

  UserPlaylist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Track> tracksInPlaylist(String playlistId) {
    final p = playlistById(playlistId);
    if (p == null) return const <Track>[];
    final byId = <String, Track>{for (final t in _library) t.id: t};
    return p.trackIds
        .map((id) => byId[id])
        .whereType<Track>()
        .toList(growable: false);
  }

  Future<void> toggleFavorite(Track track) async {
    if (_favoriteIds.contains(track.id)) {
      _favoriteIds.remove(track.id);
    } else {
      _favoriteIds.add(track.id);
    }
    if (currentTrack?.id == track.id) {
      await _bridge.setFavorite(_favoriteIds.contains(track.id));
    }
    await _savePrefs();
    notifyListeners();
  }

  Future<String> createPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final playlist = UserPlaylist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999)}',
      name: trimmed,
      trackIds: <String>[],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _playlists.insert(0, playlist);
    await _savePrefs();
    notifyListeners();
    return playlist.id;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _playlists[idx] = _playlists[idx].copyWith(name: trimmed);
    await _savePrefs();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    await _savePrefs();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final existing = _playlists[idx];
    if (existing.trackIds.contains(track.id)) return;
    final updatedIds = List<String>.from(existing.trackIds)..add(track.id);
    _playlists[idx] = existing.copyWith(trackIds: updatedIds);
    await _savePrefs();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final existing = _playlists[idx];
    final updatedIds = List<String>.from(existing.trackIds)..remove(trackId);
    _playlists[idx] = existing.copyWith(trackIds: updatedIds);
    await _savePrefs();
    notifyListeners();
  }

  void addSearchQuery(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);
    if (_recentSearches.length > 20) {
      _recentSearches.removeRange(20, _recentSearches.length);
    }
    unawaited(_savePrefs());
    notifyListeners();
  }

  void clearSearchHistory() {
    _recentSearches.clear();
    unawaited(_savePrefs());
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    unawaited(_savePrefs());
    notifyListeners();
  }

  Future<void> applyEqPreset(String presetId) async {
    final preset = SoundFxPresets.byId(presetId);
    _eqPresetId = preset.id;
    _eqGains = List<double>.from(preset.gains);
    _eqPreGain = preset.preGain;
    await _applyEqToNative();
    await _savePrefs();
    notifyListeners();
  }

  Future<void> setCustomEq(List<double> gains, double preGain) async {
    _eqPresetId = 'custom';
    _eqGains = List<double>.generate(
      5,
      (i) => i < gains.length ? gains[i].clamp(-12.0, 12.0) : 0.0,
    );
    _eqPreGain = preGain.clamp(-12.0, 12.0);
    await _applyEqToNative();
    await _savePrefs();
    notifyListeners();
  }

  Future<void> _applyEqToNative() async {
    await _bridge.setEqParams(_eqGains, _eqPreGain);
  }

  Future<MusicSourcePlugin> importPluginFromText(
    String raw, {
    String? sourceUrl,
    String? fileName,
  }) async {
    final plugin = PluginParser.parseScript(
      raw,
      sourceUrl: sourceUrl,
      fileName: fileName,
    );
    _plugins.removeWhere((p) => p.id == plugin.id);
    _plugins.insert(0, plugin);
    await _savePrefs();
    notifyListeners();
    return plugin;
  }

  Future<MusicSourcePlugin> importPluginFromUrl(String url) async {
    final raw = await PluginFetcher.fetchScriptFromUrl(url);
    return importPluginFromText(raw, sourceUrl: url);
  }

  Future<MusicSourcePlugin?> importPluginFromFile() async {
    final picked = await _bridge.pickTextFile();
    final raw = picked?['content'];
    if (raw == null || raw.trim().isEmpty) return null;
    return importPluginFromText(raw, fileName: picked?['name']);
  }

  Future<void> togglePlugin(String id, bool enabled) async {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _plugins[idx] = _plugins[idx].copyWith(enabled: enabled);
    await _savePrefs();
    notifyListeners();
  }

  Future<void> setPluginEnabled(String id, bool enabled) =>
      togglePlugin(id, enabled);

  Future<void> removePlugin(String id) async {
    _plugins.removeWhere((p) => p.id == id);
    await _savePrefs();
    notifyListeners();
  }

  Future<bool> importExternalLyricForCurrentTrack() async {
    final track = currentTrack;
    if (track == null) return false;
    final picked = await _bridge.pickTextFile();
    final raw = picked?['content'];
    if (raw == null || raw.trim().isEmpty) return false;

    final parsed = LyricParser.parse(raw);
    _currentLyrics = parsed;
    await _bridge.loadAndPlay(track, parsedLyrics: parsed);
    notifyListeners();
    return true;
  }

  Future<bool> importExternalLyric() => importExternalLyricForCurrentTrack();

  List<Track> topRankedTracks({int limit = 20}) {
    final played = _library.where((t) => (_playCounts[t.id] ?? 0) > 0).toList()
      ..sort((a, b) {
        final countCmp =
            (_playCounts[b.id] ?? 0).compareTo(_playCounts[a.id] ?? 0);
        if (countCmp != 0) return countCmp;
        return a.title.compareTo(b.title);
      });
    if (played.length <= limit) return played;
    return played.sublist(0, limit);
  }

  String exportBackupJson() {
    final payload = <String, dynamic>{
      'schema': 'soda_pulse_backup_v1',
      'exportedAtMs': DateTime.now().millisecondsSinceEpoch,
      'favoriteIds': _favoriteIds.toList(),
      'playlists': _playlists.map((p) => p.toJson()).toList(),
      'history': _history.map((h) => h.toJson()).toList(),
      'playCounts': _playCounts,
      'totalListenSeconds': _totalListenSeconds,
      'hourlyCounts': _hourlyCounts.map((k, v) => MapEntry(k.toString(), v)),
      'recentSearches': _recentSearches,
      'eqPresetId': _eqPresetId,
      'eqGains': _eqGains,
      'eqPreGain': _eqPreGain,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String?> exportBackupToFile() async {
    final content = exportBackupJson();
    final fileName =
        'soda_pulse_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    return _bridge.exportTextFile(fileName, content);
  }

  Future<int> importBackupJson(String raw) async {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'soda_pulse_backup_v1') {
      throw const FormatException('这不是气泡水的备份文件');
    }

    var importedCount = 0;

    final rawFavs = decoded['favoriteIds'];
    if (rawFavs is List) {
      for (final item in rawFavs) {
        final id = item.toString();
        if (id.isNotEmpty && _favoriteIds.add(id)) {
          importedCount += 1;
        }
      }
    }

    final rawPlaylists = decoded['playlists'];
    if (rawPlaylists is List) {
      for (final item in rawPlaylists) {
        if (item is Map<String, dynamic>) {
          final pl = UserPlaylist.fromJson(item);
          if (pl.id.isNotEmpty) {
            final idx = _playlists.indexWhere((p) => p.id == pl.id);
            if (idx >= 0) {
              _playlists[idx] = pl;
            } else {
              _playlists.add(pl);
            }
            importedCount += 1;
          }
        }
      }
    }

    final rawHistory = decoded['history'];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map<String, dynamic>) {
          final entry = HistoryEntry.fromJson(item);
          if (entry.trackId.isNotEmpty &&
              !_history.any((e) =>
                  e.trackId == entry.trackId &&
                  e.playedAtMs == entry.playedAtMs)) {
            _history.add(entry);
            importedCount += 1;
          }
        }
      }
      _history.sort((a, b) => b.playedAtMs.compareTo(a.playedAtMs));
      if (_history.length > 200) {
        _history.removeRange(200, _history.length);
      }
    }

    final rawCounts = decoded['playCounts'];
    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        final id = key.toString();
        final count = (value as num?)?.toInt() ?? 0;
        if (id.isNotEmpty && count > (_playCounts[id] ?? 0)) {
          _playCounts[id] = count;
        }
      });
    }

    final totalSec = (decoded['totalListenSeconds'] as num?)?.toInt();
    if (totalSec != null && totalSec > _totalListenSeconds) {
      _totalListenSeconds = totalSec;
    }

    final rawHourly = decoded['hourlyCounts'];
    if (rawHourly is Map) {
      rawHourly.forEach((key, value) {
        final hour = int.tryParse(key.toString());
        final count = (value as num?)?.toInt() ?? 0;
        if (hour != null && hour >= 0 && hour < 24) {
          if (count > (_hourlyCounts[hour] ?? 0)) {
            _hourlyCounts[hour] = count;
          }
        }
      });
    }

    final rawSearches = decoded['recentSearches'];
    if (rawSearches is List) {
      for (final item in rawSearches) {
        final q = item.toString().trim();
        if (q.isNotEmpty && !_recentSearches.contains(q)) {
          _recentSearches.add(q);
        }
      }
      if (_recentSearches.length > 20) {
        _recentSearches.removeRange(20, _recentSearches.length);
      }
    }

    final eqId = decoded['eqPresetId']?.toString();
    final eqGainsRaw = decoded['eqGains'];
    final eqPreRaw = (decoded['eqPreGain'] as num?)?.toDouble();
    if (eqId != null) {
      _eqPresetId = eqId;
    }
    if (eqGainsRaw is List && eqGainsRaw.length == 5) {
      _eqGains = eqGainsRaw
          .map((e) => ((e as num?)?.toDouble() ?? 0.0).clamp(-12.0, 12.0))
          .toList();
    }
    if (eqPreRaw != null) {
      _eqPreGain = eqPreRaw.clamp(-12.0, 12.0);
    }

    await _applyEqToNative();
    await _savePrefs();
    notifyListeners();
    return importedCount;
  }

  Future<void> shareCurrentTrack() async {
    final track = currentTrack;
    if (track == null) return;
    await _bridge.shareText(
      '${track.title} - ${track.artist}',
      subject: track.title,
    );
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await _bridge.getPreferences();
      final raw = prefs[_prefsKey] as String?;
      if (raw == null || raw.isEmpty) return;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      _playMode = _enumByName(
        PlayMode.values,
        decoded['playMode']?.toString(),
        PlayMode.sequence,
      );
      _playerStyle = _enumByName(
        PlayerStyle.values,
        decoded['playerStyle']?.toString(),
        PlayerStyle.immersive,
      );
      _skin = _enumByName(
        AppSkin.values,
        decoded['skin']?.toString(),
        AppSkin.soda,
      );
      _recommendMode = _enumByName(
        RecommendMode.values,
        decoded['recommendMode']?.toString(),
        RecommendMode.balanced,
      );

      _pureMode = decoded['pureMode'] == true;
      _showTranslation = decoded['showTranslation'] != false;
      _showPhonetic = decoded['showPhonetic'] == true;
      _lyricFontScale =
          ((decoded['lyricFontScale'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.8, 1.6);
      _playbackSpeed =
          ((decoded['playbackSpeed'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.5, 2.0);

      final favs = decoded['favoriteIds'];
      if (favs is List) {
        _favoriteIds
          ..clear()
          ..addAll(favs.map((e) => e.toString()));
      }

      final pls = decoded['playlists'];
      if (pls is List) {
        _playlists
          ..clear()
          ..addAll(
            pls
                .whereType<Map<String, dynamic>>()
                .map(UserPlaylist.fromJson),
          );
      }

      final hist = decoded['history'];
      if (hist is List) {
        _history
          ..clear()
          ..addAll(
            hist
                .whereType<Map<String, dynamic>>()
                .map(HistoryEntry.fromJson),
          );
      }

      final counts = decoded['playCounts'];
      if (counts is Map) {
        _playCounts.clear();
        counts.forEach((k, v) {
          final val = (v as num?)?.toInt() ?? 0;
          if (val > 0) _playCounts[k.toString()] = val;
        });
      }

      _totalListenSeconds =
          (decoded['totalListenSeconds'] as num?)?.toInt() ?? 0;

      final hourly = decoded['hourlyCounts'];
      if (hourly is Map) {
        _hourlyCounts.clear();
        hourly.forEach((k, v) {
          final hour = int.tryParse(k.toString());
          final val = (v as num?)?.toInt() ?? 0;
          if (hour != null && hour >= 0 && hour < 24 && val > 0) {
            _hourlyCounts[hour] = val;
          }
        });
      }

      final searches = decoded['recentSearches'];
      if (searches is List) {
        _recentSearches
          ..clear()
          ..addAll(searches.map((e) => e.toString()));
      }

      _eqPresetId = (decoded['eqPresetId'] ?? 'flat').toString();
      final gains = decoded['eqGains'];
      if (gains is List && gains.length == 5) {
        _eqGains = gains
            .map((e) => ((e as num?)?.toDouble() ?? 0.0).clamp(-12.0, 12.0))
            .toList();
      }
      _eqPreGain =
          ((decoded['eqPreGain'] as num?)?.toDouble() ?? 0.0).clamp(-12.0, 12.0);
      final rawPlugins = decoded['plugins'];
      if (rawPlugins is List) {
        _plugins
          ..clear()
          ..addAll(
            rawPlugins
                .whereType<Map>()
                .map((e) => MusicSourcePlugin.fromJson(Map<String, dynamic>.from(e))),
          );
      }
    } catch (_) {
      // Ignore corrupted local preference data and use defaults.
    }
  }

  Future<void> _savePrefs() async {
    final data = <String, dynamic>{
      'playMode': _playMode.name,
      'playerStyle': _playerStyle.name,
      'skin': _skin.name,
      'recommendMode': _recommendMode.name,
      'pureMode': _pureMode,
      'showTranslation': _showTranslation,
      'showPhonetic': _showPhonetic,
      'lyricFontScale': _lyricFontScale,
      'playbackSpeed': _playbackSpeed,
      'favoriteIds': _favoriteIds.toList(),
      'playlists': _playlists.map((p) => p.toJson()).toList(),
      'history': _history.map((h) => h.toJson()).toList(),
      'playCounts': _playCounts,
      'totalListenSeconds': _totalListenSeconds,
      'hourlyCounts': _hourlyCounts.map((k, v) => MapEntry(k.toString(), v)),
      'recentSearches': _recentSearches,
      'eqPresetId': _eqPresetId,
      'eqGains': _eqGains,
      'eqPreGain': _eqPreGain,
      'plugins': _plugins.map((p) => p.toJson()).toList(),
    };
    await _bridge.savePreferences(<String, dynamic>{
      _prefsKey: jsonEncode(data),
    });
  }

  T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
