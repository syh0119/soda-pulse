import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/models/track.dart';

const Color _sheetBg = Color(0xFF121826);

Future<T?> _showSodaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetContext) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: _sheetBg.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: builder(sheetContext),
            ),
          ),
        ),
      );
    },
  );
}

Widget _sheetHandle() {
  return Center(
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 14),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

Widget _sheetHeader(String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
}

Color _accentOf(BuildContext context) {
  return Theme.of(context).colorScheme.primary;
}

Future<void> showQueueSheet(BuildContext context, AppStore store) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.65;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final queue = store.queue;
            final currentId = store.currentTrack?.id;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader('待播列表 (${queue.length})'),
                if (queue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      '暂无待播歌曲',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: queue.length,
                      itemBuilder: (itemContext, index) {
                        final track = queue[index];
                        final isCurrent = currentId == track.id;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? accent.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Icon(
                              isCurrent
                                  ? Icons.equalizer_rounded
                                  : Icons.music_note_rounded,
                              color: isCurrent
                                  ? accent
                                  : Colors.white.withValues(alpha: 0.55),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? accent : Colors.white,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? accent.withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              store.playTrackFromQueue(index);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showSoundEffectSheet(BuildContext context, AppStore store) {
  const bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.8;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final gains = List<double>.from(store.eqGains);
            final preGain = store.eqPreGain;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  _sheetHeader('品牌调音 · 实时生效'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '峰值包络限幅防爆音 · 5 段参数均衡实时生效',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SoundFxPresets.all.map((preset) {
                        final selected = store.eqPresetId == preset.id;
                        return FilterChip(
                          label: Text(preset.name),
                          selected: selected,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          selectedColor: accent.withValues(alpha: 0.35),
                          side: BorderSide(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (isSelected) {
                            store.applyEqPreset(preset.id);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(bandLabels.length, (index) {
                    final value = index < gains.length
                        ? gains[index].clamp(-12.0, 12.0)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(
                              bandLabels[index],
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: value,
                              min: -12,
                              max: 12,
                              divisions: 48,
                              activeColor: accent,
                              inactiveColor:
                                  Colors.white.withValues(alpha: 0.15),
                              onChanged: (newVal) {
                                final updated = List<double>.from(gains);
                                while (updated.length < bandLabels.length) {
                                  updated.add(0.0);
                                }
                                updated[index] = newVal;
                                store.setCustomEq(updated, preGain);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}dB',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            '前级',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: preGain.clamp(-12.0, 6.0),
                            min: -12,
                            max: 6,
                            divisions: 36,
                            activeColor: accent,
                            inactiveColor:
                                Colors.white.withValues(alpha: 0.15),
                            onChanged: (newVal) {
                              store.setCustomEq(gains, newVal);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${preGain >= 0 ? '+' : ''}${preGain.toStringAsFixed(1)}dB',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Future<void> showSleepAndSpeedSheet(BuildContext context, AppStore store) {
  const sleepOptions = [
    (label: '关闭', minutes: 0),
    (label: '15分钟', minutes: 15),
    (label: '30分钟', minutes: 30),
    (label: '45分钟', minutes: 45),
    (label: '60分钟', minutes: 60),
  ];
  const speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final speed = store.playbackSpeed.clamp(0.5, 2.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                _sheetHeader('定时关闭与倍速'),
                if (store.sleepTimerRemaining != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        width: 108,
                        height: 108,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: CircularProgressIndicator(
                                value: store.sleepTimerProgress,
                                strokeWidth: 6,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(accent),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${store.sleepTimerRemaining!.inMinutes.toString().padLeft(2, '0')}:${(store.sleepTimerRemaining!.inSeconds % 60).toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '剩余时间',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    '定时关闭',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...sleepOptions.map((option) {
                        final selected = option.minutes == 0
                            ? store.sleepTimerRemaining == null
                            : store.sleepTimerTotal?.inMinutes == option.minutes;
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: selected,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          selectedColor: accent.withValues(alpha: 0.35),
                          side: BorderSide(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (isSelected) {
                            store.setSleepTimer(
                              option.minutes <= 0
                                  ? null
                                  : Duration(minutes: option.minutes),
                            );
                          },
                        );
                      }),
                      ActionChip(
                        label: const Text('自定义'),
                        labelStyle: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: accent.withValues(alpha: 0.14),
                        side: BorderSide(color: accent.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onPressed: () async {
                          final ctrl = TextEditingController();
                          final mins = await showDialog<int>(
                            context: sheetContext,
                            builder: (dCtx) => AlertDialog(
                              backgroundColor: _sheetBg,
                              title: const Text(
                                '自定义定时（分钟）',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                autofocus: true,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: '1 ~ 240',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dCtx).pop(),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final v = int.tryParse(ctrl.text.trim());
                                    if (v != null && v > 0 && v <= 240) {
                                      Navigator.of(dCtx).pop(v);
                                    }
                                  },
                                  child: Text('确定', style: TextStyle(color: accent)),
                                ),
                              ],
                            ),
                          );
                          ctrl.dispose();
                          if (mins != null) {
                            store.setSleepTimer(Duration(minutes: mins));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  activeThumbColor: accent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text(
                    '播完当前单曲后暂停',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  value: store.stopAfterCurrent,
                  onChanged: store.setStopAfterCurrent,
                ),
                const Divider(color: Colors.white12, height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '播放倍速',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${speed.toStringAsFixed(2)}x',
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Slider(
                    value: speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 30,
                    activeColor: accent,
                    inactiveColor: Colors.white.withValues(alpha: 0.15),
                    onChanged: store.setPlaybackSpeed,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: speedOptions.map((val) {
                      final selected = (speed - val).abs() < 0.01;
                      return ChoiceChip(
                        label: Text('${val}x'),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        selectedColor: accent.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (isSelected) {
                          store.setPlaybackSpeed(val);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showSmartRecommendSheet(BuildContext context, AppStore store) {
  const modeMeta = [
    (title: '默认模式', desc: '均衡推荐熟悉旋律与新鲜发现，保持顺滑听感'),
    (title: '熟悉模式', desc: '优先播放红心收藏与高频循环的偏爱曲目'),
    (title: '新鲜模式', desc: '更多探索未听过的新歌与小众宝藏作品'),
  ];

  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final modes = RecommendMode.values;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader('智能推荐模式'),
                ...List.generate(modes.length, (index) {
                  final mode = modes[index];
                  final meta = index < modeMeta.length
                      ? modeMeta[index]
                      : (title: mode.name, desc: '');
                  final selected = store.recommendMode == mode;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        store.setRecommendMode(mode);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    meta.title,
                                    style: TextStyle(
                                      color: selected ? accent : Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    meta.desc,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.65),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check_circle_rounded, color: accent),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  AppStore store,
  Track track,
) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.65;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final playlists = store.playlists;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader(
                  '添加到歌单',
                  trailing: TextButton.icon(
                    onPressed: () async {
                      final controller = TextEditingController();
                      final name = await showDialog<String>(
                        context: sheetContext,
                        builder: (dialogContext) {
                          return AlertDialog(
                            backgroundColor: _sheetBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: const Text(
                              '新建歌单',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '输入歌单名称',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accent),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final trimmed = controller.text.trim();
                                  if (trimmed.isNotEmpty) {
                                    Navigator.of(dialogContext).pop(trimmed);
                                  }
                                },
                                child: Text(
                                  '创建',
                                  style: TextStyle(color: accent),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                      controller.dispose();
                      if (name != null && name.isNotEmpty) {
                        final id = await store.createPlaylist(name);
                        if (id.isNotEmpty) {
                          await store.addTrackToPlaylist(id, track);
                        }
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      }
                    },
                    icon: Icon(Icons.add_rounded, color: accent, size: 18),
                    label: Text(
                      '新建歌单',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      '暂无歌单，点击右上角新建',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: playlists.length,
                      itemBuilder: (itemContext, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: accent,
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${playlist.trackIds.length} 首歌曲',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            store.addTrackToPlaylist(playlist.id, track);
                            Navigator.of(sheetContext).pop();
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showSkinAndLayoutSheet(BuildContext context, AppStore store) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final styles = PlayerStyle.values;
          final skins = AppSkin.values;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                _sheetHeader('皮肤、布局与车机版式'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    '播放器布局（共用同一队列）',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: List.generate(styles.length, (index) {
                      final style = styles[index];
                      final selected = store.playerStyle == style;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index == styles.length - 1 ? 0 : 8,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => store.setPlayerStyle(style),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? accent
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                style.label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '动态皮肤',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: skins.map((skin) {
                      final selected = store.appSkin == skin;
                      return ChoiceChip(
                        label: Text(skin.label),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        selectedColor: accent.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (isSelected) => store.setAppSkin(skin),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '底栏样式 & 车机大字版式',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...BottomBarStyle.values.map((bs) {
                        final sel = store.bottomBarStyle == bs;
                        return ChoiceChip(
                          label: Text(bs.label),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: accent.withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                          onSelected: (_) => store.setBottomBarStyle(bs),
                        );
                      }),
                      ...CarLayoutMode.values.map((cm) {
                        final sel = store.carLayoutMode == cm;
                        return ChoiceChip(
                          label: Text('车机:${cm.label}'),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: accent.withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                          onSelected: (_) => store.setCarLayoutMode(cm),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  activeThumbColor: accent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text(
                    '纯净模式',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  subtitle: Text(
                    '隐藏多余操作按钮，专注音乐与歌词',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  value: store.pureMode,
                  onChanged: store.setPureMode,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showTrackOptionsSheet(
  BuildContext context,
  AppStore store,
  Track track,
) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final isFav = store.isFavorite(track.id);
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${track.artist} · ${track.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              title: const Text('立即播放', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.playTrack(track);
              },
            ),
            ListTile(
              leading: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? const Color(0xFFFF4D6D) : Colors.white,
              ),
              title: Text(
                isFav ? '取消喜欢' : '添加到我喜欢',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.toggleFavorite(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: Colors.white),
              title: const Text('添加到歌单', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAddToPlaylistSheet(context, store, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Colors.white),
              title: const Text('分享歌曲', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.bridge.shareText(
                  '${track.title} - ${track.artist}',
                  subject: track.title,
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
