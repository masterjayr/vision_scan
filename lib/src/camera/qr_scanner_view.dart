import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:vision_scan/src/engine/qr_engine.dart';
import 'package:vision_scan/utils/image_pro_utils.dart';
import 'package:flutter/material.dart';

typedef QRDetectCallback = void Function(String result);

class QrScannerView extends StatefulWidget {
  final QRDetectCallback onDetect;
  final bool stopOnDetect;

  const QrScannerView({
    Key? key,
    required this.onDetect,
    this.stopOnDetect = true,
  }) : super(key: key);

  @override
  State<QrScannerView> createState() => _QRScannerViewState();
}

class _QRScannerViewState extends State<QrScannerView> {
  CameraController? _controller;
  bool _isDetecting = false;
  bool _found = false;
  bool _showPreview = true;

  @override
  void initState() {
    super.initState();
    QrEngine.init();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();

    if (!mounted) return;

    setState(() {});

    _controller!.startImageStream(_processFrame);
  }

  void _processFrame(CameraImage image) async {
    if (_isDetecting || _found) return;

    _isDetecting = true;

    try {
      Uint8List gray;
      if (Platform.isAndroid) {
        final plane = image.planes[0];

        final bytes = plane.bytes;

        final int width = image.width;
        final int height = image.height;
        final int rowStride = plane.bytesPerRow;
        gray = Uint8List(width * height);

        int offset = 0;

        for (int row = 0; row < height; row++) {
          final int rowStart = row * rowStride;
          gray.setRange(offset, offset + width, bytes, rowStart);
          offset += width;
        }
      } else if (Platform.isIOS) {
        gray = bgraToGray(image);
      } else {
        return;
      }
      final result = await QrEngine.decodeFromGray(
        gray,
        image.width,
        image.height,
      );

      if (result != null) {
        _found = true;
        widget.onDetect(result);

        if (widget.stopOnDetect) {
          setState(() {
            _showPreview = false;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _stopCamera();
            QrEngine.dispose();
          });
        }
      }
    } catch (e) {
      debugPrint("Error is ${e.toString()}");
    } finally {
      _isDetecting = false;
    }
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
    if (!_showPreview) {
      return const SizedBox.shrink();
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return CameraPreview(_controller!);
  }
}
