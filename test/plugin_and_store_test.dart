import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/core/daily_copy.dart';
import 'package:soda_pulse/core/t2s_converter.dart';
import 'package:soda_pulse/plugin/plugin_manager.dart';

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
}
