import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../game/data/realtime_service.dart';
import '../../game/domain/game_state.dart';
import '../../game/presentation/providers/countdown_provider.dart';
import '../../game/presentation/providers/game_state_provider.dart';
import '../../../core/widgets/game_over_dialog.dart';
import '../../../core/widgets/reconnecting_overlay.dart';
import 'widgets/buzzer_column_widget.dart';

class PlayersConsoleScreen extends ConsumerStatefulWidget {
  final String roomId;

  const PlayersConsoleScreen({super.key, required this.roomId});

  @override
  ConsumerState<PlayersConsoleScreen> createState() => _PlayersConsoleScreenState();
}

class _PlayersConsoleScreenState extends ConsumerState<PlayersConsoleScreen> {
  StreamSubscription<RealtimeConnectionState>? _connSub;
  bool _isReconnecting = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Enforce Landscape orientation for the 3-player console
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();

    final realtime = ref.read(realtimeServiceProvider);
    _connSub = realtime.connectionStateStream.listen((connState) {
      if (mounted) {
        setState(() {
          _isReconnecting = connState == RealtimeConnectionState.disconnected ||
              connState == RealtimeConnectionState.connecting;
        });
      }
    });
  }

  @override
  void dispose() {
    // Restore orientation settings
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.disable();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameStateAsync = ref.watch(gameStateNotifierProvider(widget.roomId));

    return Scaffold(
      backgroundColor: AppColors.background,
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

            if (state.isLobby) {
              return _buildLobbyWaitingView(context);
            }

            return _buildConsoleActiveView(context, state);
          },
        ),
      ),
    );
  }

  Widget _buildLobbyWaitingView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: AppColors.player1,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'CONSOLE CONNECTED',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Waiting for the Referee to start the match on Device 1...',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
            ),
            onPressed: () => context.go('/'),
            child: const Text('Cancel & Return Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleActiveView(BuildContext context, GameState state) {
    final notifier =
        ref.read(gameStateNotifierProvider(widget.roomId).notifier);
    final remainingDuration = ref
            .watch(countdownProvider(state.buzzExpiresAt))
            .valueOrNull ??
        Duration.zero;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          children: [
            // Top Countdown Progress Bar (Active when answering)
            if (state.isPlayerAnswering) ...[
              Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (remainingDuration.inMilliseconds /
                            (AppConstants.turnDurationSeconds * 1000))
                        .clamp(0.0, 1.0),
                    backgroundColor: AppColors.surfaceElevated,
                    color: AppColors.countdownProgress,
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 14),

            // 3 Equal-Width Player Buzzer Columns
            Expanded(
              child: Row(
                children: List.generate(3, (index) {
                  final name = index < state.playerNames.length
                      ? state.playerNames[index]
                      : 'Player ${index + 1}';
                  final score = index < state.playerScores.length
                      ? state.playerScores[index]
                      : 0;
                  final isLocked = state.isPlayerLocked(index);
                  final isAnswering = state.activePlayerIndex == index;
                  final isOtherAnswering = state.activePlayerIndex != null &&
                      state.activePlayerIndex != index;

                  return BuzzerColumnWidget(
                    playerIndex: index,
                    playerName: name,
                    playerScore: score,
                    isBuzzerActive: state.isBuzzerActive,
                    isLocked: isLocked,
                    isAnswering: isAnswering,
                    isOtherPlayerAnswering: isOtherAnswering,
                    localActivePlayer: notifier.localActivePlayer,
                    onBuzz: (playerIndex) => notifier.buzz(playerIndex),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
