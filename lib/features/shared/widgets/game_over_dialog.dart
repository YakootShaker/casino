import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../game/domain/game_state.dart';

class GameOverDialog extends StatelessWidget {
  final GameState state;

  const GameOverDialog({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final winnerIndex = state.winnerPlayerIndex;
    final winnerName = winnerIndex != null && winnerIndex < state.playerNames.length
        ? state.playerNames[winnerIndex]
        : 'Match Completed';

    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              color: AppColors.warning,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'GAME OVER',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              winnerIndex != null ? 'Winner: $winnerName!' : 'Trivia Concluded',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: winnerIndex != null
                    ? AppColors.getPlayerColor(winnerIndex)
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Scores Table
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: List.generate(3, (index) {
                  final name = index < state.playerNames.length
                      ? state.playerNames[index]
                      : 'Player ${index + 1}';
                  final score = index < state.playerScores.length
                      ? state.playerScores[index]
                      : 0;
                  final isWinner = index == winnerIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppColors.getPlayerColor(index),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isWinner
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (isWinner) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star,
                                color: AppColors.warning,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '$score pts',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.getPlayerColor(index),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final scoresSummary = List.generate(3, (i) {
                        final n = i < state.playerNames.length
                            ? state.playerNames[i]
                            : 'Player ${i + 1}';
                        final s = i < state.playerScores.length
                            ? state.playerScores[i]
                            : 0;
                        return '$n: $s pts';
                      }).join('\n');

                      Share.share(
                        '🏆 Quiz Buzzer Results!\n'
                        'Winner: $winnerName\n\n'
                        'Final Scores:\n$scoresSummary\n\n'
                        'Played on Quiz Buzzer!',
                      );
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.player1,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => context.go('/'),
                    child: const Text(
                      'Home',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
