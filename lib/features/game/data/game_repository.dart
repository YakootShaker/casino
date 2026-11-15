import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/game_state.dart';
import '../domain/question.dart';
import '../domain/room.dart';

class GameRepository {
  final SupabaseClient _client;

  GameRepository(this._client);

  /// Creates a new quiz room with 6-digit PIN and initial game state
  Future<Map<String, dynamic>> createRoom({
    List<String> selectedCategories = const [],
    List<String> playerNames = const ['Player 1', 'Player 2', 'Player 3'],
  }) async {
    final response = await _client.rpc(
      'create_room',
      params: {
        'p_selected_categories': selectedCategories,
        'p_player_names': playerNames,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Pairs the players console with an existing room via PIN
  Future<Map<String, dynamic>> joinRoom(String roomPin) async {
    final response = await _client.rpc(
      'join_room',
      params: {'p_room_pin': roomPin.trim()},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Fetches room record by ID
  Future<Room> getRoom(String roomId) async {
    final response = await _client
        .from('rooms')
        .select()
        .eq('id', roomId)
        .single();
    return Room.fromJson(response);
  }

  /// Fetches game state record by room ID
  Future<GameState> getGameState(String roomId) async {
    final response = await _client
        .from('game_states')
        .select()
        .eq('room_id', roomId)
        .single();
    return GameState.fromJson(response);
  }

  /// Fetches question details (strictly accessible to Referee)
  Future<Question?> getQuestion(String questionId) async {
    final response = await _client
        .from('questions')
        .select()
        .eq('id', questionId)
        .maybeSingle();
    if (response == null) return null;
    return Question.fromJson(response);
  }

  /// Starts the match and selects the first trivia question
  Future<void> startGame(String roomId, {String? category}) async {
    await _client.rpc(
      'start_game',
      params: {
        'p_room_id': roomId,
        if (category != null) 'p_category': category,
      },
    );
  }

  /// Referee arms buzzers, transitioning state from question_revealed to buzzer_active
  Future<void> armBuzzer(String roomId) async {
    await _client.rpc(
      'arm_buzzer',
      params: {'p_room_id': roomId},
    );
  }

  /// Console captures hardware touch and claims turn for player
  Future<Map<String, dynamic>> buzz(String roomId, int playerIndex) async {
    final response = await _client.rpc(
      'buzz',
      params: {
        'p_room_id': roomId,
        'p_player_index': playerIndex,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Referee marks verbal answer as correct (+1) or incorrect (-1)
  Future<Map<String, dynamic>> judgeMark(String roomId, bool isCorrect) async {
    final response = await _client.rpc(
      'judge_mark',
      params: {
        'p_room_id': roomId,
        'p_is_correct': isCorrect,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Signals that the 10-second answer timer elapsed
  Future<void> expireTurn(String roomId) async {
    await _client.rpc(
      'expire_turn',
      params: {'p_room_id': roomId},
    );
  }

  /// Manual referee score adjustment
  Future<void> adjustScore(String roomId, int playerIndex, int delta) async {
    await _client.rpc(
      'adjust_score',
      params: {
        'p_room_id': roomId,
        'p_player_index': playerIndex,
        'p_delta': delta,
      },
    );
  }

  /// Skips the current question
  Future<void> skipQuestion(String roomId) async {
    await _client.rpc(
      'skip_question',
      params: {'p_room_id': roomId},
    );
  }

  /// Authoritative server time for clock sync
  Future<DateTime> getServerTime() async {
    final response = await _client.rpc('get_server_time');
    return DateTime.parse(response as String);
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ref.watch(supabaseClientProvider));
});
