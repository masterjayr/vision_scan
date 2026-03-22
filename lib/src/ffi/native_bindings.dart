import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';

base class QRResult extends ffi.Struct {
  external ffi.Pointer<ffi.Char> text;

  @ffi.Int32()
  external int success;
}

base class VSFrameResult extends ffi.Struct {
  @ffi.Int32()
  external int detected;

  @ffi.Int32()
  external int decoded;

  @ffi.Array.multi([8])
  external ffi.Array<ffi.Float> corners;

  external ffi.Pointer<ffi.Char> text;
}

base class VSScanResult extends ffi.Struct {
  @ffi.Int32()
  external int success;

  external ffi.Pointer<ffi.Char> text;
}

/// Native / Dart signatures for [scan_qr_windows] (struct return avoids `>` parse issues in generics).
typedef ScanQrWindowsNative = VSScanResult Function();

typedef ScanQrWindowsDart = VSScanResult Function();

base class VSFinalResult extends ffi.Struct {
  @ffi.Int32()
  external int success;

  @ffi.Int32()
  external int decoded;

  @ffi.Array.multi([8])
  external ffi.Array<ffi.Float> corners;

  external ffi.Pointer<ffi.Char> text;

  external ffi.Pointer<ffi.Uint8> cropped_jpeg;

  @ffi.Int32()
  external int cropped_len;

  external ffi.Pointer<ffi.Uint8> frame_jpeg;

  @ffi.Int32()
  external int frame_len;
}

class NativeBindings {
  NativeBindings._();

  static final ffi.DynamicLibrary _lib = _open();

