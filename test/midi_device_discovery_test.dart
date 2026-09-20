import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_device_discovery.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('piano_midi/macos');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps a valid source from the platform response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'listMidiSources');
      return <dynamic>[
        <String, dynamic>{
          'id': 123456,
          'name': 'Example MIDI Keyboard',
          'manufacturer': 'Example Manufacturer',
        },
      ];
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    final sources = await discovery.listSources();

    expect(sources, hasLength(1));
    final source = sources.single;
    expect(source.id, '123456');
    expect(source.name, 'Example MIDI Keyboard');
    expect(source.manufacturer, 'Example Manufacturer');
  });

  test('maps multiple sources in platform order', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[
        <String, dynamic>{
          'id': 1,
          'name': 'Keyboard A',
          'manufacturer': 'Maker A',
        },
        <String, dynamic>{
          'id': 2,
          'name': 'Keyboard B',
          'manufacturer': 'Maker B',
        },
      ];
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    final sources = await discovery.listSources();

    expect(sources.map((s) => s.name), ['Keyboard A', 'Keyboard B']);
    expect(sources.map((s) => s.id), ['1', '2']);
  });

  test('returns an empty list when no MIDI sources exist', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[];
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    final sources = await discovery.listSources();

    expect(sources, isEmpty);
  });

  test('falls back to "Unknown" for a missing manufacturer', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[
        <String, dynamic>{
          'id': 7,
          'name': 'Nameless Maker Device',
        },
      ];
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    final sources = await discovery.listSources();

    expect(sources.single.manufacturer, MidiSourceInfo.unknownManufacturer);
    expect(sources.single.manufacturer, 'Unknown');
  });

  test('falls back to "Unknown" for an empty manufacturer string', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[
        <String, dynamic>{
          'id': 7,
          'name': 'Nameless Maker Device',
          'manufacturer': '',
        },
      ];
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    final sources = await discovery.listSources();

    expect(sources.single.manufacturer, 'Unknown');
  });

  test('accepts a string id and preserves an empty name', () async {
    final info = MidiSourceInfo.fromPlatformMap(<String, dynamic>{
      'id': 'abc-123',
      'name': '',
      'manufacturer': 'Maker',
    });

    expect(info.id, 'abc-123');
    expect(info.name, '');
    expect(info.manufacturer, 'Maker');
  });

  test('throws FormatException on a malformed response (not a list)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, dynamic>{'unexpected': true};
    });

    final discovery = MacosMidiDeviceDiscovery(channel: channel);
    expect(discovery.listSources(), throwsFormatException);
  });

  test('throws FormatException on a source missing its id', () {
    expect(
      () => MidiSourceInfo.fromPlatformMap(<String, dynamic>{
        'name': 'No Id Device',
        'manufacturer': 'Maker',
      }),
      throwsFormatException,
    );
  });

  test('falls back to an empty name for a non-string name', () {
    expect(
      () => MidiSourceInfo.fromPlatformMap(<String, dynamic>{
        'id': 5,
        'name': 42,
        'manufacturer': 'Maker',
      }),
      isNot(throwsFormatException),
    );
    final info = MidiSourceInfo.fromPlatformMap(<String, dynamic>{
      'id': 5,
      'name': 42,
      'manufacturer': 'Maker',
    });
    expect(info.name, '');
    expect(info.manufacturer, 'Maker');
  });
}