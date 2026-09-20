import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/raw_midi_export_sink.dart';

void main() {
  group('midiExportFilename', () {
    test('uses the session id directly', () {
      expect(
        midiExportFilename('session-abc'),
        'midi_capture_session-abc.jsonl',
      );
    });

    test('sanitizes filename-unsafe characters', () {
      expect(
        midiExportFilename('session abc/dé'),
        'midi_capture_session_abc_d_.jsonl',
      );
    });

    test('falls back to unsessioned when no session is present', () {
      expect(midiExportFilename(null), 'midi_capture_unsessioned.jsonl');
      expect(midiExportFilename(''), 'midi_capture_unsessioned.jsonl');
    });

    test('is deterministic for the same session id', () {
      const sessionId = 'sess-1';
      expect(midiExportFilename(sessionId), midiExportFilename(sessionId));
    });
  });

  group('MacosRawMidiExportSink', () {
    test('writes content to the base directory and returns the path',
        () async {
      final dir = Directory.systemTemp.createTempSync('midi_export_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sink = MacosRawMidiExportSink(baseDirectory: dir);

      final path = await sink.write(
        filename: 'midi_capture_session-abc.jsonl',
        content: '{"a":1}\n',
      );

      expect(path, '${dir.path}/midi_capture_session-abc.jsonl');
      expect(File(path).readAsStringSync(), '{"a":1}\n');
    });

    test('creates the base directory when missing', () async {
      final parent = Directory.systemTemp.createTempSync('midi_export_parent');
      addTearDown(() => parent.deleteSync(recursive: true));
      final sink = MacosRawMidiExportSink(
        baseDirectory: Directory('${parent.path}/exports'),
      );

      final path = await sink.write(filename: 'f.jsonl', content: '');

      expect(Directory('${parent.path}/exports').existsSync(), isTrue);
      expect(File(path).readAsStringSync(), '');
    });
  });
}