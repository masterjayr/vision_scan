import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

base class QRResult extends ffi.Struct {
  external ffi.Pointer<ffi.Char> text;

  @ffi.Int32()
  external int success;
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

  static final void Function(ffi.Pointer<ffi.Char>) freeQrString = _lib
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Char>),
        void Function(ffi.Pointer<ffi.Char>)
      >('free_qr_string');

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libvision_scan_native.so');
    }

    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }

    throw UnsupportedError("This demo only supports Android/iOS for now.");
  }

  static String? decodeQR(Uint8List grayBytes, int width, int height) {
    final ptr = malloc<ffi.Uint8>(grayBytes.length);
    ptr.asTypedList(grayBytes.length).setAll(0, grayBytes);

    final result = decodeQRFromGray(ptr, width, height);

    String? text;
    if (result.success == 1 && result.text != ffi.nullptr) {
      text = result.text.cast<Utf8>().toDartString();
      freeQrString(result.text);
    }

    malloc.free(ptr);
    return text;
  }
}
