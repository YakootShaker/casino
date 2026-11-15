import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_buzzer/features/console/presentation/widgets/buzzer_column_widget.dart';

void main() {
  Widget buildTestWidget({
    required Widget child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [child],
        ),
      ),
    );
  }

  group('BuzzerColumnWidget Tests', () {
    testWidgets('Renders player name, score and tap to buzz prompt when active',
        (tester) async {
      final localLock = ValueNotifier<int?>(null);
      bool buzzCalled = false;

      await tester.pumpWidget(
        buildTestWidget(
          child: BuzzerColumnWidget(
            playerIndex: 0,
            playerName: 'Zeus',
            playerScore: 3,
            isBuzzerActive: true,
            isLocked: false,
            isAnswering: false,
            isOtherPlayerAnswering: false,
            localActivePlayer: localLock,
            onBuzz: (idx) async {
              buzzCalled = true;
            },
          ),
        ),
      );

      expect(find.text('ZEUS'), findsOneWidget);
      expect(find.text('3 PTS'), findsOneWidget);
      expect(find.text('TAP TO BUZZ'), findsOneWidget);

      // Tap on column
      await tester.tap(find.text('TAP TO BUZZ'));
      await tester.pump();

      expect(buzzCalled, isTrue);
      expect(localLock.value, equals(0));
    });

    testWidgets('Displays locked out state and rejects pointer taps',
        (tester) async {
      final localLock = ValueNotifier<int?>(null);
      bool buzzCalled = false;

      await tester.pumpWidget(
        buildTestWidget(
          child: BuzzerColumnWidget(
            playerIndex: 1,
            playerName: 'Ares',
            playerScore: 1,
            isBuzzerActive: true,
            isLocked: true,
            isAnswering: false,
            isOtherPlayerAnswering: false,
            localActivePlayer: localLock,
            onBuzz: (idx) async {
              buzzCalled = true;
            },
          ),
        ),
      );

      expect(find.text('LOCKED OUT'), findsOneWidget);

      await tester.tap(find.text('LOCKED OUT'));
      await tester.pump();

      expect(buzzCalled, isFalse);
      expect(localLock.value, isNull);
    });

    testWidgets('Displays answering highlight when active player',
        (tester) async {
      final localLock = ValueNotifier<int?>(0);

      await tester.pumpWidget(
        buildTestWidget(
          child: BuzzerColumnWidget(
            playerIndex: 0,
            playerName: 'Zeus',
            playerScore: 4,
            isBuzzerActive: false,
            isLocked: false,
            isAnswering: true,
            isOtherPlayerAnswering: false,
            localActivePlayer: localLock,
            onBuzz: (_) async {},
          ),
        ),
      );

      expect(find.text('SPEAK ANSWER NOW!'), findsOneWidget);
    });
  });
}
