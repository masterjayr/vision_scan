import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:vision_scan/src/camera/qr_overlay_painter.dart';
import 'package:vision_scan/src/engine/qr_engine.dart';
import 'package:vision_scan/src/models/final_capture_paths_result.dart';
import 'package:vision_scan/src/models/final_capture_result.dart';
import 'package:vision_scan/utils/file_utils.dart';
import 'package:vision_scan/utils/image_pro_utils.dart';
import 'package:flutter/material.dart';
import 'package:vision_scan/utils/scan_utils.dart';

typedef QRDetectCallback = void Function(String result);
typedef QRCaptureCallback = void Function(FinalCaptureResult result);
typedef QRCapturePathsCallback = void Function(FinalCapturePathsResult result);

class QrScannerView extends StatefulWidget {
  final QRDetectCallback onDetect;
  final QRCaptureCallback? onFinalCapture;
  final QRCapturePathsCallback? onFinalCapturePaths;
  final bool stopOnDetect;

  const QrScannerView({
    Key? key,
    required this.onDetect,
    this.onFinalCapture,
    this.onFinalCapturePaths,
    this.stopOnDetect = false,
  }) : super(key: key);

  @override
  State<QrScannerView> createState() => _QRScannerViewState();
}

class _QRScannerViewState extends State<QrScannerView> {
  CameraController? _controller;
  bool _isCapturing = false;
  bool _foundFinal = false;

  // ── Overlay ──────────────────────────────────────────────────────────────
  // _displayCorners: what the painter actually draws (smoothed, widget-space).
  // _rawImageCorners: last corners in image-space, used for stability check.
  List<Offset> _displayCorners = const [];
  List<Offset> _stableCheckCorners = const [];

  // How many frames in a row we got no detection — used only to clear the box.
  int _missedFrames = 0;

  // Clear the box after this many consecutive missed frames.
  // Keep this low so the box disappears quickly when the QR leaves frame,
  // but not so low that a single bad frame flickers it off.
  static const int _missedFramesToClear = 5;

  // ── Capture stability ────────────────────────────────────────────────────
  int _stableCount = 0;
  static const int _stableNeeded = 40;

  int _unstableFrames = 0;
  static const int _stableResetGap = 15;

  // ── Frame pipeline ───────────────────────────────────────────────────────
  Size _overlaySize = Size.zero;
  Size _previewSize = Size.zero;

  CameraImage? _latestImage;
  bool _isProcessing = false;

