import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const String _defaultWindowsZipUrl =
    'https://github.com/masterjayr/vision_scan/releases/latest/download/windows-x64.zip';

Future<void> main(List<String> args) async {
  try {
    final options = _parseArgs(args);
    final projectRoot = Directory(options.projectRoot ?? Directory.current.path);

    _validateConsumerProject(projectRoot);
    _validateWindowsEnabled(projectRoot);

    final buildDebugDir = Directory(
      p.join(projectRoot.path, 'build', 'windows', 'x64', 'runner', 'Debug'),
    );
    final buildReleaseDir = Directory(
      p.join(projectRoot.path, 'build', 'windows', 'x64', 'runner', 'Release'),
    );
    await buildDebugDir.create(recursive: true);
    await buildReleaseDir.create(recursive: true);

    final cacheDir = Directory(
      p.join(projectRoot.path, '.dart_tool', 'vision_scan', 'windows'),
    );
    await cacheDir.create(recursive: true);

    final zipUrl = options.url ?? _defaultWindowsZipUrl;
    final zipPath = p.join(cacheDir.path, 'windows-x64.zip');

    stdout.writeln('Downloading Windows runtime zip...');
    stdout.writeln('URL: $zipUrl');
    await _downloadZip(zipUrl, zipPath);

    final files = await _extractZipFiles(zipPath);
    final dllFiles =
        files
            .whereType<_ExtractedFile>()
            .where((f) => f.name.toLowerCase().endsWith('.dll'))
            .toList();

    if (dllFiles.isEmpty) {
      _fail(
        'No DLL files found in downloaded zip.\n'
        'Expected at least vision_scan_native.dll in windows-x64.zip.',
      );
    }

    final nativeDll = dllFiles.firstWhere(
      (f) => p.basename(f.name).toLowerCase() == 'vision_scan_native.dll',
      orElse: () => _ExtractedFile('missing', Uint8List(0)),
    );
    if (nativeDll.bytes.isEmpty) {
      _fail(
        'vision_scan_native.dll not found in zip.\n'
        'Please verify the release asset contains vision_scan_native.dll.',
      );
    }

    for (final dll in dllFiles) {
      final name = p.basename(dll.name);
      final debugOut = File(p.join(buildDebugDir.path, name));
      final releaseOut = File(p.join(buildReleaseDir.path, name));
      await debugOut.writeAsBytes(dll.bytes, flush: true);
      await releaseOut.writeAsBytes(dll.bytes, flush: true);
      stdout.writeln('Copied $name -> Debug and Release runner dirs');
    }

    stdout.writeln('\nWindows runtime setup complete.');
    stdout.writeln(
      'You can now run: flutter run -d windows',
    );
  } catch (e) {
    _fail(e.toString());
  }
}

_CliOptions _parseArgs(List<String> args) {
  String? url;
  String? projectRoot;

  for (final arg in args) {
    if (arg.startsWith('--url=')) {
      url = arg.substring('--url='.length).trim();
      continue;
    }
    if (arg.startsWith('--project-root=')) {
      projectRoot = arg.substring('--project-root='.length).trim();
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      stdout.writeln('vision_scan Windows setup');
      stdout.writeln('Usage: dart run vision_scan:setup_windows [options]');
      stdout.writeln('Options:');
      stdout.writeln(
        '  --url=<zip-url>            Override windows-x64.zip download URL',
      );
      stdout.writeln(
        '  --project-root=<path>      Consumer project root (default: current dir)',
      );
      exit(0);
    }
    _fail('Unknown argument: $arg');
  }

  return _CliOptions(url: url, projectRoot: projectRoot);
}

void _validateConsumerProject(Directory projectRoot) {
  if (!projectRoot.existsSync()) {
    _fail('Project root does not exist: ${projectRoot.path}');
  }
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    _fail(
      'pubspec.yaml not found in ${projectRoot.path}\n'
      'Run this command from the Flutter app project root, or pass --project-root=<path>.',
    );
  }
}

void _validateWindowsEnabled(Directory projectRoot) {
  final windowsDir = Directory(p.join(projectRoot.path, 'windows'));
  final runnerCmake = File(
    p.join(projectRoot.path, 'windows', 'runner', 'CMakeLists.txt'),
  );

  if (!windowsDir.existsSync() || !runnerCmake.existsSync()) {
    _fail(
      'This project does not appear to have Windows platform support enabled.\n'
      'Expected windows/runner/CMakeLists.txt in the app project.\n'
      'Enable Windows first with:\n'
      '  flutter config --enable-windows-desktop\n'
      '  flutter create --platforms=windows .',
    );
  }
}

Future<void> _downloadZip(String url, String zipPath) async {
  final uri = Uri.parse(url);
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/zip');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      _fail(
        'Download failed with status ${response.statusCode} for $url\n'
        'Response: $body',
      );
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (prev, element) => prev..addAll(element),
    );
    await File(zipPath).writeAsBytes(bytes, flush: true);
  } finally {
    client.close();
  }
}

Future<List<_ExtractedFile>> _extractZipFiles(String zipPath) async {
  final zipBytes = await File(zipPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);

  final out = <_ExtractedFile>[];
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final content = entry.content;
    out.add(_ExtractedFile(entry.name, List<int>.from(content)));
  }
  return out;
}

Never _fail(String message) {
  stderr.writeln('\n[vision_scan setup_windows] ERROR');
  stderr.writeln(message);
  exit(1);
}

class _CliOptions {
  final String? url;
  final String? projectRoot;

  const _CliOptions({this.url, this.projectRoot});
}

class _ExtractedFile {
  final String name;
  final List<int> bytes;

  const _ExtractedFile(this.name, this.bytes);
}
