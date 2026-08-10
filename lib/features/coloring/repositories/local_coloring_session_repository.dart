import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/coloring_session.dart';
import 'coloring_session_repository.dart';

class LocalColoringSessionRepository implements ColoringSessionRepository {
  LocalColoringSessionRepository({SharedPreferences? sharedPreferences})
      : _sharedPreferencesFuture = sharedPreferences != null
            ? Future.value(sharedPreferences)
            : SharedPreferences.getInstance();

  static const String _sessionKeyPrefix = 'coloring_session:';

  final Future<SharedPreferences> _sharedPreferencesFuture;

  String _keyForPage(String pageId) => '$_sessionKeyPrefix$pageId';

  @override
  Future<ColoringSession?> getSession(String pageId) async {
    try {
      final preferences = await _sharedPreferencesFuture;
      final rawSession = preferences.getString(_keyForPage(pageId));
      if (rawSession == null) {
        return null;
      }

      final decoded = jsonDecode(rawSession);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('ColoringSession decode failed for $pageId: not a JSON object');
        return null;
      }

      return ColoringSession.fromJson(decoded);
    } on UnsupportedError catch (error) {
      debugPrint('ColoringSession ignored for $pageId: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('ColoringSession malformed for $pageId: $error');
      return null;
    } catch (error) {
      debugPrint('ColoringSession load failed for $pageId: $error');
      return null;
    }
  }

  @override
  Future<void> saveSession(ColoringSession session) async {
    final preferences = await _sharedPreferencesFuture;
    final key = _keyForPage(session.pageId);
    final value = jsonEncode(session.toJson());
    final didSave = await preferences.setString(key, value);
    if (!didSave) {
      throw StateError('Failed to save coloring session for page ${session.pageId}.');
    }
  }

  @override
  Future<void> deleteSession(String pageId) async {
    final preferences = await _sharedPreferencesFuture;
    final didDelete = await preferences.remove(_keyForPage(pageId));
    if (!didDelete) {
      throw StateError('Failed to delete coloring session for page $pageId.');
    }
  }

  @override
  Future<void> clearAllSessions() async {
    final preferences = await _sharedPreferencesFuture;
    final keys = preferences.getKeys();
    for (final key in keys) {
      if (!key.startsWith(_sessionKeyPrefix)) {
        continue;
      }

      final didDelete = await preferences.remove(key);
      if (!didDelete) {
        throw StateError('Failed to delete coloring session key $key.');
      }
    }
  }
}
