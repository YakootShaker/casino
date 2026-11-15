import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';

class BuzzerColumnWidget extends StatelessWidget {
  final int playerIndex;
  final String playerName;
  final int playerScore;
  final bool isBuzzerActive;
  final bool isLocked;
  final bool isAnswering;
  final bool isOtherPlayerAnswering;
  final ValueNotifier<int?> localActivePlayer;
  final Future<void> Function(int playerIndex) onBuzz;

  const BuzzerColumnWidget({
    super.key,
    required this.playerIndex,
    required this.playerName,
    required this.playerScore,
    required this.isBuzzerActive,
    required this.isLocked,
    required this.isAnswering,
    required this.isOtherPlayerAnswering,
    required this.localActivePlayer,
    required this.onBuzz,
  });

  @override
  Widget build(BuildContext context) {
    final playerColor = AppColors.getPlayerColor(playerIndex);
    final dimColor = AppColors.getPlayerDimColor(playerIndex);

    // Determine visual status
    final bool canBuzz = isBuzzerActive &&
        !isLocked &&
        !isOtherPlayerAnswering &&
        localActivePlayer.value == null;

    final Color backgroundColor;
    final Color borderColor;
    final double borderThickness;

    if (isAnswering) {
      backgroundColor = playerColor.withOpacity(0.35);
      borderColor = playerColor;
      borderThickness = 4.0;
    } else if (isLocked || isOtherPlayerAnswering) {
      backgroundColor = dimColor;
      borderColor = AppColors.border.withOpacity(0.3);
      borderThickness = 1.0;
    } else if (isBuzzerActive) {
      backgroundColor = playerColor.withOpacity(0.18);
      borderColor = playerColor.withOpacity(0.8);
      borderThickness = 2.5;
    } else {
      backgroundColor = AppColors.surface;
      borderColor = AppColors.border;
      borderThickness = 1.0;
    }

    return Expanded(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (!canBuzz) return;

          // Sub-frame synchronous lock
          localActivePlayer.value = playerIndex;
          HapticFeedback.heavyImpact();

          // Dispatch async RPC
          onBuzz(playerIndex);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: borderThickness,
            ),
            boxShadow: isAnswering
                ? [
                    BoxShadow(
                      color: playerColor.withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    )
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Top Player Name & Score Header
              Positioned(
                top: 20,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    Text(
                      playerName.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: isLocked ? AppColors.textDisabled : playerColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? AppColors.surfaceElevated
                            : playerColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLocked
                              ? AppColors.border
                              : playerColor.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        '$playerScore PTS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isLocked
                              ? AppColors.textDisabled
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Center Buzzer Visual / Status
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAnswering) ...[
                    Icon(
                      Icons.mic_rounded,
                      size: 72,
                      color: playerColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'SPEAK ANSWER NOW!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: playerColor,
                      ),
                    ),
                  ] else if (isLocked) ...[
                    const Icon(
                      Icons.lock_rounded,
                      size: 54,
                      color: AppColors.textDisabled,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'LOCKED OUT',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ] else if (isBuzzerActive) ...[
                    Icon(
                      Icons.touch_app_rounded,
                      size: 64,
                      color: playerColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'TAP TO BUZZ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: playerColor,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      Icons.hearing_rounded,
                      size: 48,
                      color: AppColors.textDisabled.withOpacity(0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'LISTEN TO REFEREE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: AppColors.textDisabled.withOpacity(0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
