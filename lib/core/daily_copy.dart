class DailyGreeting {
  final String title;
  final String subtitle;

  const DailyGreeting({
    required this.title,
    required this.subtitle,
  });
}

class DailyCopy {
  const DailyCopy._();

  static DailyGreeting forHour(int hour) {
    final normalizedHour = ((hour % 24) + 24) % 24;

    if (normalizedHour >= 5 && normalizedHour <= 10) {
      return const DailyGreeting(
        title: '早安 · 清晨的第一首歌',
        subtitle: '把还没醒透的清晨，交给旋律慢慢唤醒',
      );
    }
    if (normalizedHour >= 11 && normalizedHour <= 13) {
      return const DailyGreeting(
        title: '午安 · 正午微风',
        subtitle: '忙里偷闲听一首，给耳朵放个短假',
      );
    }
    if (normalizedHour >= 14 && normalizedHour <= 17) {
      return const DailyGreeting(
        title: '午后 · 日光慢拍',
        subtitle: '那些安静听歌的时刻，都是音乐在温柔陪伴你',
      );
    }
    if (normalizedHour >= 18 && normalizedHour <= 22) {
      return const DailyGreeting(
        title: '傍晚到入夜 · 霓虹微醺',
        subtitle: '夜色渐深，让喜欢的歌陪你走完这一程',
      );
    }
    return const DailyGreeting(
      title: '夜深了 · 夜晚属于音乐',
      subtitle: '夜深人静时的旋律，最懂没说出口的心事',
    );
  }

  static DailyGreeting now() => forHour(DateTime.now().hour);

  static const List<String> listeningQuotes = <String>[
    '那些安静听歌的时刻，都是音乐在替你接住情绪。',
    '耳机一戴，世界自动静音，只剩心跳和副歌同频。',
    '单曲循环的不是旋律，而是某段舍不得翻篇的记忆。',
    '好听的歌像气泡水，每一次重逢都还是清冽上头。',
    '黑夜很长，但幸好歌单里总有一首能陪你走到天亮。',
    '不必刻意记住时间，你听过的每一首歌都替你记着。',
  ];
}
