import 'dart:io';

/// Persists exported JSONL content to disk.
///
/// Kept intentionally small so the diagnostic UI never owns filesystem
/// logic. The [RawMidiJsonlExporter] remains the single source of truth for
/// serialization; this sink is only the destination.
abstract interface class RawMidiExportSink {
  /// Writes [content] to the sink under [filename] and returns the resolved
  /// absolute path, or throws if the write cannot be completed.
  Future<String> write({required String filename, required String content});
}

/// Deterministic export filename for a captured session.
///
/// Produces `midi_capture_<session_id>.jsonl` where the session id is
/// sanitized to filename-safe characters. A missing session uses the static
/// `unsessioned` placeholder.
String midiExportFilename(String? sessionId) {
  final sanitized =
      (sessionId ?? '').replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  final safeName = sanitized.isEmpty ? 'unsessioned' : sanitized;
  return 'midi_capture_$safeName.jsonl';
}

/// Writes exported JSONL into the user's Downloads folder on macOS.
///
/// Uses only `dart:io`, so no filesystem package or platform channel is
/// required. The App Sandbox entitlement
/// `com.apple.security.files.downloads.read-write` is required for the write
/// to succeed at runtime.
final class MacosRawMidiExportSink implements RawMidiExportSink {
  MacosRawMidiExportSink({Directory? baseDirectory})
      : _baseDirectory = baseDirectory ?? _defaultDownloadsDirectory();

  final Directory _baseDirectory;

  static Directory _defaultDownloadsDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return Directory.current;
    }
    return Directory('$home/Downloads');
  }

  @override
  Future<String> write({required String filename, required String content}) async {
    if (!await _baseDirectory.exists()) {
      await _baseDirectory.create(recursive: true);
    }
    final file = File('${_baseDirectory.path}/$filename');
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}