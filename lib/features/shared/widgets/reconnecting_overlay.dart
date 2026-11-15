import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ReconnectingOverlay extends StatelessWidget {
  final bool isReconnecting;
  final Widget child;

  const ReconnectingOverlay({
    super.key,
    required this.isReconnecting,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isReconnecting)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppColors.player1,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Reconnecting...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Syncing game state with server',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
