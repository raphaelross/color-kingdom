import '../models/coloring_session.dart';

abstract class ColoringSessionRepository {
  Future<List<ColoringSession>> getAllSessions();

  Future<ColoringSession?> getSession(String pageId);

  Future<void> saveSession(ColoringSession session);

  Future<void> deleteSession(String pageId);

  Future<void> clearAllSessions();
}
