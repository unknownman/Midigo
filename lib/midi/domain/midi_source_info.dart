final class MidiSourceInfo {
  final String id;
  final String name;
  final String manufacturer;

  const MidiSourceInfo({
    required this.id,
    required this.name,
    required this.manufacturer,
  });

  static const unknownManufacturer = 'Unknown';
  static const unnamed = '(unnamed)';

  factory MidiSourceInfo.fromPlatformMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
          'Malformed platform response: expected a map for a MIDI source.');
    }
    final map = Map<Object?, Object?>.from(raw);

    final id = switch (map['id']) {
      final String value => value,
      final int value => value.toString(),
      _ => throw const FormatException(
          'Malformed platform response: missing or invalid MIDI source id.'),
    };

    final name = _optionalString(map['name']) ?? '';

    final manufacturer =
        _optionalString(map['manufacturer']) ?? unknownManufacturer;

    return MidiSourceInfo(
      id: id,
      name: name,
      manufacturer: manufacturer,
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
  }
}