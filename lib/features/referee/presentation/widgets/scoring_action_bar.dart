import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../game/domain/game_state.dart';

class ScoringActionBar extends StatelessWidget {
  final GameState state;
  final Duration remainingDuration;
  final VoidCallback onArmBuzzer;
  final ValueChanged<bool> onJudgeMark;
  final VoidCallback onSkipQuestion;
  final void Function(int playerIndex, int delta) onAdjustScore;

  const ScoringActionBar({
    super.key,
    required this.state,
    required this.remainingDuration,
    required this.onArmBuzzer,
    required this.onJudgeMark,
    required this.onSkipQuestion,
    required this.onAdjustScore,
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = state.activePlayerIndex;
    final activeName = activeIndex != null && activeIndex < state.playerNames.length
        ? state.playerNames[activeIndex]
        : '';
    final activeColor = activeIndex != null
        ? AppColors.getPlayerColor(activeIndex)
        : AppColors.surfaceElevated;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phase-specific Action Controls
          if (state.isQuestionRevealed) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.player1,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onArmBuzzer,
                    icon: const Icon(Icons.touch_app_rounded),
                    label: const Text(
                      'OPEN BUZZERS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onSkipQuestion,
                  child: const Text('Skip'),
                ),
              ],
            ),
          ] else if (state.isBuzzerActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.player1.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.player1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Buzzers Active — Waiting for player...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSkipQuestion,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
          ] else if (state.isPlayerAnswering || state.isJudgeEvaluating) ...[
            // Active Player Banner & Timer
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: activeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: activeColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        activeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: activeColor,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    state.isJudgeEvaluating
                        ? 'TIME EXPIRED'
                        : '${(remainingDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: state.isJudgeEvaluating
                          ? AppColors.incorrect
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            // Evaluation Verdict Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.correct,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => onJudgeMark(true),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(
                      state.isJudgeEvaluating ? 'Spoke (+1)' : 'CORRECT (+1)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.incorrect,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => onJudgeMark(false),
                    icon: const Icon(Icons.cancel_rounded),
                    label: Text(
                      state.isJudgeEvaluating ? 'Timeout (-1)' : 'WRONG (-1)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 8),

          // Manual +/- Score Adjuster Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (index) {
              final name = index < state.playerNames.length
                  ? state.playerNames[index]
                  : 'P${index + 1}';
              final score = index < state.playerScores.length
                  ? state.playerScores[index]
                  : 0;
              final col = AppColors.getPlayerColor(index);

              return Column(
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: col,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => onAdjustScore(index, -1),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.remove, size: 14, color: AppColors.textSecondary),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          '$score',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: col,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => onAdjustScore(index, 1),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.add, size: 14, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
