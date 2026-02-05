import 'dart:isolate';
import 'dart:typed_data';

import 'package:vision_scan/src/ffi/native_bindings.dart';

class QrIsolate {
  late final Isolate _isolate;

  late final SendPort _sendPort;

  final ReceivePort _receivePort = ReceivePort();

  static Future<QrIsolate> spawn() async {
    final isolate = QrIsolate();
    isolate._isolate = await Isolate.spawn(
      _entry,
      isolate._receivePort.sendPort,
    );
    isolate._sendPort = await isolate._receivePort.first as SendPort;
    return isolate;
  }

  static void _entry(SendPort mainPort) {
    final port = ReceivePort();
    mainPort.send(port.sendPort);

    port.listen((message) {
      final data = message as _DecodeMessage;

      final result = NativeBindings.decodeQR(
        data.gray,
        data.width,
        data.height,
      );

      data.reply.send(result);
    });
  }

  Future<String?> decode(Uint8List gray, int width, int height) async {
    final response = ReceivePort();

    _sendPort.send(_DecodeMessage(gray, width, height, response.sendPort));

    return await response.first as String?;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _DecodeMessage {
  final Uint8List gray;
  final int width;
  final int height;
  final SendPort reply;

  _DecodeMessage(this.gray, this.width, this.height, this.reply);
}
