import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:soda_pulse/models/track.dart';

class OnlineChartDef {
  final String id;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;

  const OnlineChartDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
  });
}

class OnlinePlaylistDetail {
  final String id;
  final String name;
  final String description;
  final String coverUrl;
  final List<Track> tracks;

  const OnlinePlaylistDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.tracks,
  });
}

class OnlineMusicCatalog {
  OnlineMusicCatalog._();

  static const Duration _timeout = Duration(seconds: 10);
  static const String _referer = 'https://music.163.com/';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const List<OnlineChartDef> charts = [
    OnlineChartDef(
      id: '3778678',
      title: '热歌榜',
      subtitle: '全网热度飙升 · 实时更新',
      gradientColors: [Color(0xFF1F3A3D), Color(0xFF0E1B1D)],
    ),
    OnlineChartDef(
      id: '19723756',
      title: '飙升榜',
      subtitle: '实时飙升 · 热门单曲',
      gradientColors: [Color(0xFF1D3E4E), Color(0xFF0F2028)],
    ),
    OnlineChartDef(
      id: '3779629',
      title: '新歌榜',
      subtitle: '最新上架 · 每日精选',
      gradientColors: [Color(0xFF1B4530), Color(0xFF0D2117)],
    ),
    OnlineChartDef(
      id: '2884035',
      title: '原创榜',
      subtitle: '独立音乐 · 原创好歌',
      gradientColors: [Color(0xFF3C2A4D), Color(0xFF17101E)],
    ),
  ];

  static String? extractPlaylistId(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;

    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed;
    }

    final queryMatch = RegExp(r'[?&]id=(\d+)').firstMatch(trimmed);
    if (queryMatch != null) {
      return queryMatch.group(1);
    }

    final pathMatch = RegExp(r'playlist/(\d+)').firstMatch(trimmed);
    if (pathMatch != null) {
      return pathMatch.group(1);
    }

    return null;
  }

  static List<Track> parseWySearchTracks(
    String jsonBody, {
    required String pluginId,
  }) {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map<String, dynamic>) return const [];
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) return const [];
    final songs = result['songs'];
    if (songs is! List) return const [];
    return _parseWyTrackList(songs, pluginId: pluginId);
  }

  static OnlinePlaylistDetail parseWyPlaylistDetail(
    String jsonBody, {
    required String pluginId,
  }) {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid playlist response JSON');
    }
    final playlist = decoded['playlist'];
    if (playlist is! Map<String, dynamic>) {
      throw const FormatException('Missing playlist object in response');
    }

    final id = playlist['id']?.toString() ?? '';
    final name = playlist['name']?.toString() ?? '';
    final description = playlist['description']?.toString() ?? '';
    final coverUrl = _toHttps(playlist['coverImgUrl']?.toString() ?? '');
    final rawTracks = playlist['tracks'];
    final tracks = rawTracks is List
        ? _parseWyTrackList(rawTracks, pluginId: pluginId)
        : const <Track>[];

    return OnlinePlaylistDetail(
      id: id,
      name: name,
      description: description,
      coverUrl: coverUrl,
      tracks: tracks,
    );
  }

  static Future<List<Track>> searchWyTracks(
    String query, {
    required String pluginId,
    int limit = 25,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final encodedQuery = Uri.encodeQueryComponent(trimmed);
    final uri = Uri.parse(
      'https://music.163.com/api/cloudsearch/pc?s=$encodedQuery&type=1&limit=$limit',
    );
    final body = await _sendRequest('POST', uri);
    return parseWySearchTracks(body, pluginId: pluginId);
  }

  static Future<OnlinePlaylistDetail> fetchWyPlaylist(
    String playlistId, {
    required String pluginId,
    int limit = 40,
  }) async {
    final encodedId = Uri.encodeQueryComponent(playlistId.trim());
    final uri = Uri.parse(
      'https://music.163.com/api/v6/playlist/detail?id=$encodedId&n=$limit',
    );
    final body = await _sendRequest('GET', uri);
    return parseWyPlaylistDetail(body, pluginId: pluginId);
  }

  static Future<({String raw, String translation})> fetchWyLyric(
    String songId,
  ) async {
    final encodedId = Uri.encodeQueryComponent(songId.trim());
    final uri = Uri.parse(
      'https://music.163.com/api/song/lyric?id=$encodedId&lv=1&tv=1',
    );
    final body = await _sendRequest('GET', uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return (raw: '', translation: '');
    }

    final lrc = decoded['lrc'];
    final tlyric = decoded['tlyric'];
    final raw =
        lrc is Map<String, dynamic> ? (lrc['lyric']?.toString() ?? '') : '';
    final translation = tlyric is Map<String, dynamic>
        ? (tlyric['lyric']?.toString() ?? '')
        : '';

    return (raw: raw, translation: translation);
  }

  static Future<String> _sendRequest(String method, Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(_timeout);
      request.headers.set(HttpHeaders.refererHeader, _referer);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);

      final response = await request.close().timeout(_timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: $body',
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static List<Track> _parseWyTrackList(
    List<dynamic> rawSongs, {
    required String pluginId,
  }) {
    final tracks = <Track>[];
    for (final item in rawSongs) {
      if (item is! Map) continue;
      final song = Map<String, dynamic>.from(item);
      final songId = song['id']?.toString() ?? '';
      if (songId.isEmpty) continue;

      final title = song['name']?.toString() ?? '';
      final artist = _extractArtists(song);
      final albumMap = _asMap(song['al']) ?? _asMap(song['album']);
      final album = albumMap?['name']?.toString() ?? '';
      final httpsPic = _toHttps(albumMap?['picUrl']?.toString() ?? '');
      final durationMs = _asInt(song['dt'] ?? song['duration']);

      final rawPluginData = jsonEncode({
        'id': songId,
        'songmid': songId,
        'name': title,
        'singer': artist,
        'albumName': album,
        'interval': durationMs ~/ 1000,
        'pic': httpsPic,
        'source': 'wy',
      });

      tracks.add(
        Track(
          id: 'lx_wy_$songId',
          title: title,
          artist: artist,
          album: album,
          durationMs: durationMs,
          uri: '',
          albumArtUri: httpsPic.isEmpty ? null : httpsPic,
          pluginId: pluginId,
          sourcePlatform: 'wy',
          rawPluginData: rawPluginData,
        ),
      );
    }
    return tracks;
  }

  static String _extractArtists(Map<String, dynamic> song) {
    final rawArtists = song['ar'] ?? song['artists'];
    if (rawArtists is! List) return '';
    final names = <String>[];
    for (final artist in rawArtists) {
      if (artist is Map) {
        final name = artist['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
    }
    return names.join(' / ');
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String _toHttps(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring(7)}';
    }
    return trimmed;
  }
}
