import 'package:flutter_test/flutter_test.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/lyrics/lyric_parser.dart';

void main() {
  group('LyricParser.parse', () {
    test('parses standard LRC with [offset:500]', () {
      const lrc = '''
[ti:Test Song]
[ar:Tester]
[offset:500]
[00:01.00]First line
[00:05.50]Second line
[00:10.00]Third line
''';

      final doc = LyricParser.parse(lrc);

      expect(doc.lines, hasLength(3));
      expect(doc.hasWordTiming, isFalse);

      expect(doc.lines[0].text, 'First line');
      expect(doc.lines[0].startMs, 1500);
      expect(doc.lines[0].endMs, 6000);

      expect(doc.lines[1].text, 'Second line');
      expect(doc.lines[1].startMs, 6000);
      expect(doc.lines[1].endMs, 10500);

      expect(doc.lines[2].text, 'Third line');
      expect(doc.lines[2].startMs, 10500);
      expect(doc.lines[2].endMs, greaterThan(doc.lines[2].startMs));
    });

    test('parses enhanced LRC <mm:ss.xx> word timing in ascending order', () {
      const enhancedLrc = '''
[00:10.00]<00:10.00>He<00:10.40>llo <00:10.80>world<00:11.50>
[00:15.00]<00:15.00>Next <00:15.50>line<00:16.20>
''';

      final doc = LyricParser.parse(enhancedLrc);

      expect(doc.hasWordTiming, isTrue);
      expect(doc.lines, hasLength(2));

      final firstWords = doc.lines[0].words!;
      expect(firstWords.length, greaterThanOrEqualTo(3));
      expect(firstWords.map((w) => w.text).join(), contains('Hello world'));

      for (var i = 0; i < firstWords.length; i++) {
        final w = firstWords[i];
        expect(w.startMs, lessThanOrEqualTo(w.endMs));
        if (i > 0) {
          expect(w.startMs, greaterThanOrEqualTo(firstWords[i - 1].startMs));
          expect(w.startMs, greaterThanOrEqualTo(firstWords[i - 1].endMs));
        }
      }
    });

    test('parses KRC [start,dur]<off,dur>word format', () {
      const krc = '''
[ti:KRC Demo]
[1000,2000]<0,500>你<500,600>好<1100,900>世界
[3500,1500]<0,700>再<700,800>见
''';

      final doc = LyricParser.parse(krc);

      expect(doc.hasWordTiming, isTrue);
      expect(doc.lines, hasLength(2));

      final line0 = doc.lines[0];
      expect(line0.startMs, 1000);
      expect(line0.endMs, 3000);
      expect(line0.text, '你好世界');
      expect(line0.words, hasLength(3));

      expect(line0.words![0].text, '你');
      expect(line0.words![0].startMs, 1000);
      expect(line0.words![0].endMs, 1500);

      expect(line0.words![1].text, '好');
      expect(line0.words![1].startMs, 1500);
      expect(line0.words![1].endMs, 2100);

      expect(line0.words![2].text, '世界');
      expect(line0.words![2].startMs, 2100);
      expect(line0.words![2].endMs, 3000);
    });

    test('parses YRC/QRC [start,dur](start,dur)word format', () {
      const yrc = '''
[2000,2500](2000,500)Soda(2500,1000)Pulse(3500,1000)Music
[5000,1200](5000,600)Flu(5600,600)tter
''';

      final doc = LyricParser.parse(yrc);

      expect(doc.hasWordTiming, isTrue);
      expect(doc.lines, hasLength(2));

      final line0 = doc.lines[0];
      expect(line0.startMs, 2000);
      expect(line0.endMs, 4500);
      expect(line0.text, 'SodaPulseMusic');
      expect(line0.words, hasLength(3));

      expect(line0.words![0].text, 'Soda');
      expect(line0.words![0].startMs, 2000);
      expect(line0.words![0].endMs, 2500);

      expect(line0.words![1].text, 'Pulse');
      expect(line0.words![1].startMs, 2500);
      expect(line0.words![1].endMs, 3500);

      expect(line0.words![2].text, 'Music');
      expect(line0.words![2].startMs, 3500);
      expect(line0.words![2].endMs, 4500);
    });

    test('aligns bilingual translation within ±150ms and builds complete native payload', () {
      const bilingualLrc = '''
[00:10.00]Hello world
[00:10.12]你好世界
[00:20.00]Good night
[00:19.88]晚安
[00:30.00]Far apart line
[00:30.50]Unrelated next line
''';

      final doc = LyricParser.parse(bilingualLrc);

      expect(doc.lines.length, greaterThanOrEqualTo(3));

      final first = doc.lines.firstWhere((l) => l.text == 'Hello world');
      expect(first.translation, '你好世界');

      final second = doc.lines.firstWhere((l) => l.text == 'Good night');
      expect(second.translation, '晚安');

      final third = doc.lines.firstWhere((l) => l.text == 'Far apart line');
      expect(third.translation, isNull);

      final payload = doc.toNativePayload();
      expect(payload, isA<Map<String, dynamic>>());
      expect(payload.containsKey('hasWordTiming'), isTrue);
      expect(payload.containsKey('lines'), isTrue);

      final payloadLines = payload['lines'] as List<dynamic>;
      expect(payloadLines, isNotEmpty);

      final firstMap = payloadLines.first as Map<String, dynamic>;
      expect(firstMap.containsKey('startMs'), isTrue);
      expect(firstMap.containsKey('endMs'), isTrue);
      expect(firstMap.containsKey('text'), isTrue);
      expect(firstMap.containsKey('translation'), isTrue);
      expect(firstMap.containsKey('words'), isTrue);
      expect(firstMap['text'], 'Hello world');
      expect(firstMap['translation'], '你好世界');
    });

    test('handles empty string, out-of-order timestamps, and negative values safely', () {
      final emptyDoc = LyricParser.parse('');
      expect(emptyDoc.lines, isEmpty);
      expect(emptyDoc.hasWordTiming, isFalse);

      const messyLrc = '''
[offset:-99999]
[00:20.00]Later line
[00:05.00]Earlier line
[-100,500](-50,200)Neg
[invalid]Broken tag
''';

      expect(() => LyricParser.parse(messyLrc), returnsNormally);
      final messyDoc = LyricParser.parse(messyLrc);

      for (var i = 0; i < messyDoc.lines.length; i++) {
        final line = messyDoc.lines[i];
        expect(line.startMs, greaterThanOrEqualTo(0));
        expect(line.endMs, greaterThanOrEqualTo(line.startMs));
        if (i > 0) {
          expect(line.startMs, greaterThanOrEqualTo(messyDoc.lines[i - 1].startMs));
        }
      }
    });

    test('LyricParser.demoLyrics() is non-empty and has word timing', () {
      final demo = LyricParser.demoLyrics();

      expect(demo.lines, isNotEmpty);
      expect(demo.hasWordTiming, isTrue);
      expect(
        demo.lines.any((LyricLine line) => line.words != null && line.words!.isNotEmpty),
        isTrue,
      );
    });
  });
}
