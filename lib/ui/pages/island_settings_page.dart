import 'package:flutter/material.dart';
import 'package:soda_pulse/services/native_bridge.dart';

class IslandSettingsPage extends StatefulWidget {
  const IslandSettingsPage({super.key, NativePlayerBridge? bridge})
      : _bridge = bridge;

  final NativePlayerBridge? _bridge;

  @override
  State<IslandSettingsPage> createState() => _IslandSettingsPageState();
}

class _IslandSettingsPageState extends State<IslandSettingsPage> {
  static const Color _bgDeep = Color(0xFF090D16);
  static const Color _bgCard = Color(0xFF121A2B);
  static const Color _bgCardElevated = Color(0xFF182238);
  static const Color _sodaCyan = Color(0xFF38BDF8);
  static const Color _sodaMint = Color(0xFF2DD4BF);
  static const Color _sodaIndigo = Color(0xFF818CF8);
  static const Color _sodaAmber = Color(0xFFFBBF24);
  static const Color _sodaRose = Color(0xFFFB7185);

  static const List<_ModeOption> _modeOptions = <_ModeOption>[
    _ModeOption(
      wire: 'auto',
      title: '自动智能优先 (auto)',
      subtitle: '自动优先 SuperLyric -> ColorOS lyricInfo',
      icon: Icons.auto_awesome_rounded,
    ),
    _ModeOption(
      wire: 'lyric_info',
      title: 'ColorOS lyricInfo 原生通道',
      subtitle: '写入 MediaMetadata["lyricInfo"] 适配流体云与锁屏',
      icon: Icons.album_rounded,
    ),
    _ModeOption(
      wire: 'super_lyric',
      title: 'SuperLyric 5.0 直推',
      subtitle: 'HChenX SuperLyricApi 5.0 Binder 整首逐字推送',
      icon: Icons.bolt_rounded,
    ),
    _ModeOption(
      wire: 'ticker',
      title: '状态栏 Ticker',
      subtitle: '通用通知栏 Ticker + FLAG_ALWAYS_SHOW_TICKER',
      icon: Icons.notifications_active_rounded,
    ),
    _ModeOption(
      wire: 'overlay',
      title: '桌面悬浮歌词',
      subtitle: '使用独立悬浮窗在任意应用上方显示逐字歌词',
      icon: Icons.layers_rounded,
    ),
  ];

  NativePlayerBridge get _bridge =>
      widget._bridge ?? NativePlayerBridge.instance;

  EnvironmentStatus? _status;
  bool _loading = true;
  String? _errorMessage;

