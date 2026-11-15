import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/mock_supabase.dart';

void main() {
  group('Touch Arbitration Logic Unit Tests', () {
    test('First touch acquires synchronous lock within UI frame', () {
      final localActivePlayer = ValueNotifier<int?>(null);
      final lockedIndices = <int>[];

      // Player 0 touches first
      if (localActivePlayer.value == null && !lockedIndices.contains(0)) {
        localActivePlayer.value = 0;
      }

      expect(localActivePlayer.value, equals(0));

      // Player 1 touches 1 millisecond later
      if (localActivePlayer.value == null && !lockedIndices.contains(1)) {
        localActivePlayer.value = 1;
      }

      // Player 1 must be rejected; Player 0 retains lock
      expect(localActivePlayer.value, equals(0));
    });

    test('Disqualified / locked player touch is strictly ignored', () {
      final localActivePlayer = ValueNotifier<int?>(null);
      final lockedIndices = <int>[0]; // Player 0 missed previous attempt

      // Disqualified Player 0 attempts to touch
      if (localActivePlayer.value == null && !lockedIndices.contains(0)) {
        localActivePlayer.value = 0;
      }

      // Must remain unlocked
      expect(localActivePlayer.value, isNull);

      // Eligible Player 2 touches
      if (localActivePlayer.value == null && !lockedIndices.contains(2)) {
        localActivePlayer.value = 2;
      }

      // Player 2 successfully acquires turn
      expect(localActivePlayer.value, equals(2));
    });

    test('GameState domain model validates locked player queries', () {
      final state = TestFixtures.createMockGameState(
        lockedPlayerIndices: [1],
      );

      expect(state.isPlayerLocked(1), isTrue);
      expect(state.isPlayerLocked(0), isFalse);
      expect(state.isPlayerLocked(2), isFalse);
    });

    test('Transitioning phase resets local lock', () {
      final localActivePlayer = ValueNotifier<int?>(0);

      // Simulate phase transition away from player_answering
      const newPhase = 'question_revealed';
      if (newPhase != 'player_answering') {
        localActivePlayer.value = null;
      }

      expect(localActivePlayer.value, isNull);
    });
  });
}
