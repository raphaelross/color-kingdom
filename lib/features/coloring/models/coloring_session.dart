import 'dart:convert';

class ColoringSession {
  const ColoringSession({
    required this.pageId,
    required this.regionColors,
    required this.schemaVersion,
    required this.lastUpdatedAtEpochMs,
  });

  static const int currentSchemaVersion = 1;

  final String pageId;
  final Map<String, int> regionColors;
  final int schemaVersion;
  final int lastUpdatedAtEpochMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pageId': pageId,
      'regionColors': regionColors,
      'schemaVersion': schemaVersion,
      'lastUpdatedAtEpochMs': lastUpdatedAtEpochMs,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static ColoringSession fromJson(Map<String, dynamic> json) {
    final pageId = json['pageId'];
    final regionColors = json['regionColors'];
    final schemaVersion = json['schemaVersion'];
    final lastUpdatedAtEpochMs = json['lastUpdatedAtEpochMs'];

    if (pageId is! String || pageId.trim().isEmpty) {
      throw const FormatException('Invalid ColoringSession.pageId');
    }

    if (schemaVersion is! int) {
      throw const FormatException('Invalid ColoringSession.schemaVersion');
    }

    if (schemaVersion != currentSchemaVersion) {
      throw UnsupportedError('Unsupported ColoringSession schemaVersion: $schemaVersion');
    }

    if (lastUpdatedAtEpochMs is! int) {
      throw const FormatException('Invalid ColoringSession.lastUpdatedAtEpochMs');
    }

    if (regionColors is! Map) {
      throw const FormatException('Invalid ColoringSession.regionColors');
    }

    final parsedRegionColors = <String, int>{};
    for (final entry in regionColors.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty) {
        throw const FormatException('Invalid ColoringSession.regionColors key');
      }
      if (value is! int) {
        throw const FormatException('Invalid ColoringSession.regionColors value');
      }
      parsedRegionColors[key] = value;
    }

    return ColoringSession(
      pageId: pageId,
      regionColors: parsedRegionColors,
      schemaVersion: schemaVersion,
      lastUpdatedAtEpochMs: lastUpdatedAtEpochMs,
    );
  }

  static ColoringSession fromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ColoringSession JSON must be an object.');
    }
    return fromJson(decoded);
  }
}