  String _selectedModeWire = 'auto';
  bool _overlayEnabled = false;
  bool _overlayLocked = false;
  double _fontSizeSp = 16.0;
  int _yOffsetPx = 120;
  int _lyricOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  String _normalizeModeWire(Object? mode) {
    final raw = mode?.toString() ?? 'auto';
    if (raw.contains('.')) {
      final tail = raw.split('.').last;
      if (tail == 'superLyric') return 'super_lyric';
      if (tail == 'lyricInfo') return 'lyric_info';
      return tail;
    }
    return raw;
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final status = await _bridge.getEnvironmentStatus();
      if (!mounted) return;
      final normalizedSelected = _normalizeModeWire(status.selectedMode);
      setState(() {
        _status = status;
        _selectedModeWire = normalizedSelected;
        _overlayEnabled = normalizedSelected == 'overlay';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '获取环境诊断信息失败: $e';
      });
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _bridge.requestPermissions();
      await _refreshStatus();
    } catch (e) {
      _showSnack('申请基础权限失败: $e');
    }
  }

  Future<void> _requestOverlayPermission() async {
    try {
      await _bridge.requestOverlayPermission();
      await _refreshStatus();
    } catch (e) {
      _showSnack('申请悬浮窗权限失败: $e');
    }
  }

  Future<void> _selectMode(String wireValue) async {
    setState(() {
      _selectedModeWire = wireValue;
      if (wireValue == 'overlay') {
        _overlayEnabled = true;
      } else if (wireValue == 'off') {
        _overlayEnabled = false;
      }
    });

    try {
      await _bridge.setLyricMode(LyricIslandMode.fromWire(wireValue));
      await _refreshStatus();
    } catch (e) {
      _showSnack('切换歌词模式失败: $e');
    }
  }

  Future<void> _applyOverlayConfig() async {
    try {
      await _bridge.setOverlayConfig(
        enabled: _overlayEnabled,
        locked: _overlayLocked,
        fontSizeSp: _fontSizeSp,
        yOffsetPx: _yOffsetPx,
      );
    } catch (e) {
      _showSnack('更新悬浮窗配置失败: $e');
    }
  }

  Future<void> _applyLyricOffset(int ms) async {
    final clamped = ms.clamp(-3000, 3000);
    setState(() {
      _lyricOffsetMs = clamped;
    });
    try {
      await _bridge.setLyricOffset(clamped);
    } catch (e) {
      _showSnack('设置歌词偏移失败: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _bgCardElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      body: Stack(
        children: <Widget>[
          _buildSodaBackground(),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                _buildAppBar(),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      if (_errorMessage != null) _buildErrorBanner(),
                      _buildDiagnosticsCard(),
                      const SizedBox(height: 16),
                      _buildPermissionsCard(),
                      const SizedBox(height: 16),
                      _buildModeSelectorCard(),
                      const SizedBox(height: 16),
                      _buildOverlayConfigCard(),
                      const SizedBox(height: 16),
                      _buildLyricOffsetCard(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSodaBackground() {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -90,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    _sodaCyan.withValues(alpha: 0.18),
                    _sodaCyan.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 280,
            left: -100,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    _sodaMint.withValues(alpha: 0.14),
                    _sodaMint.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    _sodaIndigo.withValues(alpha: 0.16),
                    _sodaIndigo.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      title: const Text(
        '歌词岛与诊断中心',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: <Widget>[
        IconButton(
          tooltip: '刷新环境状态',
          onPressed: _loading ? null : _refreshStatus,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _sodaCyan,
                  ),
                )
              : const Icon(Icons.refresh_rounded, color: _sodaCyan),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _sodaRose.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _sodaRose.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: _sodaRose, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _bgCard.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _sodaCyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _sodaCyan, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard() {
    final status = _status;
    return _buildGlassCard(
      title: '系统环境诊断',
      icon: Icons.monitor_heart_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _sodaMint.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _sodaMint.withValues(alpha: 0.35)),
        ),
        child: Text(
          status == null ? '检测中' : 'SDK ${status.androidSdk}',
          style: const TextStyle(
            color: _sodaMint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      children: status == null
          ? <Widget>[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: _sodaCyan),
                ),
              ),
            ]
          : <Widget>[
              _buildDiagRow('设备型号', '${status.brand} ${status.model}'),
              _buildDiagRow(
                'SuperLyric 状态',
                '${status.superLyricStatus} (v${status.superLyricVersion})',
              ),
              _buildDiagRow(
                '当前生效模式',
                _normalizeModeWire(status.activeMode),
              ),
              _buildDiagRow(
                '用户预设模式',
                _normalizeModeWire(status.selectedMode),
              ),
              _buildDiagRow(
                '最近发布结果',
                status.lastPublishResult.isEmpty
                    ? '暂无记录'
                    : status.lastPublishResult,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _buildStatusChip('悬浮窗权限', status.canDrawOverlay),
                  _buildStatusChip('音频权限', status.hasAudioPerm),
                  _buildStatusChip('通知权限', status.hasNotifPerm),
                ],
              ),
            ],
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, bool granted) {
    final color = granted ? _sodaMint : _sodaAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ${granted ? '已授权' : '未授权'}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard() {
    final status = _status;
    final hasBasePerms =
        (status?.hasAudioPerm ?? false) && (status?.hasNotifPerm ?? false);
    final canOverlay = status?.canDrawOverlay ?? false;

    return _buildGlassCard(
      title: '权限申请与授权',
      icon: Icons.verified_user_rounded,
      children: <Widget>[
        _buildPermissionTile(
          title: '音频与通知权限',
          subtitle: '用于音频焦点监听、媒体会话同步与通知栏歌词推送',
          granted: hasBasePerms,
          buttonText: hasBasePerms ? '重新检查' : '立即授权',
          onPressed: _requestPermissions,
        ),
        const SizedBox(height: 10),
        _buildPermissionTile(
          title: '悬浮窗显示权限',
          subtitle: '用于在桌面及其他应用上层绘制悬浮歌词窗口',
          granted: canOverlay,
          buttonText: canOverlay ? '已开启' : '前往开启',
          onPressed: _requestOverlayPermission,
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool granted,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCardElevated.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: granted
                  ? _sodaMint.withValues(alpha: 0.2)
                  : _sodaCyan.withValues(alpha: 0.24),
              foregroundColor: granted ? _sodaMint : _sodaCyan,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelectorCard() {
    return _buildGlassCard(
      title: '歌词推送模式（四模互斥）',
      icon: Icons.tune_rounded,
      children: _modeOptions.map((option) {
        final selected = _selectedModeWire == option.wire;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _selectMode(option.wire),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? _sodaCyan.withValues(alpha: 0.14)
                    : _bgCardElevated.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _sodaCyan.withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.06),
                  width: selected ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    option.icon,
                    color: selected ? _sodaCyan : Colors.white.withValues(alpha: 0.65),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          option.title,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          option.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? _sodaCyan : Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOverlayConfigCard() {
    return _buildGlassCard(
      title: '桌面悬浮窗配置',
      icon: Icons.picture_in_picture_alt_rounded,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: _sodaCyan,
          title: const Text(
            '启用悬浮窗歌词',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            '在桌面与第三方应用上方显示独立歌词条',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
          ),
          value: _overlayEnabled,
          onChanged: (value) {
            setState(() => _overlayEnabled = value);
            _applyOverlayConfig();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: _sodaMint,
          title: const Text(
            '锁定悬浮窗位置',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            '开启后允许触摸穿透，防止游戏或刷视频时误触拖动',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
          ),
          value: _overlayLocked,
          onChanged: (value) {
            setState(() => _overlayLocked = value);
            _applyOverlayConfig();
          },
        ),
        const SizedBox(height: 8),
        _buildSliderHeader('歌词字号', '${_fontSizeSp.toStringAsFixed(1)} sp'),
        Slider(
          value: _fontSizeSp,
          min: 12.0,
          max: 32.0,
          divisions: 40,
          activeColor: _sodaCyan,
          inactiveColor: Colors.white12,
          onChanged: (value) {
            setState(() => _fontSizeSp = value);
          },
          onChangeEnd: (_) => _applyOverlayConfig(),
        ),
        const SizedBox(height: 6),
        _buildSliderHeader('垂直偏移 (Y Offset)', '$_yOffsetPx px'),
        Slider(
          value: _yOffsetPx.toDouble(),
          min: 0,
          max: 600,
          divisions: 60,
          activeColor: _sodaMint,
          inactiveColor: Colors.white12,
          onChanged: (value) {
            setState(() => _yOffsetPx = value.round());
          },
          onChangeEnd: (_) => _applyOverlayConfig(),
        ),
      ],
    );
  }

  Widget _buildLyricOffsetCard() {
    final sign = _lyricOffsetMs > 0 ? '+' : '';
    return _buildGlassCard(
      title: '歌词时间轴微调',
      icon: Icons.av_timer_rounded,
      children: <Widget>[
        _buildSliderHeader('全局时间偏移', '$sign$_lyricOffsetMs ms'),
        Slider(
          value: _lyricOffsetMs.toDouble(),
          min: -3000,
          max: 3000,
          divisions: 120,
          activeColor: _sodaIndigo,
          inactiveColor: Colors.white12,
          onChanged: (value) {
            setState(() => _lyricOffsetMs = value.round());
          },
          onChangeEnd: (value) => _applyLyricOffset(value.round()),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _buildOffsetButton('-100 ms', () => _applyLyricOffset(_lyricOffsetMs - 100)),
            _buildOffsetButton('重置 0 ms', () => _applyLyricOffset(0)),
            _buildOffsetButton('+100 ms', () => _applyLyricOffset(_lyricOffsetMs + 100)),
          ],
        ),
      ],
    );
  }

  Widget _buildSliderHeader(String title, String valueText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          valueText,
          style: const TextStyle(
            color: _sodaCyan,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _ModeOption {
  const _ModeOption({
    required this.wire,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String wire;
  final String title;
  final String subtitle;
  final IconData icon;
}
