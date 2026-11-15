import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../game/data/realtime_service.dart';
import '../../game/domain/game_state.dart';
import '../../game/presentation/providers/countdown_provider.dart';
import '../../game/presentation/providers/game_state_provider.dart';
import '../../game/presentation/providers/question_provider.dart';
import '../../shared/widgets/game_over_dialog.dart';
import '../../shared/widgets/reconnecting_overlay.dart';
import 'widgets/question_display_card.dart';
import 'widgets/scoring_action_bar.dart';

class RefereeCockpitScreen extends ConsumerStatefulWidget {
  final String roomId;

  const RefereeCockpitScreen({super.key, required this.roomId});

  @override
  ConsumerState<RefereeCockpitScreen> createState() => _RefereeCockpitScreenState();
}

class _RefereeCockpitScreenState extends ConsumerState<RefereeCockpitScreen> {
  StreamSubscription<RealtimeConnectionState>? _connSub;
  bool _isReconnecting = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    final realtime = ref.read(realtimeServiceProvider);
    _connSub = realtime.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isReconnecting = state == RealtimeConnectionState.disconnected ||
              state == RealtimeConnectionState.connecting;
        });
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameStateAsync = ref.watch(gameStateNotifierProvider(widget.roomId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Referee Cockpit',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded),
            tooltip: 'Exit Match',
            onPressed: () => _confirmExit(context),
          ),
        ],
      ),
      body: ReconnectingOverlay(
        isReconnecting: _isReconnecting,
        child: gameStateAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.player1),
          ),
          error: (err, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.incorrect),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(gameStateNotifierProvider(widget.roomId).notifier)
                        .refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (state) {
            // Trigger Game Over dialog if match concluded
            if (state.isGameOver && !_dialogShown) {
              _dialogShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => GameOverDialog(state: state),
                );
              });
            }

            return _buildCockpitContent(context, state);
          },
        ),
      ),
    );
  }

  Widget _buildCockpitContent(BuildContext context, GameState state) {
    final questionAsync = ref.watch(questionProvider(state.currentQuestionId));
    final remainingDuration = ref
            .watch(countdownProvider(state.buzzExpiresAt))
            .valueOrNull ??
        Duration.zero;

    // Auto-expire turn when timer hits zero in player_answering
    ref.listen(countdownProvider(state.buzzExpiresAt), (prev, next) {
      if (state.isPlayerAnswering &&
          next.valueOrNull == Duration.zero &&
          prev?.valueOrNull != Duration.zero) {
        ref.read(gameStateNotifierProvider(widget.roomId).notifier).expireTurn();
      }
    });

    final notifier =
        ref.read(gameStateNotifierProvider(widget.roomId).notifier);

    return Column(
      children: [
        // Top Scores Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceElevated,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (index) {
              final name = index < state.playerNames.length
                  ? state.playerNames[index]
                  : 'P${index + 1}';
              final score = index < state.playerScores.length
                  ? state.playerScores[index]
                  : 0;
              final isLocked = state.isPlayerLocked(index);
              final isActive = state.activePlayerIndex == index;
              final col = AppColors.getPlayerColor(index);

              return Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isLocked ? AppColors.textDisabled : col,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.w500,
                      color: isLocked
                          ? AppColors.textDisabled
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isLocked ? AppColors.textDisabled : col,
                    ),
                  ),
                ],
              );
            }),
          ),
        ),

        // Main Question Clue Card Area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: questionAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: AppColors.player1),
                ),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load question: $e'),
              ),
              data: (question) {
                if (question == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text(
                        'No question loaded.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return QuestionDisplayCard(question: question);
              },
            ),
          ),
        ),

        // Bottom Scoring Controls
        ScoringActionBar(
          state: state,
          remainingDuration: remainingDuration,
          onArmBuzzer: () => notifier.armBuzzer(),
          onJudgeMark: (isCorrect) => notifier.judgeMark(isCorrect),
          onSkipQuestion: () => notifier.skipQuestion(),
          onAdjustScore: (playerIndex, delta) =>
              notifier.adjustScore(playerIndex, delta),
        ),
      ],
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Exit Match?'),
        content: const Text(
          'Leaving will return you to the home screen. The game room will remain accessible via PIN until expiration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.incorrect),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/');
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
}
