import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/supabase_client.dart';
import '../../game/data/game_repository.dart';
import '../../game/data/realtime_service.dart';
import '../../game/domain/room.dart';

class RoomSetupScreen extends ConsumerStatefulWidget {
  const RoomSetupScreen({super.key});

  @override
  ConsumerState<RoomSetupScreen> createState() => _RoomSetupScreenState();
}

class _RoomSetupScreenState extends ConsumerState<RoomSetupScreen> {
  final _p1Controller = TextEditingController(text: 'Player 1');
  final _p2Controller = TextEditingController(text: 'Player 2');
  final _p3Controller = TextEditingController(text: 'Player 3');

  final Set<String> _selectedCategories = {'General Knowledge', 'Science'};
  bool _isCreating = false;
  String? _roomId;
  String? _roomPin;
  Room? _room;

  @override
  void dispose() {
    _p1Controller.dispose();
    _p2Controller.dispose();
    _p3Controller.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() => _isCreating = true);
    try {
      final authHelper = ref.read(supabaseAuthProvider);
      await authHelper.ensureAnonymousAuth();

      final repo = ref.read(gameRepositoryProvider);
      final result = await repo.createRoom(
        selectedCategories: _selectedCategories.toList(),
        playerNames: [
          _p1Controller.text.trim().isEmpty ? 'Player 1' : _p1Controller.text.trim(),
          _p2Controller.text.trim().isEmpty ? 'Player 2' : _p2Controller.text.trim(),
          _p3Controller.text.trim().isEmpty ? 'Player 3' : _p3Controller.text.trim(),
        ],
      );

      final rId = result['room_id'] as String;
      final rPin = result['room_pin'] as String;

      setState(() {
        _roomId = rId;
        _roomPin = rPin;
      });

      // Subscribe to room changes to watch for console pairing
      final realtime = ref.read(realtimeServiceProvider);
      realtime.subscribeToRoom(rId);
      realtime.roomStream.listen((updatedRoom) {
        if (mounted) {
          setState(() => _room = updatedRoom);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create room: $e'),
            backgroundColor: AppColors.incorrect,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _startMatch() async {
    if (_roomId == null) return;
    try {
      final repo = ref.read(gameRepositoryProvider);
      await repo.startGame(_roomId!);
      if (mounted) {
        context.go('/referee/$_roomId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start match: $e'),
            backgroundColor: AppColors.incorrect,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Host as Referee'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_roomPin == null) ...[
                // Setup Form
                const Text(
                  '1. Configure Players',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildPlayerField(0, _p1Controller, AppColors.player1),
                const SizedBox(height: 8),
                _buildPlayerField(1, _p2Controller, AppColors.player2),
                const SizedBox(height: 8),
                _buildPlayerField(2, _p3Controller, AppColors.player3),
                const SizedBox(height: 24),

                const Text(
                  '2. Select Categories',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.availableCategories.map((category) {
                    final isSelected = _selectedCategories.contains(category);
                    return FilterChip(
                      label: Text(category),
                      selected: isSelected,
                      selectedColor: AppColors.player1.withOpacity(0.3),
                      checkmarkColor: AppColors.player1,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategories.add(category);
                          } else {
                            if (_selectedCategories.length > 1) {
                              _selectedCategories.remove(category);
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 36),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.player1,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isCreating ? null : _createRoom,
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'GENERATE ROOM PIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ] else ...[
                // Room Created & Pairing View
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'ROOM PAIRING PIN',
                        style: TextStyle(
                          fontSize: 14,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _roomPin!,
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8.0,
                          color: AppColors.player1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Enter this 6-digit PIN on the Players Console device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Pairing Status Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (_room?.isConsoleConnected ?? false)
                        ? AppColors.correct.withOpacity(0.15)
                        : AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_room?.isConsoleConnected ?? false)
                          ? AppColors.correct
                          : AppColors.warning,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (_room?.isConsoleConnected ?? false)
                            ? Icons.check_circle_rounded
                            : Icons.hourglass_top_rounded,
                        color: (_room?.isConsoleConnected ?? false)
                            ? AppColors.correct
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (_room?.isConsoleConnected ?? false)
                              ? 'Players Console Connected! Ready to start.'
                              : 'Waiting for Players Console to join...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: (_room?.isConsoleConnected ?? false)
                                ? AppColors.correct
                                : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.player1,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.surfaceElevated,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (_room?.isConsoleConnected ?? false) ? _startMatch : null,
                  child: const Text(
                    'START MATCH',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerField(
    int index,
    TextEditingController controller,
    Color color,
  ) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Player ${index + 1} Name',
        labelStyle: TextStyle(color: color),
        prefixIcon: Icon(Icons.person, color: color),
        filled: true,
        fillColor: AppColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
      ),
    );
  }
}
