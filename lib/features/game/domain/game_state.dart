class GameState {
  final String roomId;
  final String phase;
  final int stateVersion;
  final List<String> playerNames;
  final List<int> playerScores;
  final String? currentQuestionId;
  final int? activePlayerIndex;
  final List<int> lockedPlayerIndices;
  final DateTime? buzzExpiresAt;
  final int? winnerPlayerIndex;
  final DateTime updatedAt;

  const GameState({
    required this.roomId,
    required this.phase,
    required this.stateVersion,
    this.playerNames = const ['Player 1', 'Player 2', 'Player 3'],
    this.playerScores = const [0, 0, 0],
    this.currentQuestionId,
    this.activePlayerIndex,
    this.lockedPlayerIndices = const [],
    this.buzzExpiresAt,
    this.winnerPlayerIndex,
    required this.updatedAt,
  });

  bool get isLobby => phase == 'lobby';
  bool get isQuestionRevealed => phase == 'question_revealed';
  bool get isBuzzerActive => phase == 'buzzer_active';
  bool get isPlayerAnswering => phase == 'player_answering';
  bool get isJudgeEvaluating => phase == 'judge_evaluating';
  bool get isGameOver => phase == 'game_over';

  bool isPlayerLocked(int index) => lockedPlayerIndices.contains(index);

  factory GameState.initial(String roomId) {
    return GameState(
      roomId: roomId,
      phase: 'lobby',
      stateVersion: 1,
      playerNames: const ['Player 1', 'Player 2', 'Player 3'],
      playerScores: const [0, 0, 0],
      lockedPlayerIndices: const [],
      updatedAt: DateTime.now(),
    );
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      roomId: json['room_id'] as String,
      phase: json['phase'] as String,
      stateVersion: (json['state_version'] as num?)?.toInt() ?? 1,
      playerNames: (json['player_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Player 1', 'Player 2', 'Player 3'],
      playerScores: (json['player_scores'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [0, 0, 0],
      currentQuestionId: json['current_question_id'] as String?,
      activePlayerIndex: (json['active_player_index'] as num?)?.toInt(),
      lockedPlayerIndices: (json['locked_player_indices'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      buzzExpiresAt: json['buzz_expires_at'] != null
          ? DateTime.parse(json['buzz_expires_at'] as String)
          : null,
      winnerPlayerIndex: (json['winner_player_index'] as num?)?.toInt(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'phase': phase,
      'state_version': stateVersion,
      'player_names': playerNames,
      'player_scores': playerScores,
      'current_question_id': currentQuestionId,
      'active_player_index': activePlayerIndex,
      'locked_player_indices': lockedPlayerIndices,
      'buzz_expires_at': buzzExpiresAt?.toIso8601String(),
      'winner_player_index': winnerPlayerIndex,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  GameState copyWith({
    String? roomId,
    String? phase,
    int? stateVersion,
    List<String>? playerNames,
    List<int>? playerScores,
    String? currentQuestionId,
    int? activePlayerIndex,
    List<int>? lockedPlayerIndices,
    DateTime? buzzExpiresAt,
    int? winnerPlayerIndex,
    DateTime? updatedAt,
  }) {
    return GameState(
      roomId: roomId ?? this.roomId,
      phase: phase ?? this.phase,
      stateVersion: stateVersion ?? this.stateVersion,
      playerNames: playerNames ?? this.playerNames,
      playerScores: playerScores ?? this.playerScores,
      currentQuestionId: currentQuestionId ?? this.currentQuestionId,
      activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
      lockedPlayerIndices: lockedPlayerIndices ?? this.lockedPlayerIndices,
      buzzExpiresAt: buzzExpiresAt ?? this.buzzExpiresAt,
      winnerPlayerIndex: winnerPlayerIndex ?? this.winnerPlayerIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
