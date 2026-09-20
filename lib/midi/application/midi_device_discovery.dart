import 'package:flutter/services.dart';

import '../domain/midi_source_info.dart';

abstract interface class MidiDeviceDiscovery {
  Future<List<MidiSourceInfo>> listSources();
}

final class MacosMidiDeviceDiscovery implements MidiDeviceDiscovery {
  MacosMidiDeviceDiscovery({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('piano_midi/macos');

  static const _listMidiSourcesMethod = 'listMidiSources';

  final MethodChannel _channel;

  @override
  Future<List<MidiSourceInfo>> listSources() async {
    final dynamic rawResponse =
        await _channel.invokeMethod<Object?>(_listMidiSourcesMethod);
    if (rawResponse == null) {
      return const [];
    }
    if (rawResponse is! List) {
      throw const FormatException(
          'Malformed platform response: expected an array of MIDI sources.');
    }
    return rawResponse
        .map(MidiSourceInfo.fromPlatformMap)
        .toList(growable: false);
  }
}