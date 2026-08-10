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

  test('getAllSessions returns empty list when no sessions exist', () async {
    final repository = LocalColoringSessionRepository();

    final sessions = await repository.getAllSessions();

    expect(sessions, isEmpty);
  });

  test('getAllSessions returns multiple sessions newest first', () async {
    final repository = LocalColoringSessionRepository();

    await repository.saveSession(
      const ColoringSession(
        pageId: 'happy-cat',
        regionColors: {'cat-body': 0xFF000001},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 10,
      ),
    );
    await repository.saveSession(
      const ColoringSession(
        pageId: 'playful-puppy',
        regionColors: {'puppy-body': 0xFF000002},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 30,
      ),
    );
    await repository.saveSession(
      const ColoringSession(
        pageId: 'friendly-lion',
        regionColors: {'lion-body': 0xFF000003},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 20,
      ),
    );

    final sessions = await repository.getAllSessions();

    expect(
      sessions.map((session) => session.pageId).toList(),
      ['playful-puppy', 'friendly-lion', 'happy-cat'],
    );
  });

  test('getAllSessions orders same timestamp by pageId ascending', () async {
    final repository = LocalColoringSessionRepository();

    await repository.saveSession(
      const ColoringSession(
        pageId: 'zebra-page',
        regionColors: {'zebra-body': 0xFF000004},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 50,
      ),
    );
    await repository.saveSession(
      const ColoringSession(
        pageId: 'apple-page',
        regionColors: {'apple-body': 0xFF000005},
        schemaVersion: ColoringSession.currentSchemaVersion,
        lastUpdatedAtEpochMs: 50,
      ),
    );

    final sessions = await repository.getAllSessions();

    expect(
      sessions.map((session) => session.pageId).toList(),
      ['apple-page', 'zebra-page'],
    );
  });

  test('getAllSessions excludes malformed and unsupported entries', () async {
    final validRaw = jsonEncode(<String, dynamic>{
      'pageId': 'happy-cat',
      'regionColors': <String, int>{'cat-body': 0xFF000000},
      'schemaVersion': ColoringSession.currentSchemaVersion,
      'lastUpdatedAtEpochMs': 3,
    });

    final unsupportedRaw = jsonEncode(<String, dynamic>{
      'pageId': 'playful-puppy',
      'regionColors': <String, int>{'puppy-body': 0xFF000000},
      'schemaVersion': 999,
      'lastUpdatedAtEpochMs': 4,
    });

    SharedPreferences.setMockInitialValues(<String, Object>{
      'coloring_session:happy-cat': validRaw,
      'coloring_session:bad-json': '{not valid json}',
      'coloring_session:playful-puppy': unsupportedRaw,
      'coloring_session:bad-map': jsonEncode(<String, dynamic>{'foo': 'bar'}),
    });

    final repository = LocalColoringSessionRepository();

    final sessions = await repository.getAllSessions();

    expect(sessions.length, 1);
    expect(sessions.single.pageId, 'happy-cat');
  });

  test('getAllSessions ignores unrelated SharedPreferences keys', () async {
    final validRaw = jsonEncode(<String, dynamic>{
      'pageId': 'happy-cat',
      'regionColors': <String, int>{'cat-body': 0xFF000000},
      'schemaVersion': ColoringSession.currentSchemaVersion,
      'lastUpdatedAtEpochMs': 3,
    });

    SharedPreferences.setMockInitialValues(<String, Object>{
      'coloring_session:happy-cat': validRaw,
      'not_a_session_key': '42',
      'color_palette': 'blue',
    });

    final repository = LocalColoringSessionRepository();

    final sessions = await repository.getAllSessions();

    expect(sessions.length, 1);
    expect(sessions.single.pageId, 'happy-cat');
  });

  test('one malformed entry does not block other valid entries', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'coloring_session:happy-cat': jsonEncode(<String, dynamic>{
        'pageId': 'happy-cat',
        'regionColors': <String, int>{'cat-body': 0xFF000001},
        'schemaVersion': ColoringSession.currentSchemaVersion,
        'lastUpdatedAtEpochMs': 10,
      }),
      'coloring_session:bad-entry': '{broken json',
      'coloring_session:friendly-lion': jsonEncode(<String, dynamic>{
        'pageId': 'friendly-lion',
        'regionColors': <String, int>{'lion-body': 0xFF000002},
        'schemaVersion': ColoringSession.currentSchemaVersion,
        'lastUpdatedAtEpochMs': 11,
      }),
    });

    final repository = LocalColoringSessionRepository();

    final sessions = await repository.getAllSessions();

    expect(
      sessions.map((session) => session.pageId).toList(),
      ['friendly-lion', 'happy-cat'],
    );
  });
}
