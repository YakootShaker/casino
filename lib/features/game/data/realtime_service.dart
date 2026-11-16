import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_client.dart';
import '../domain/game_state.dart';
import '../domain/room.dart';

enum RealtimeConnectionState { connected, connecting, disconnected, error }

class RealtimeService {
  final SupabaseClient _client;

  RealtimeChannel? _gameChannel;
  final _gameStateController = StreamController<GameState>.broadcast();
  final _roomController = StreamController<Room>.broadcast();
  final _connectionStateController =
      StreamController<RealtimeConnectionState>.broadcast();

  int _latestVersion = 0;

  RealtimeService(this._client);

  Stream<GameState> get gameStateStream => _gameStateController.stream;
  Stream<Room> get roomStream => _roomController.stream;
  Stream<RealtimeConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Subscribes to real-time updates for a given room
  void subscribeToRoom(String roomId) {
    unsubscribe();

    _connectionStateController.add(RealtimeConnectionState.connecting);

    _gameChannel = _client.channel('room:$roomId');

    // Listen to Game States table changes
    _gameChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'game_states',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final state = GameState.fromJson(newRecord);
                // Ensure monotonic version ordering
                if (state.stateVersion >= _latestVersion) {
                  _latestVersion = state.stateVersion;
                  _gameStateController.add(state);
                }
              }
            } catch (e) {
              debugPrint('Failed to decode game state payload: $e');
            }
          },
        )
        // Listen to Room table changes (e.g. console_uid pairing)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final room = Room.fromJson(newRecord);
                _roomController.add(room);
              }
            } catch (e) {
              debugPrint('Failed to decode room payload: $e');
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Realtime channel status: $status, error: $error');
          if (status == RealtimeSubscribeStatus.subscribed) {
            _connectionStateController.add(RealtimeConnectionState.connected);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _connectionStateController.add(RealtimeConnectionState.disconnected);
          } else if (status == RealtimeSubscribeStatus.closed) {
            _connectionStateController.add(RealtimeConnectionState.disconnected);
          }
        });
  }

  void unsubscribe() {
    if (_gameChannel != null) {
      _client.removeChannel(_gameChannel!);
      _gameChannel = null;
    }
    _latestVersion = 0;
  }

  void dispose() {
    unsubscribe();
    _gameStateController.close();
    _roomController.close();
    _connectionStateController.close();
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService(ref.watch(supabaseClientProvider));
  ref.onDispose(() => service.dispose());
  return service;
});
