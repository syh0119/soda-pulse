import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soda_pulse/core/app_store.dart';

class QrPluginImportPage extends StatefulWidget {
  const QrPluginImportPage({super.key, required this.store});

  final AppStore store;

  @override
  State<QrPluginImportPage> createState() => _QrPluginImportPageState();
}

class _QrPluginImportPageState extends State<QrPluginImportPage> {
  static const _bgColor = Color(0xFF0E1512);
  static const _cardColor = Color(0xFF151D19);
  static const _borderColor = Color(0xFF24332C);
  static const _emerald = Color(0xFF34D399);
  static const _darkGreenBtn = Color(0xFF1A2E25);

  final TextEditingController _inputController = TextEditingController();
  Uint8List? _qrPngBytes;
  bool _busy = false;

  AppStore get store => widget.store;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor:
            isError ? const Color(0xFF7F1D1D) : const Color(0xFF1B3A2D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _importRawQr(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _showSnack('二维码内容为空', isError: true);
      return;
    }
    final result = await store.importPluginsFromQrPayload(trimmed);
    if (!mounted) return;
    if (result.imported.isEmpty) {
      _showSnack(result.firstError ?? '未导入任何音源插件', isError: true);
      return;
    }
    final msg = result.imported.length == 1 && result.failedCount == 0
        ? '已导入音源：${result.imported.first.name}'
        : result.failedCount > 0
            ? '成功导入 ${result.imported.length} 个音源，${result.failedCount} 个失败'
            : '已批量导入 ${result.imported.length} 个音源插件';
    _showSnack(msg);
  }

  Future<void> _scanWithCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final raw = await store.bridge.scanQrCode();
      if (!mounted || raw == null || raw.trim().isEmpty) return;
      await _importRawQr(raw);
    } on PlatformException catch (e) {
      _showSnack(e.message ?? '相机扫码失败', isError: true);
    } catch (e) {
      _showSnack('导入失败：${e.toString().replaceFirst('FormatException: ', '')}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final raw = await store.bridge.pickQrImage();
      if (!mounted || raw == null || raw.trim().isEmpty) return;
      await _importRawQr(raw);
    } on PlatformException catch (e) {
      if (e.code == 'QR_NOT_FOUND') {
        _showSnack('未在所选图片中识别到二维码', isError: true);
      } else {
        _showSnack(e.message ?? '相册识图失败', isError: true);
      }
    } catch (e) {
      _showSnack('导入失败：${e.toString().replaceFirst('FormatException: ', '')}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _generateQr([String? overrideText]) async {
    if (_busy) return;
    final text = (overrideText ?? _inputController.text).trim();
    if (text.isEmpty) {
      _showSnack('请先输入音源链接或脚本内容', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await store.bridge.generateQrPng(text, size: 640);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _showSnack('生成二维码失败', isError: true);
        return;
      }
      setState(() => _qrPngBytes = bytes);
      _showSnack('二维码已生成');
    } on PlatformException catch (e) {
      _showSnack(e.message ?? '生成二维码失败', isError: true);
    } catch (e) {
      _showSnack('生成二维码失败：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickJsFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? payloadToGenerate;
    try {
      final file = await store.bridge.pickTextFile();
      if (!mounted || file == null) return;

      final content = (file['content'] ?? '').trim();
      if (content.isEmpty) {
        _showSnack('所选文件内容为空', isError: true);
        return;
      }

      final srcUrlMatch = RegExp(
        r'''['"]?srcUrl['"]?\s*:\s*['"](https?://[^'"]+)['"]''',
      ).firstMatch(content);
      final srcUrl = srcUrlMatch?.group(1)?.trim();

      if (srcUrl != null && srcUrl.isNotEmpty) {
        payloadToGenerate = srcUrl;
      } else {
        final dataUri =
            'data:text/javascript;base64,${base64Encode(utf8.encode(content))}';
        if (dataUri.length < 1800) {
          payloadToGenerate = dataUri;
        } else {
          _showSnack('脚本超过 1800 字符且未包含 srcUrl，无法直接生成二维码', isError: true);
          return;
        }
      }

      _inputController.text = payloadToGenerate;
    } on PlatformException catch (e) {
      _showSnack(e.message ?? '读取 JS 文件失败', isError: true);
      return;
    } catch (e) {
      _showSnack('读取 JS 文件失败：$e', isError: true);
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    if (mounted) {
      await _generateQr(payloadToGenerate);
    }
  }

  Future<void> _copyInput() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showSnack('当前没有可复制的内容', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showSnack('已复制到剪贴板');
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('扫码导入'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _scanWithCamera,
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text(
                            '打开相机扫码',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _emerald,
                            foregroundColor: const Color(0xFF062016),
                            disabledBackgroundColor:
                                _emerald.withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text(
                            '从相册选图识别',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _darkGreenBtn,
                            foregroundColor: _emerald,
                            disabledBackgroundColor:
                                _darkGreenBtn.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                            side: const BorderSide(color: _borderColor),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              color: _emerald,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '把音源链接 / 脚本变成二维码',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '粘贴音源链接或选择 .js 脚本，生成标准可扫码导入的二维码，另一台设备打开「扫码导入」即可导入',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _inputController,
                          minLines: 2,
                          maxLines: 3,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'https://raw.githubusercontent.com/.../plugin.js',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.32),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: _bgColor,
                            contentPadding: const EdgeInsets.all(14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: _emerald, width: 1.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _busy ? null : () => _generateQr(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _emerald,
                                  foregroundColor: const Color(0xFF062016),
                                  disabledBackgroundColor:
                                      _emerald.withValues(alpha: 0.4),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: const StadiumBorder(),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '生成二维码',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _busy ? null : _pickJsFile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _darkGreenBtn,
                                  foregroundColor: _emerald,
                                  disabledBackgroundColor:
                                      _darkGreenBtn.withValues(alpha: 0.5),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: const StadiumBorder(),
                                  side: const BorderSide(color: _borderColor),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '选 JS 文件',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                onPressed: _busy ? null : _copyInput,
                                icon: const Icon(Icons.copy_rounded, size: 20),
                                color: _emerald,
                                style: IconButton.styleFrom(
                                  backgroundColor: _darkGreenBtn,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: _borderColor),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_qrPngBytes != null) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.memory(
                                    _qrPngBytes!,
                                    width: 220,
                                    height: 220,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    '让另一台设备打开「扫码导入」扫这张图',
                                    style: TextStyle(
                                      color: Color(0xFF1F2937),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_emerald),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
