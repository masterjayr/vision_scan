import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileUtils {
  FileUtils._();

  static Future<String> saveTempBytes({
    required Uint8List bytes,
    required String prefix,
    String ext = "jpg",
  }) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, "${prefix}_$ts.$ext");
    final f = File(filePath);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
}
