import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/core/daily_copy.dart';
import 'package:soda_pulse/core/t2s_converter.dart';
import 'package:soda_pulse/plugin/plugin_manager.dart';
import 'package:soda_pulse/services/media_storage_service.dart';
import 'package:soda_pulse/services/native_bridge.dart';
import 'package:soda_pulse/services/online_music_catalog.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

void main() {
  group('PluginParser.parseScript', () {
    test('parses LX Music plugin metadata and platforms', () {
      const lxScript = '''
/*!
 * @name Demo LX Source
 * @description Test LX source script
 * @version 1.2.3
 * @author Tester
 */
const { EVENT_NAMES, on, send } = globalThis.lx;
const sources = { kw: {}, wy: {}, tx: {} };
on(EVENT_NAMES.request, ({ source, action, info }) => {});
''';
      final plugin = PluginParser.parseScript(lxScript);
      expect(plugin.type, PluginType.lx);
      expect(plugin.name, 'Demo LX Source');
      expect(plugin.version, '1.2.3');
      expect(plugin.author, 'Tester');
      expect(plugin.platforms, containsAll(<String>['kw', 'wy', 'tx']));
    });

    test('parses MusicFree plugin module.exports', () {
      const mfScript = '''
module.exports = {
  platform: "DemoMF",
  version: "0.9.0",
  author: "OpenMusic",
  srcUrl: "https://example.com/mf.js",
  getMediaSource(musicItem, quality) {
    return { url: "https://example.com/a.mp3" };
  }
};
''';
      final plugin = PluginParser.parseScript(mfScript);
      expect(plugin.type, PluginType.musicFree);
      expect(plugin.name, 'DemoMF');
      expect(plugin.version, '0.9.0');
      expect(plugin.author, 'OpenMusic');
    });

    test('rejects non-plugin script with FormatException', () {
      expect(
        () => PluginParser.parseScript('console.log("hello world");'),
        throwsFormatException,
      );
    });
  });

  group('DailyCopy & SoundFxPresets', () {
    test('DailyCopy.forHour returns non-empty copy across all hours', () {
      for (int h = 0; h < 24; h++) {
        final copy = DailyCopy.forHour(h);
        expect(copy.title, isNotEmpty);
        expect(copy.subtitle, isNotEmpty);
      }
    });

    test('SoundFxPresets.all has 7 valid 5-band EQ curves', () {
      expect(SoundFxPresets.all, hasLength(7));
      for (final preset in SoundFxPresets.all) {
        expect(preset.gains, hasLength(5));
        expect(preset.name, isNotEmpty);
      }
    });

    test('UserPlaylist JSON round-trip preserves fields', () {
      const playlist = UserPlaylist(
        id: 'pl_1',
        name: 'Night Drive',
        trackIds: <String>['101', '102'],
        createdAtMs: 1700000000000,
      );
      final decoded = UserPlaylist.fromJson(
        jsonDecode(jsonEncode(playlist.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.id, playlist.id);
      expect(decoded.name, playlist.name);
      expect(decoded.trackIds, playlist.trackIds);
      expect(decoded.createdAtMs, playlist.createdAtMs);
    });

    test('T2SConverter normalizes Traditional Chinese song titles & artists', () {
      expect(T2SConverter.convert('烏梅子醬'), '乌梅子酱');
      expect(T2SConverter.convert('李榮浩'), '李荣浩');
      expect(T2SConverter.convert('陳奕迅'), '陈奕迅');
      expect(T2SConverter.convert('周杰倫'), '周杰伦');
      expect(T2SConverter.normalize('  鄧紫棋 G.E.M. '), '邓紫棋 g.e.m.');
    });
  });

  group('PluginQrParser', () {
    const sampleMfScript = '''
module.exports = {
  platform: "QrDemoMF",
  version: "1.0.0",
  author: "Tester",
  getMediaSource(musicItem, quality) {
    return { url: "https://example.com/a.mp3" };
  }
};
''';

    test('parses direct http(s) script and subscription URLs', () {
      final jsRes = PluginQrParser.parse('https://example.com/plugins/demo.js');
      expect(jsRes.kind, PluginQrPayloadKind.scriptUrl);
      expect(jsRes.urls, <String>['https://example.com/plugins/demo.js']);

      final subRes = PluginQrParser.parse('http://example.com/sub/plugins.json');
      expect(subRes.kind, PluginQrPayloadKind.scriptUrl);
      expect(subRes.urls, <String>['http://example.com/sub/plugins.json']);
    });

    test('parses custom URI schemes (bubble://, musicfree://, lxmusic://, sodapulse://)', () {
      const target = 'https://example.com/source.js';
      final enc = Uri.encodeComponent(target);
      for (final raw in <String>[
        'bubble://plugin?url=$enc',
        'musicfree://install?src=$enc',
        'lxmusic://import?srcUrl=$enc',
        'sodapulse://add?plugin=$enc',
        'bubble://subscribe?sub=$enc',
        'sodapulse://open/$target',
      ]) {
        final res = PluginQrParser.parse(raw);
        expect(res.kind, PluginQrPayloadKind.scriptUrl, reason: raw);
        expect(res.urls, <String>[target], reason: raw);
      }
    });

    test('parses inline JSON manifests and script objects', () {
      const manifest = '''
      {
        "plugins": [
          {"name": "A", "url": "https://example.com/a.js"},
          {"name": "B", "srcUrl": "https://example.com/b.js"}
        ]
      }
      ''';
      final mRes = PluginQrParser.parse(manifest);
      expect(mRes.kind, PluginQrPayloadKind.manifestJson);
      expect(mRes.urls, <String>[
        'https://example.com/a.js',
        'https://example.com/b.js',
      ]);

      final scriptObj = jsonEncode(<String, dynamic>{'script': sampleMfScript});
      final sRes = PluginQrParser.parse(scriptObj);
      expect(sRes.kind, PluginQrPayloadKind.inlineScript);
      expect(sRes.inlineScript, sampleMfScript.trim());
    });

    test('parses data:...;base64 and base64:// payloads', () {
      final jsB64 = base64Encode(utf8.encode(sampleMfScript));
      final dataRes = PluginQrParser.parse('data:text/javascript;base64,$jsB64');
      expect(dataRes.kind, PluginQrPayloadKind.inlineScript);

      const jsonManifest = '{"plugins":[{"url":"https://example.com/p.js"}]}';
      final jsonB64 = base64Encode(utf8.encode(jsonManifest));
      final b64Res = PluginQrParser.parse('base64://$jsonB64');
      expect(b64Res.kind, PluginQrPayloadKind.manifestJson);
      expect(b64Res.urls, <String>['https://example.com/p.js']);
    });

    test('parses raw JS script and mixed text with Chinese punctuation', () {
      final rawRes = PluginQrParser.parse(sampleMfScript);
      expect(rawRes.kind, PluginQrPayloadKind.inlineScript);

      final mixedRes = PluginQrParser.parse('分享音源插件：https://example.com/one.js，请复制使用。');
      expect(mixedRes.kind, PluginQrPayloadKind.scriptUrl);
      expect(mixedRes.urls, <String>['https://example.com/one.js']);

      final multiRes = PluginQrParser.parse('源1 https://example.com/1.js 源2 https://example.com/2.js');
      expect(multiRes.kind, PluginQrPayloadKind.urlList);
      expect(multiRes.urls, <String>[
        'https://example.com/1.js',
        'https://example.com/2.js',
      ]);
    });

    test('throws FormatException on invalid QR payloads', () {
      for (final bad in <String>['', '   ', 'hello world', 'bubble://plugin?foo=bar', 'base64://!!!']) {
        expect(() => PluginQrParser.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('preserves and percent-encodes Chinese filenames in URLs', () {
      const cnUrl = 'https://raw.githubusercontent.com/yr123466/yr/refs/heads/main/全豆要.js';
      final directRes = PluginQrParser.parse(cnUrl);
      expect(directRes.kind, PluginQrPayloadKind.scriptUrl);
      expect(directRes.urls, <String>[cnUrl]);

      final mixedRes = PluginQrParser.parse('分享音源：https://raw.githubusercontent.com/yr123466/yr/refs/heads/main/全豆要.js，扫码导入！');
      expect(mixedRes.kind, PluginQrPayloadKind.scriptUrl);
      expect(mixedRes.urls, <String>[cnUrl]);

      final normalized = PluginFetcher.normalizeUrl(cnUrl);
      expect(normalized, 'https://raw.githubusercontent.com/yr123466/yr/refs/heads/main/%E5%85%A8%E8%B1%86%E8%A6%81.js');
      expect(PluginFetcher.normalizeUrl(normalized), normalized);
    });
  });

  group('OnlineMusicCatalog', () {
    test('extractPlaylistId handles full NetEase URLs and raw numeric IDs', () {
      expect(
        OnlineMusicCatalog.extractPlaylistId('https://music.163.com/#/playlist?id=3778678'),
        '3778678',
      );
      expect(
        OnlineMusicCatalog.extractPlaylistId('https://y.music.163.com/m/playlist?id=19723756&userid=1'),
        '19723756',
      );
      expect(OnlineMusicCatalog.extractPlaylistId('2884035'), '2884035');
      expect(OnlineMusicCatalog.extractPlaylistId('not a playlist'), isNull);
    });

    test('parseWySearchTracks and parseWyPlaylistDetail build LX-resolvable tracks', () {
      const searchJson = '''
      {
        "result": {
          "songs": [
            {
              "id": 186016,
              "name": "晴天",
              "dt": 269000,
              "ar": [{"name": "周杰伦"}],
              "al": {"name": "叶惠美", "picUrl": "http://p1.music.126.net/demo.jpg"}
            }
          ]
        }
      }
      ''';
      final tracks = OnlineMusicCatalog.parseWySearchTracks(
        searchJson,
        pluginId: 'lx_demo',
      );
      expect(tracks, hasLength(1));
      expect(tracks.first.id, 'lx_wy_186016');
      expect(tracks.first.title, '晴天');
      expect(tracks.first.artist, '周杰伦');
      expect(tracks.first.albumArtUri, 'https://p1.music.126.net/demo.jpg');
      expect(tracks.first.sourcePlatform, 'wy');
      expect(tracks.first.pluginId, 'lx_demo');

      const playlistJson = '''
      {
        "playlist": {
          "id": 3778678,
          "name": "热歌榜",
          "description": "热门单曲",
          "coverImgUrl": "http://p1.music.126.net/hot.jpg",
          "tracks": [
            {
              "id": 999,
              "name": "海屿你",
              "dt": 210000,
              "ar": [{"name": "测试歌手"}],
              "al": {"name": "测试专辑", "picUrl": "http://p1.music.126.net/a.jpg"}
            }
          ]
        }
      }
      ''';
      final detail = OnlineMusicCatalog.parseWyPlaylistDetail(
        playlistJson,
        pluginId: 'lx_demo',
      );
      expect(detail.name, '热歌榜');
      expect(detail.tracks, hasLength(1));
      expect(detail.tracks.first.title, '海屿你');
    });
  });

  group('CoverArtWidget helpers', () {
    test('networkHeadersFor sets NetEase Referer without duplicating User-Agent', () {
      expect(CoverArtWidget.defaultUserAgent, contains('Mozilla/5.0'));
      expect(CoverArtWidget.defaultUserAgent, isNot(contains('Dart/')));

      final wyHeaders = CoverArtWidget.networkHeadersFor(
        'https://P2.MUSIC.126.NET/abc/123.jpg',
      );
      expect(wyHeaders.containsKey('User-Agent'), isFalse);
      expect(wyHeaders['Referer'], 'https://music.163.com/');

      final otherHeaders = CoverArtWidget.networkHeadersFor(
        'https://cdn.example.com/cover.jpg',
      );
      expect(otherHeaders, isEmpty);
    });

    test('resolveNetworkUrl upgrades http and appends NetEase size params', () {
      expect(
        CoverArtWidget.resolveNetworkUrl(
          'http://p1.music.126.net/abc/123.jpg',
          size: 46,
        ),
        'https://p1.music.126.net/abc/123.jpg?param=200y200',
      );
      expect(
        CoverArtWidget.resolveNetworkUrl(
          'https://p2.music.126.net/abc/123.jpg',
          size: 260,
        ),
        'https://p2.music.126.net/abc/123.jpg?param=600y600',
      );
      expect(
        CoverArtWidget.resolveNetworkUrl(
          'http://p1.music.126.net/abc/123.jpg?param=300y300',
          size: 44,
        ),
        'https://p1.music.126.net/abc/123.jpg?param=300y300',
      );
    });
  });

  group('PlaybackSnapshot playbackState', () {
    test('defaults playbackState to 1 and preserves via copyWith', () {
      const initial = PlaybackSnapshot();
      expect(initial.playbackState, 1);

      final ready = initial.copyWith(isPlaying: true, playbackState: 3);
      expect(ready.playbackState, 3);
      expect(ready.isPlaying, isTrue);

      final paused = ready.copyWith(isPlaying: false);
      expect(paused.playbackState, 3);
      expect(paused.isPlaying, isFalse);

      final parsed = PlaybackSnapshot.fromMap({
        'isPlaying': true,
        'positionMs': 1200,
        'durationMs': 24000,
        'playbackState': 3,
      });
      expect(parsed.playbackState, 3);
    });
  });

  group('AppStore.isSnapshotForActiveTrack', () {
    test('filters out stale snapshots from a different trackId', () {
      const snapA = PlaybackSnapshot(trackId: 'track_a', isPlaying: true, positionMs: 35000);
      expect(AppStore.isSnapshotForActiveTrack(snapA, 'track_a'), isTrue);
      expect(AppStore.isSnapshotForActiveTrack(snapA, 'track_b'), isFalse);

      const snapEmpty = PlaybackSnapshot(trackId: '', isPlaying: false);
      expect(AppStore.isSnapshotForActiveTrack(snapEmpty, 'track_b'), isTrue);
      expect(AppStore.isSnapshotForActiveTrack(snapA, null), isTrue);
    });
  });

  group('AudioQualityOptions', () {
    test('defines 128k/320k/flac/flac24bit options and falls back to 320k', () {
      expect(AudioQualityOptions.all, hasLength(4));
      expect(AudioQualityOptions.byId('128k').label, '标准');
      expect(AudioQualityOptions.byId('128k').badge, 'STD');
      expect(AudioQualityOptions.byId('320k').label, '高品质');
      expect(AudioQualityOptions.byId('320k').badge, 'HQ');
      expect(AudioQualityOptions.byId('flac').label, '无损');
      expect(AudioQualityOptions.byId('flac').badge, 'SQ');
      expect(AudioQualityOptions.byId('flac24bit').label, 'Hi-Res');
      expect(AudioQualityOptions.byId('flac24bit').badge, 'HR');
      expect(AudioQualityOptions.byId('unknown').id, '320k');
    });
  });

  group('MediaStorageService & DownloadTask', () {
    test('formatBytes, sanitizeFileName, and extFromUrlOrQuality work reliably', () {
      expect(MediaStorageService.formatBytes(0), '0 B');
      expect(MediaStorageService.formatBytes(1536), '1.5 KB');
      expect(MediaStorageService.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(
        MediaStorageService.sanitizeFileName('Artist: Song? <Hi-Res>'),
        'Artist_ Song_ _Hi-Res_',
      );
      expect(
        MediaStorageService.extFromUrlOrQuality(
          'https://cdn.example.com/audio/123.flac?auth=1',
          'flac24bit',
        ),
        '.flac',
      );
      expect(
        MediaStorageService.extFromUrlOrQuality(
          'https://cdn.example.com/stream?id=1',
          '320k',
        ),
        '.mp3',
      );
    });

    test('DownloadTask serializes and restores cleanly', () {
      final task = DownloadTask(
        id: 't1',
        trackId: 'wy_100',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        quality: 'flac24bit',
        url: 'https://music.126.net/song.flac',
        targetPath: '/music/song.flac',
        lrcPath: '/music/song.lrc',
        coverUrl: 'https://p1.music.126.net/cover.jpg',
        status: DownloadStatus.downloading,
        receivedBytes: 512,
        totalBytes: 1024,
        createdAt: DateTime.utc(2026, 11, 28),
        headers: const {'Referer': 'https://music.163.com/'},
      );
      expect(task.progress, 0.5);
      final restored = DownloadTask.fromMap(task.toMap());
      expect(restored.id, 't1');
      expect(restored.quality, 'flac24bit');
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.headers['Referer'], 'https://music.163.com/');
      expect(restored.lrcPath, '/music/song.lrc');
    });
  });
}
