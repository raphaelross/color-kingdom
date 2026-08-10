import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:color_kingdom/features/coloring/models/coloring_session.dart';
import 'package:color_kingdom/features/coloring/repositories/local_coloring_session_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('save session then load session', () async {
    final repository = LocalColoringSessionRepository();
    const session = ColoringSession(
      pageId: 'happy-cat',
      regionColors: {'cat-body': 0xFFFF0000},
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 100,
    );

    await repository.saveSession(session);
    final loaded = await repository.getSession('happy-cat');

    expect(loaded, isNotNull);
    expect(loaded!.pageId, 'happy-cat');
    expect(loaded.regionColors['cat-body'], 0xFFFF0000);
  });

  test('missing session returns null', () async {
    final repository = LocalColoringSessionRepository();

    final loaded = await repository.getSession('missing-page');

    expect(loaded, isNull);
  });

  test('delete session removes page session', () async {
    final repository = LocalColoringSessionRepository();
    const session = ColoringSession(
      pageId: 'happy-cat',
      regionColors: {'cat-body': 0xFF00FF00},
      schemaVersion: ColoringSession.currentSchemaVersion,
      lastUpdatedAtEpochMs: 100,
    );

    await repository.saveSession(session);
    await repository.deleteSession('happy-cat');

    final loaded = await repository.getSession('happy-cat');
    expect(loaded, isNull);
  });

  test('clearAllSessions removes all coloring session keys', () async {
    final repository = LocalColoringSessionRepository();

    await repository.saveSession(
      const ColoringSession(
        pageId: 'happy-cat',
        regionColors: {'cat-body': 0xFF00FF00},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 1,
      ),
    );
    await repository.saveSession(
      const ColoringSession(
        pageId: 'playful-puppy',
        regionColors: {'puppy-body': 0xFFFF0000},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 2,
      ),
    );

    await repository.clearAllSessions();

    expect(await repository.getSession('happy-cat'), isNull);
    expect(await repository.getSession('playful-puppy'), isNull);
  });

  test('sessions remain isolated by page id', () async {
    final repository = LocalColoringSessionRepository();

    await repository.saveSession(
      const ColoringSession(
        pageId: 'happy-cat',
        regionColors: {'cat-body': 0xFF123456},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 1,
      ),
    );
    await repository.saveSession(
      const ColoringSession(
        pageId: 'playful-puppy',
        regionColors: {'puppy-body': 0xFFABCDEF},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 2,
      ),
    );

    final cat = await repository.getSession('happy-cat');
    final puppy = await repository.getSession('playful-puppy');

    expect(cat!.regionColors['cat-body'], 0xFF123456);
    expect(cat.regionColors.containsKey('puppy-body'), isFalse);
    expect(puppy!.regionColors['puppy-body'], 0xFFABCDEF);
    expect(puppy.regionColors.containsKey('cat-body'), isFalse);
  });

  test('malformed json does not crash and returns null', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'coloring_session:happy-cat': '{not valid json}',
    });
    final repository = LocalColoringSessionRepository();

    final loaded = await repository.getSession('happy-cat');

    expect(loaded, isNull);
  });

  test('unsupported schema does not crash and returns null', () async {
    final raw = jsonEncode(<String, dynamic>{
      'pageId': 'happy-cat',
      'regionColors': <String, int>{'cat-body': 0xFF000000},
      'schemaVersion': 999,
      'lastUpdatedAtEpochMs': 3,
    });

    SharedPreferences.setMockInitialValues(<String, Object>{
      'coloring_session:happy-cat': raw,
    });

    final repository = LocalColoringSessionRepository();

    final loaded = await repository.getSession('happy-cat');

    expect(loaded, isNull);
  });
}
