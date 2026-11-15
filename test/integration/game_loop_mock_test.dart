import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../helpers/mock_supabase.dart';

void main() {
  group('Game Loop Integration Simulation Tests', () {
    late MockGameRepository mockRepo;

    setUp(() {
      mockRepo = MockGameRepository();
    });

    test('Full game loop transitions match specification', () async {
      const roomId = 'test-room-999';

      // 1. Initial Lobby State
      var currentState = TestFixtures.createMockGameState(
        roomId: roomId,
        phase: 'lobby',
        playerNames: ['Player 1', 'Player 2', 'Player 3'],
        playerScores: [0, 0, 0],
      );

      when(() => mockRepo.startGame(roomId)).thenAnswer((_) async {});
      when(() => mockRepo.armBuzzer(roomId)).thenAnswer((_) async {});
      when(() => mockRepo.buzz(roomId, 0)).thenAnswer((_) async => {'success': true, 'player_index': 0});
      when(() => mockRepo.judgeMark(roomId, false)).thenAnswer((_) async => {
        'success': true,
        'phase': 'buzzer_active',
        'locked': [0],
      });
      when(() => mockRepo.buzz(roomId, 1)).thenAnswer((_) async => {'success': true, 'player_index': 1});
      when(() => mockRepo.judgeMark(roomId, true)).thenAnswer((_) async => {
        'success': true,
        'phase': 'question_revealed',
        'next_question_id': 'q-102',
      });

      expect(currentState.isLobby, isTrue);

      // 2. Referee starts game -> Question Revealed
      await mockRepo.startGame(roomId);
      currentState = currentState.copyWith(
        phase: 'question_revealed',
        currentQuestionId: 'q-101',
      );
      expect(currentState.isQuestionRevealed, isTrue);
      expect(currentState.currentQuestionId, equals('q-101'));

      // 3. Referee arms buzzers -> Buzzer Active
      await mockRepo.armBuzzer(roomId);
      currentState = currentState.copyWith(phase: 'buzzer_active');
      expect(currentState.isBuzzerActive, isTrue);

      // 4. Player 0 buzzes in -> Player Answering (10s timer)
      final buzzResult = await mockRepo.buzz(roomId, 0);
      expect(buzzResult['success'], isTrue);
      currentState = currentState.copyWith(
        phase: 'player_answering',
        activePlayerIndex: 0,
        buzzExpiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );
      expect(currentState.isPlayerAnswering, isTrue);
      expect(currentState.activePlayerIndex, equals(0));

      // 5. Referee judges Player 0 incorrect (-1) -> Steal Reopen
      final wrongMark = await mockRepo.judgeMark(roomId, false);
      expect(wrongMark['phase'], equals('buzzer_active'));
      currentState = currentState.copyWith(
        phase: 'buzzer_active',
        playerScores: [-1, 0, 0],
        activePlayerIndex: null,
        lockedPlayerIndices: [0],
        buzzExpiresAt: null,
      );
      expect(currentState.isBuzzerActive, isTrue);
      expect(currentState.isPlayerLocked(0), isTrue);
      expect(currentState.isPlayerLocked(1), isFalse);
      expect(currentState.isPlayerLocked(2), isFalse);

      // 6. Player 1 steals and buzzes in
      final stealBuzz = await mockRepo.buzz(roomId, 1);
      expect(stealBuzz['success'], isTrue);
      currentState = currentState.copyWith(
        phase: 'player_answering',
        activePlayerIndex: 1,
        buzzExpiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );
      expect(currentState.isPlayerAnswering, isTrue);
      expect(currentState.activePlayerIndex, equals(1));

      // 7. Referee judges Player 1 correct (+1) -> Advances to next question
      final correctMark = await mockRepo.judgeMark(roomId, true);
      expect(correctMark['phase'], equals('question_revealed'));
      currentState = currentState.copyWith(
        phase: 'question_revealed',
        playerScores: [-1, 1, 0],
        currentQuestionId: 'q-102',
        activePlayerIndex: null,
        lockedPlayerIndices: [],
        buzzExpiresAt: null,
      );
      expect(currentState.isQuestionRevealed, isTrue);
      expect(currentState.currentQuestionId, equals('q-102'));
      expect(currentState.playerScores, equals([-1, 1, 0]));
      expect(currentState.lockedPlayerIndices, isEmpty);

      // 8. Win condition simulation (Player reaches 5 points)
      currentState = currentState.copyWith(
        phase: 'game_over',
        playerScores: [-1, 5, 2],
        winnerPlayerIndex: 1,
      );
      expect(currentState.isGameOver, isTrue);
      expect(currentState.winnerPlayerIndex, equals(1));
    });
  });
}
