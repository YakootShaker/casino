import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/console/presentation/pin_entry_screen.dart';
import '../features/console/presentation/players_console_screen.dart';
import '../features/home/presentation/landing_screen.dart';
import '../features/referee/presentation/referee_cockpit_screen.dart';
import '../features/referee/presentation/room_setup_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'landing',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/host',
        name: 'host',
        builder: (context, state) => const RoomSetupScreen(),
      ),
      GoRoute(
        path: '/join',
        name: 'join',
        builder: (context, state) => const PinEntryScreen(),
      ),
      GoRoute(
        path: '/referee/:roomId',
        name: 'referee',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          return RefereeCockpitScreen(roomId: roomId);
        },
      ),
      GoRoute(
        path: '/console/:roomId',
        name: 'console',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          return PlayersConsoleScreen(roomId: roomId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.uri}'),
      ),
    ),
  );
});
