import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:vision_scan/src/ffi/native_bindings.dart';

enum _Op { detect, capture, decode }

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
      final msg = message as _WorkMessage;

      // heavy work done in isolate

      if (msg.op == _Op.decode) {
        final result = NativeBindings.decodeQR(msg.gray, msg.width, msg.height);

        msg.reply.send(result);
      } else if (msg.op == _Op.detect) {
        final result = NativeBindings.detectFromGray(
          msg.gray,
          msg.width,
          msg.height,
        );
        msg.reply.send(
          DetectReply(
            detected: result.detected,
            decoded: result.decoded,
            text: result.text,
            corners: result.corners,
          ),
        );
      } else {
        final result = NativeBindings.captureFromGray(
          msg.gray,
          msg.width,
          msg.height,
        );
        msg.reply.send(
          CaptureReply(
            success: result.success,
            decoded: result.decoded,
            text: result.text,
            corners: result.corners,
            croppedJpeg: result.croppedJpeg,
            frameJpeg: result.frameJpeg,
          ),
        );
      }
    });
  }

  Future<String?> decode(Uint8List gray, int width, int height) async {
    final response = ReceivePort();

    _sendPort.send(
      _WorkMessage(_Op.decode, gray, width, height, response.sendPort),
    );

    return await response.first as String?;
  }

  Future<DetectReply?> detect(Uint8List gray, int width, int height) async {
    final response = ReceivePort();

    _sendPort.send(
      _WorkMessage(_Op.detect, gray, width, height, response.sendPort),
    );

    return await response.first as DetectReply;
  }

  Future<CaptureReply?> capture(Uint8List gray, int width, int height) async {
    final response = ReceivePort();
    _sendPort.send(
      _WorkMessage(_Op.capture, gray, width, height, response.sendPort),
    );

    return await response.first as CaptureReply;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkMessage {
  final _Op op;
  final Uint8List gray;
  final int width;
  final int height;
  final SendPort reply;

  _WorkMessage(this.op, this.gray, this.width, this.height, this.reply);
}

class DetectReply {
  final bool detected;
  final bool decoded;
  final String? text;
  final List<Offset> corners;
  DetectReply({
    required this.detected,
    required this.decoded,
    required this.text,
    required this.corners,
  });
}

class CaptureReply {
  final bool success;
  final bool decoded;
  final String? text;
  final List<Offset> corners;
  final Uint8List croppedJpeg;
  final Uint8List frameJpeg;
  CaptureReply({
    required this.success,
    required this.decoded,
    required this.text,
    required this.corners,
    required this.croppedJpeg,
    required this.frameJpeg,
  });
}