  static final QRResult Function(ffi.Pointer<ffi.Uint8>, int, int)
  decodeQRFromGray = _lib
      .lookupFunction<
        QRResult Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32),
        QRResult Function(ffi.Pointer<ffi.Uint8>, int, int)
      >('decode_qr_from_gray');

  // VSFrameResult detect_qr_from_gray(const uint8_t* gray, int32_t w, int32_t h)
  static final VSFrameResult Function(ffi.Pointer<ffi.Uint8>, int, int)
  _detect = _lib
      .lookupFunction<
        VSFrameResult Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32),
        VSFrameResult Function(ffi.Pointer<ffi.Uint8>, int, int)
      >("detect_qr_from_gray");

  // VSFinalResult capture_qr_from_gray(...)
  static final VSFinalResult Function(ffi.Pointer<ffi.Uint8>, int, int)
  _capture = _lib
      .lookupFunction<
        VSFinalResult Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32),
        VSFinalResult Function(ffi.Pointer<ffi.Uint8>, int, int)
      >("capture_qr_from_gray");

  static final VSScanResult Function(ffi.Pointer<ffi.Uint8>, int, int)
  _scanFromGray = _lib
      .lookupFunction<
        VSScanResult Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32),
        VSScanResult Function(ffi.Pointer<ffi.Uint8>, int, int)
      >('scan_qr_from_gray');

  static final void Function(ffi.Pointer<ffi.Char>) _freeString = _lib
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Char>),
        void Function(ffi.Pointer<ffi.Char>)
      >('free_qr_string');

  static final void Function(ffi.Pointer<ffi.Uint8>) _freeBytes = _lib
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Uint8>),
        void Function(ffi.Pointer<ffi.Uint8>)
      >("free_qr_bytes");

  static final ping = _lib.lookupFunction<ffi.Int32 Function(), int Function()>(
    "vision_scan_ping",
  );

  static final _opencvTest =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>(
    "vision_scan_opencv_test",
  );

  static final _zxingTest =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>(
    "vision_scan_zxing_test",
  );

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libvision_scan_native.so');
    }

    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }

    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open("vision_scan_native.dll");
    }

    throw UnsupportedError(
      'vision_scan FFI supports Android, iOS, and Windows.',
    );
  }

  /// Simple decode-only API; frees native text via [free_qr_string].
  static String? scanFromGray(Uint8List grayBytes, int width, int height) {
    final ptr = malloc<ffi.Uint8>(grayBytes.length);
    ptr.asTypedList(grayBytes.length).setAll(0, grayBytes);

    final res = _scanFromGray(ptr, width, height);

    String? text;
    if (res.success == 1 && res.text != ffi.nullptr) {
      text = res.text.cast<Utf8>().toDartString();
      _freeString(res.text);
    } else if (res.text != ffi.nullptr) {
      _freeString(res.text);
    }

    malloc.free(ptr);
    return text;
  }

  static String? decodeQR(Uint8List grayBytes, int width, int height) {
    final ptr = malloc<ffi.Uint8>(grayBytes.length);
    ptr.asTypedList(grayBytes.length).setAll(0, grayBytes);

    final result = decodeQRFromGray(ptr, width, height);

    String? text;
    if (result.success == 1 && result.text != ffi.nullptr) {
      text = result.text.cast<Utf8>().toDartString();
      _freeString(result.text);
    }

    malloc.free(ptr);
    return text;
  }

  static int pingWindows() {
    return ping();
  }

  static int opencvTestWindows() {
    return _opencvTest();
  }

  static int zxingTestWindows() {
    return _zxingTest();
  }

  static List<Offset> _cornersToOffsets(ffi.Array<ffi.Float> c) {
    return List.generate(4, (i) => Offset(c[i * 2], c[i * 2 + 1]));
  }

  static String? _readAndFreeText(ffi.Pointer<ffi.Char> p) {
    if (p == ffi.nullptr) return null;
    final s = p.cast<Utf8>().toDartString();
    _freeString(p);
    return s;
  }

  static Uint8List _copyAndFreeBytes(ffi.Pointer<ffi.Uint8> p, int len) {
    if (p == ffi.nullptr || len <= 0) return Uint8List(0);
    final bytes = Uint8List.fromList(p.asTypedList(len));
    _freeBytes(p);
    return bytes;
  }

  static FrameDetection detectFromGray(Uint8List gray, int width, int height) {
    final ptr = malloc<ffi.Uint8>(gray.length);
    ptr.asTypedList(gray.length).setAll(0, gray);

    final res = _detect(ptr, width, height);

    final corners = _cornersToOffsets(res.corners);
    final text = _readAndFreeText(res.text);

    malloc.free(ptr);

    return FrameDetection(
      detected: res.detected == 1,
      decoded: res.decoded == 1,
      corners: corners,
      text: text,
    );
  }

  static FinalCapture captureFromGray(Uint8List gray, int width, int height) {
    final ptr = malloc<ffi.Uint8>(gray.length);
    ptr.asTypedList(gray.length).setAll(0, gray);
    final res = _capture(ptr, width, height);

    final corners = _cornersToOffsets(res.corners);
    final text = _readAndFreeText(res.text);
    final cropped = _copyAndFreeBytes(res.cropped_jpeg, res.cropped_len);
    final frame = _copyAndFreeBytes(res.frame_jpeg, res.frame_len);

    malloc.free(ptr);

    return FinalCapture(
      success: res.success == 1,
      decoded: res.decoded == 1,
      text: text,
      corners: corners,
      croppedJpeg: cropped,
      frameJpeg: frame,
    );
  }

  /// Windows-only: OpenCV camera, first successful ZXing decode (or cancel with Esc).
  static String? scanWindows() {
    if (!Platform.isWindows) return null;
    final fn = _lib.lookupFunction<ScanQrWindowsNative, ScanQrWindowsDart>(
      'scan_qr_windows',
    );
    final res = fn();
    String? text;
    if (res.success == 1 && res.text != ffi.nullptr) {
      text = res.text.cast<Utf8>().toDartString();
      _freeString(res.text);
    } else if (res.text != ffi.nullptr) {
      _freeString(res.text);
    }
    return text;
  }

  /// Windows-only: opens native camera window, detects QR, stabilizes, returns same type as captureFromGray.
  static FinalCapture? captureFromCameraWindows() {
    if (!Platform.isWindows) return null;
    final fn = _lib.lookupFunction<VSFinalResult Function(), VSFinalResult Function()>(
      'capture_qr_from_camera_windows',
    );
    final res = fn();
    if (res.success != 1) {
      if (res.text != ffi.nullptr) _freeString(res.text);
      if (res.frame_len > 0 && res.frame_jpeg != ffi.nullptr) _freeBytes(res.frame_jpeg);
      if (res.cropped_len > 0 && res.cropped_jpeg != ffi.nullptr) _freeBytes(res.cropped_jpeg);
      return null;
    }
    final corners = _cornersToOffsets(res.corners);
    final text = _readAndFreeText(res.text);
    final cropped = _copyAndFreeBytes(res.cropped_jpeg, res.cropped_len);
    final frame = _copyAndFreeBytes(res.frame_jpeg, res.frame_len);
    return FinalCapture(
      success: true,
      decoded: res.decoded == 1,
      text: text,
      corners: corners,
      croppedJpeg: cropped,
      frameJpeg: frame,
    );
  }
}

class FrameDetection {
  final bool detected;
  final bool decoded;
  final String? text;
  final List<Offset> corners;
  FrameDetection({
    required this.detected,
    required this.decoded,
    required this.corners,
    required this.text,
  });
}

class FinalCapture {
  final bool success;
  final bool decoded;
  final String? text;
  final List<Offset> corners;
  final Uint8List croppedJpeg;
  final Uint8List frameJpeg;
  FinalCapture({
    required this.success,
    required this.decoded,
    required this.corners,
    required this.text,
    required this.croppedJpeg,
    required this.frameJpeg,
  });
}
