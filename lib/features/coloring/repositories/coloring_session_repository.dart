import '../models/coloring_session.dart';

abstract class ColoringSessionRepository {
  Future<ColoringSession?> getSession(String pageId);

  Future<void> saveSession(ColoringSession session);

  Future<void> deleteSession(String pageId);

  Future<void> clearAllSessions();
}
