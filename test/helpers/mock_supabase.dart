import 'package:mocktail/mocktail.dart';
import 'package:quiz_buzzer/features/game/data/game_repository.dart';
import 'package:quiz_buzzer/features/game/domain/game_state.dart';
import 'package:quiz_buzzer/features/game/domain/question.dart';
import 'package:quiz_buzzer/features/game/domain/room.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockPostgrestFilterBuilder extends Mock implements PostgrestFilterBuilder {}
class MockRealtimeChannel extends Mock implements RealtimeChannel {}
class MockGameRepository extends Mock implements GameRepository {}

/// Helper fixtures for tests
class TestFixtures {
  static Room createMockRoom({
    String id = 'room-1234',
    String pin = '123456',
    String refereeUid = 'referee-uid-1',
    String? consoleUid = 'console-uid-2',
  }) {
    return Room(
      id: id,
      roomPin: pin,
      refereeUid: refereeUid,
      consoleUid: consoleUid,
      selectedCategories: const ['General Knowledge'],
      createdAt: DateTime.now(),
      roomExpiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
  }

  static GameState createMockGameState({
    String roomId = 'room-1234',
    String phase = 'question_revealed',
    int stateVersion = 1,
    List<String> playerNames = const ['Alice', 'Bob', 'Charlie'],
    List<int> playerScores = const [0, 0, 0],
    String? currentQuestionId = 'q-101',
    int? activePlayerIndex,
    List<int> lockedPlayerIndices = const [],
    DateTime? buzzExpiresAt,
    int? winnerPlayerIndex,
  }) {
    return GameState(
      roomId: roomId,
      phase: phase,
      stateVersion: stateVersion,
      playerNames: playerNames,
      playerScores: playerScores,
      currentQuestionId: currentQuestionId,
      activePlayerIndex: activePlayerIndex,
      lockedPlayerIndices: lockedPlayerIndices,
      buzzExpiresAt: buzzExpiresAt,
      winnerPlayerIndex: winnerPlayerIndex,
      updatedAt: DateTime.now(),
    );
  }

  static Question createMockQuestion({
    String id = 'q-101',
    String category = 'Science',
    String questionType = 'text',
    String questionText = 'What is the chemical symbol for gold?',
    String referenceAnswer = 'Au',
  }) {
    return Question(
      id: id,
      category: category,
      questionType: questionType,
      questionText: questionText,
      referenceAnswer: referenceAnswer,
    );
  }
}