  double _bestDelta = double.infinity;
  Uint8List? _bestGray;
  int _bestW = 0;
  int _bestH = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await QrEngine.init();
    await _initCamera();
  }

  Future<void> _initCamera() async {
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

  // Called on every camera frame — just stores the latest and kicks the loop.
  void _onFrame(CameraImage image) {
    _latestImage = image;
    if (!_isProcessing) {
      _isProcessing = true;
      _processLatest();
    }
  }

  Future<void> _processLatest() async {
    while (_latestImage != null) {
      final image = _latestImage!;
      _latestImage = null;

      if ((widget.stopOnDetect && _foundFinal) || _isCapturing) continue;
      if (!QrEngine.isReady) continue;

      try {
        final gray = Platform.isAndroid
            ? androidYPlaneToGray(image)
            : bgraToGray(image);

        // detectFromGray now drops the frame (returns null) if the isolate is
        // busy — no throttle, no backlog, minimal latency.
        final detection = await QrEngine.detectFromGray(
          gray,
          image.width,
          image.height,
        );

        if (detection == null) continue; // isolate busy, skip frame

        // ── No QR found ───────────────────────────────────────────────────
        if (!detection.detected || !detection.hasCorners) {
          _missedFrames++;
          if (_missedFrames >= _missedFramesToClear) {
            _stableCheckCorners = const [];
            if (mounted) {
              setState(() => _displayCorners = const []);
            }
          }

          // Degrade stability while QR is missing
          _onUnstable();
          continue;
        }

        // ── QR detected ───────────────────────────────────────────────────
        _missedFrames = 0;

        if (detection.decoded && detection.text != null) {
          widget.onDetect.call(detection.text!);
        }

        final widgetSize = _overlaySize;
        final previewSize = _previewSize;
        if (widgetSize == Size.zero || previewSize == Size.zero) continue;

        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        final sensorOrientation = _controller!.description.sensorOrientation;

        // Map raw corners → widget space for this frame
        final newWidgetCorners = detection.corners.map((p) {
          return mapImageToWidget(
            imagePoint: p,
            imageSize: imageSize,
            widgetSize: widgetSize,
            sensorOrientation: sensorOrientation,
            previewSize: previewSize,
            isIOS: Platform.isIOS,
          );
        }).toList();

        // ── Smooth the overlay corners ────────────────────────────────────
        // smoothCorners blends previous display position with the new one so
        // the box glides onto the QR code instead of teleporting.
        // alpha=0.75 → responsive but not jittery; raise toward 1.0 for
        // more snap, lower toward 0.5 for more smoothing.
        final smoothed = smoothCorners(
          _displayCorners,
          newWidgetCorners,
          alpha: 0.75,
        );

        if (mounted) {
          setState(() => _displayCorners = smoothed);
        }

        // ── Stability check (capture gate only) ───────────────────────────
        if (!cornersLookValid(detection.corners)) {
          _onUnstable();
        } else if (_stableCheckCorners.isNotEmpty &&
            isStableCorners(_stableCheckCorners, newWidgetCorners)) {
          _stableCount++;
          _unstableFrames = 0;
          // Track the sharpest/most-locked frame
          final delta = averageCornerDelta(
            _stableCheckCorners,
            newWidgetCorners,
          );
          if (delta < _bestDelta) {
            _bestDelta = delta;
            _bestGray = gray;
            _bestW = image.width;
            _bestH = image.height;
          }
        } else {
          _onUnstable();
        }

        _stableCheckCorners = newWidgetCorners;

        if (_stableCount >= _stableNeeded && _bestGray != null) {
          await _captureFinal(gray, image.width, image.height);
          _bestDelta = double.infinity;
          _bestGray = null;
        }
      } catch (e) {
        debugPrint('Scan error: $e');
      }
    }

    _isProcessing = false;
  }

  void _onUnstable() {
    if (_stableCount > 0) _stableCount--;
    _unstableFrames++;
    if (_unstableFrames > _stableResetGap) {
      _stableCheckCorners = const []; // was _rawImageCorners
    }
  }

  Future<void> _captureFinal(Uint8List gray, int w, int h) async {
    _isCapturing = true;
    try {
      final finalResult = await QrEngine.captureFromGray(gray, w, h);
      if (finalResult == null || !finalResult.success) {
        _stableCount = 0;
        return;
      }

      final croppedPath = await FileUtils.saveTempBytes(
        bytes: Uint8List.fromList(finalResult.croppedJpeg),
        prefix: 'qr_crop',
        ext: 'jpg',
      );
      final framePath = await FileUtils.saveTempBytes(
        bytes: Uint8List.fromList(finalResult.frameJpeg),
        prefix: 'qr_frame',
        ext: 'jpg',
      );

      if (widget.stopOnDetect) _foundFinal = true;

      if (finalResult.decoded && finalResult.text != null) {
        widget.onDetect.call(finalResult.text!);
      }

      widget.onFinalCapture?.call(finalResult);
      widget.onFinalCapturePaths?.call(
        FinalCapturePathsResult(
          success: finalResult.success,
          decoded: finalResult.decoded,
          text: finalResult.text,
          corners: finalResult.corners,
          croppedImagePath: croppedPath,
          frameImagePath: framePath,
        ),
      );

      if (!widget.stopOnDetect && mounted) {
        setState(() => _stableCount = 0);
      }

      if (widget.stopOnDetect) {
        await _stopCamera();
        QrEngine.dispose();
      }
    } finally {
      _isCapturing = false;
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
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _overlaySize = size;

        final preview = c.value.previewSize!;
        _previewSize = Size(preview.width, preview.height);

        final previewAspect = preview.width / preview.height;
        final widgetAspect = size.width / size.height;
        final scale = widgetAspect * previewAspect;

        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(
              scale: scale < 1 ? 1 / scale : scale,
              child: Center(child: CameraPreview(c)),
            ),
            CustomPaint(
              painter: QrOverlayPainter(
                points: _displayCorners,
                show: _displayCorners.length == 4,
              ),
            ),
          ],
        );
      },
    );
  }
}
