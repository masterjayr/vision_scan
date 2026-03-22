import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:vision_scan/src/engine/qr_engine.dart';
import 'package:vision_scan/utils/image_pro_utils.dart';

/// Full-screen camera that decodes the first QR via [QrEngine.scanFromGray] and pops with the string.
class SimpleQrScanPage extends StatefulWidget {
  const SimpleQrScanPage({super.key});

  @override
  State<SimpleQrScanPage> createState() => _SimpleQrScanPageState();
}

class _SimpleQrScanPageState extends State<SimpleQrScanPage> {
  CameraController? _controller;
  CameraImage? _latestImage;
  bool _isProcessing = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await QrEngine.init();
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _controller = CameraController(
      backCamera,
      Platform.isIOS ? ResolutionPreset.high : ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
    await _controller!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage image) {
    if (_done) return;
    _latestImage = image;
    if (!_isProcessing) {
      _isProcessing = true;
      _processLatest();
    }
  }

  Future<void> _processLatest() async {
    while (_latestImage != null && !_done) {
      final image = _latestImage!;
      _latestImage = null;

      try {
        final gray = Platform.isAndroid
            ? androidYPlaneToGray(image)
            : bgraToGray(image);

        final text = await QrEngine.scanFromGray(
          gray,
          image.width,
          image.height,
        );
        if (text != null && mounted) {
          _done = true;
          await _stopCamera();
          if (mounted) Navigator.of(context).pop<String>(text);
          return;
        }
      } catch (e) {
        debugPrint('Simple scan error: $e');
      }
    }
    _isProcessing = false;
  }

  Future<void> _stopCamera() async {
    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR (decode only)'),
      ),
      body: c == null || !c.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                Center(child: CameraPreview(c)),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Text(
                    'Point at a QR code',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(blurRadius: 4, color: Colors.black),
                          ],
                        ),
                  ),
                ),
              ],
            ),
    );
  }
}
