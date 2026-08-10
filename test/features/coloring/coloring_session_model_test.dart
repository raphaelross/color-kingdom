import 'package:flutter_test/flutter_test.dart';

import 'package:color_kingdom/features/coloring/models/coloring_session.dart';

void main() {
  test('serialization round-trip preserves all fields', () {
    const session = ColoringSession(
      pageId: 'happy-cat',
      regionColors: {
        'cat-body': 0xFFFF0000,
        'cat-tail': 0x8000FF00,
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 1700000000000,
    );

    final json = session.toJson();
    final restored = ColoringSession.fromJson(json);

    expect(restored.pageId, 'happy-cat');
    expect(restored.regionColors['cat-body'], 0xFFFF0000);
    expect(restored.regionColors['cat-tail'], 0x8000FF00);
    expect(restored.schemaVersion, ColoringSession.currentSchemaVersion);
    expect(restored.lastUpdatedAtEpochMs, 1700000000000);
  });

  test('json string round-trip preserves ARGB values', () {
    const session = ColoringSession(
      pageId: 'playful-puppy',
      regionColors: {
        'puppy-body': 0xFF112233,
        'puppy-tail': 0xFFFFFFFF,
      },
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 42,
    );

    final raw = session.toJsonString();
    final restored = ColoringSession.fromJsonString(raw);

    expect(restored.pageId, 'playful-puppy');
    expect(restored.regionColors, session.regionColors);
    expect(restored.schemaVersion, session.schemaVersion);
    expect(restored.lastUpdatedAtEpochMs, session.lastUpdatedAtEpochMs);
  });

  test('malformed payload is rejected safely', () {
    expect(
      () => ColoringSession.fromJson(<String, dynamic>{
        'pageId': 'happy-cat',
        'regionColors': 'not-a-map',
        'schemaVersion': ColoringSession.currentSchemaVersion,
        'lastUpdatedAtEpochMs': 1,
      }),
      throwsFormatException,
    );
  });

  test('unsupported schema is rejected safely', () {
    expect(
      () => ColoringSession.fromJson(<String, dynamic>{
        'pageId': 'happy-cat',
        'regionColors': <String, int>{'cat-body': 0xFF000000},
        'schemaVersion': 999,
        'lastUpdatedAtEpochMs': 1,
      }),
      throwsUnsupportedError,
    );
  });
}
