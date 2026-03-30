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

  // ── Overlay ───────────────────────────────────────────────────────────────
  // _displayCorners    : what the painter draws (smoothed, widget-space)
  // _stableCheckCorners: widget-space corners used for the stability gate
  List<Offset> _displayCorners = const [];
  List<Offset> _stableCheckCorners = const [];

  // Consecutive missed frames before the overlay box is cleared.
  // Android drops more frames than iOS so we give it more headroom.
  int _missedFrames = 0;
  int get _missedFramesToClear => Platform.isAndroid ? 8 : 5;

  // ── Capture stability ─────────────────────────────────────────────────────
  int _stableCount = 0;
  static const int _stableNeeded = 40;

  int _unstableFrames = 0;
  // Android needs a longer reset gap because detection is less consistent.
  int get _stableResetGap => Platform.isAndroid ? 20 : 15;

  // ── Frame pipeline ────────────────────────────────────────────────────────
  Size _overlaySize = Size.zero;
  Size _previewSize = Size.zero;

  // Single flag — if true we are mid-processing and incoming frames are dropped.
  // This guarantees we always process the freshest frame, never a stale queued one.
  bool _isProcessing = false;

  // Best-frame tracking for capture quality
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
      // iOS gets high resolution — hardware is capable and benefits from it.
      // Android stays at medium — better isolate throughput = smoother overlay.
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

  // Called on every camera frame.
  // If we are still processing the previous frame we drop this one entirely —
  // we never queue frames. This guarantees the box always reflects the current
  // camera view, not a frame from several renders ago.
  void _onFrame(CameraImage image) {
    if (_isProcessing) return; // busy — drop frame, never queue
    _isProcessing = true;
    _processFrame(image); // process THIS frame right now
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      if ((widget.stopOnDetect && _foundFinal) || _isCapturing) return;
      if (!QrEngine.isReady) return;

      final gray = Platform.isAndroid
          ? androidYPlaneToGray(image)
          : bgraToGray(image);

      // Returns null if isolate is still busy — should rarely happen now since
      // we drop frames at _onFrame level instead of queuing them.
      final detection = await QrEngine.detectFromGray(
        gray,
        image.width,
        image.height,
      );

      if (detection == null) return; // isolate busy — skip silently

      // ── No QR found ─────────────────────────────────────────────────────
      if (!detection.detected || !detection.hasCorners) {
        _missedFrames++;
        if (_missedFrames >= _missedFramesToClear) {
          _stableCheckCorners = const [];
          if (mounted) {
            setState(() => _displayCorners = const []);
          }
        }
        _onUnstable();
        return;
      }

      // ── QR detected ─────────────────────────────────────────────────────
      _missedFrames = 0;

      if (detection.decoded && detection.text != null) {
        widget.onDetect.call(detection.text!);
      }

      final widgetSize = _overlaySize;
      final previewSize = _previewSize;
      if (widgetSize == Size.zero || previewSize == Size.zero) return;

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final sensorOrientation = _controller!.description.sensorOrientation;
      final correctedPreviewSize = Platform.isIOS
          ? Size(previewSize.height, previewSize.width)
          : previewSize;

      // Map raw ZXing corners → widget space.
      // isIOS skips the rotation transform since iOS frames are already
      // in display orientation unlike Android which comes in sensor orientation.

      final newWidgetCorners = detection.corners.map((p) {
        return mapImageToWidget(
          imagePoint: p,
          imageSize: imageSize,
          widgetSize: widgetSize,
          sensorOrientation: sensorOrientation,
          previewSize: correctedPreviewSize, // use corrected size
          isIOS: Platform.isIOS,
        );
      }).toList();

      // ── Overlay smoothing ────────────────────────────────────────────────
      //
      // iOS  (alpha 0.75): gentle glide — hardware is fast and consistent.
      // Android (alpha 0.92): near-instant snap — avoids blending toward a
      //   stale position when detection gaps occur.
      final smoothed = smoothCorners(
        _displayCorners,
        newWidgetCorners,
        alpha: Platform.isIOS ? 0.75 : 0.92,
      );

      if (mounted) {
        setState(() => _displayCorners = smoothed);
      }

      // ── Stability gate (capture only) ────────────────────────────────────
      // cornersLookValid receives widget-space corners (newWidgetCorners) —
      // NOT image-space corners (detection.corners). This is critical so the
      // area threshold of 1500 is resolution-independent across both platforms.
      if (!cornersLookValid(newWidgetCorners)) {
        _onUnstable();
      } else if (_stableCheckCorners.isNotEmpty &&
          isStableCorners(_stableCheckCorners, newWidgetCorners)) {
        _stableCount++;
        _unstableFrames = 0;

        // Track the frame where corners moved the least — that is the
        // sharpest, most locked-on frame and gives the best capture image.
        final delta = averageCornerDelta(_stableCheckCorners, newWidgetCorners);
        if (delta < _bestDelta) {
          _bestDelta = delta;
          _bestGray = gray;
          _bestW = image.width;
          _bestH = image.height;
        }
      } else {
        _onUnstable();
      }

      // Always update with latest widget-space corners for next frame comparison.
      _stableCheckCorners = newWidgetCorners;

      if (_stableCount >= _stableNeeded && _bestGray != null) {
        await _captureFinal(_bestGray!, _bestW, _bestH);
        _bestDelta = double.infinity;
        _bestGray = null;
        _bestW = 0;
        _bestH = 0;
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      // Always release the processing lock so the next frame can be picked up.
      _isProcessing = false;
    }
  }

  void _onUnstable() {
    if (_stableCount > 0) _stableCount--;
    _unstableFrames++;
    if (_unstableFrames > _stableResetGap) {
      _stableCheckCorners = const [];
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
