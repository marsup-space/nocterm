import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isNotEmpty;

void main() {
  group('FocusManager', () {
    group('auto-focus', () {
      test('first Focusable gets auto-focused on mount', () async {
        final focusedFlags = <bool>[];

        await testNocterm('auto focus', (tester) async {
          await tester.pumpComponent(
            Column(
              children: [
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    focusedFlags.add(Focus.of(context));
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: const Text('B'),
                ),
              ],
            ),
          );

          expect(focusedFlags, isNotEmpty);
          expect(focusedFlags.last, isTrue);
        });
      });

      test('autofocus takes priority', () async {
        final focusedFlags = <bool>[];

        await testNocterm('autofocus priority', (tester) async {
          await tester.pumpComponent(
            Column(
              children: [
                Focusable(
                  onKeyEvent: (_) => false,
                  child: const Text('A'),
                ),
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    focusedFlags.add(Focus.of(context));
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(focusedFlags, isNotEmpty);
          expect(focusedFlags.last, isTrue);
        });
      });
    });

    test('unfocus returns focus to the first enabled focusable', () async {
      int activeIndex = -1;

      await testNocterm('unfocus returns first', (tester) async {
        await tester.pumpComponent(
          Column(
            children: [
              Focusable(
                onKeyEvent: (_) => false,
                child: Builder(builder: (context) {
                  if (Focus.of(context)) activeIndex = 0;
                  return const Text('input');
                }),
              ),
              Focusable(
                autofocus: true,
                onKeyEvent: (_) => false,
                child: Builder(builder: (context) {
                  if (Focus.of(context)) activeIndex = 1;
                  return const Text('surface');
                }),
              ),
            ],
          ),
        );

        expect(activeIndex, equals(1));
        NoctermBinding.instance.focusManager.unfocus();
        await tester.pump();
        expect(activeIndex, equals(0));
      });
    });

    group('Tab navigation', () {
      test('Tab moves to next Focusable', () async {
        int activeIndex = -1;

        await testNocterm('tab next', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.tab);
          expect(activeIndex, equals(1));
        });
      });

      test('Shift+Tab moves to previous Focusable', () async {
        int activeIndex = -1;

        await testNocterm('shift tab prev', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.tab);
          expect(activeIndex, equals(1));

          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.tab,
              modifiers: const ModifierKeys(shift: true),
            ),
          );
          expect(activeIndex, equals(0));
        });
      });

      test('Tab wraps around', () async {
        int activeIndex = -1;

        await testNocterm('tab wrap', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.tab);
          expect(activeIndex, equals(1));

          await tester.sendKey(LogicalKey.tab);
          expect(activeIndex, equals(0));
        });
      });
    });

    group('Arrow key navigation', () {
      test('Right arrow moves to next in Row', () async {
        int activeIndex = -1;

        await testNocterm('arrow right in row', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(1));
        });
      });

      test('Left arrow moves to previous in Row', () async {
        int activeIndex = -1;

        await testNocterm('arrow left in row', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(1));

          await tester.sendKey(LogicalKey.arrowLeft);
          expect(activeIndex, equals(0));
        });
      });

      test('Down arrow moves to next in Column', () async {
        int activeIndex = -1;

        await testNocterm('arrow down in column', (tester) async {
          await tester.pumpComponent(
            Column(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.arrowDown);
          expect(activeIndex, equals(1));
        });
      });

      test('Up arrow moves to previous in Column', () async {
        int activeIndex = -1;

        await testNocterm('arrow up in column', (tester) async {
          await tester.pumpComponent(
            Column(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.arrowDown);
          expect(activeIndex, equals(1));

          await tester.sendKey(LogicalKey.arrowUp);
          expect(activeIndex, equals(0));
        });
      });

      test('Arrow keys wrap within container', () async {
        int activeIndex = -1;

        await testNocterm('arrow wrap', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(1));

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(0));
        });
      });
    });

    group('Cross-axis navigation', () {
      test('Down arrow jumps from Row to sibling Row', () async {
        int activeIndex = -1;

        await testNocterm('cross axis row to row', (tester) async {
          await tester.pumpComponent(
            Column(
              children: [
                Row(
                  children: [
                    Focusable(
                      autofocus: true,
                      onKeyEvent: (_) => false,
                      child: Builder(builder: (context) {
                        if (Focus.of(context)) activeIndex = 0;
                        return const Text('A');
                      }),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Focusable(
                      onKeyEvent: (_) => false,
                      child: Builder(builder: (context) {
                        if (Focus.of(context)) activeIndex = 1;
                        return const Text('B');
                      }),
                    ),
                  ],
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.arrowDown);
          expect(activeIndex, equals(1));
        });
      });
    });

    group('Disabled Focusable', () {
      test('disabled Focusable is skipped during Tab', () async {
        int activeIndex = -1;

        await testNocterm('disabled skip tab', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  disabled: true,
                  onKeyEvent: (_) => false,
                  child: const Text('B (disabled)'),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 2;
                    return const Text('C');
                  }),
                ),
              ],
            ),
          );

          await tester.sendKey(LogicalKey.tab);
          expect(activeIndex, equals(2));
        });
      });
    });

    group('Focus.of(context)', () {
      test('returns false for unfocused Focusable', () async {
        bool secondFocused = true;

        await testNocterm('focus of unfocused', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (_) => false,
                  child: const Text('A'),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    secondFocused = Focus.of(context);
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(secondFocused, isFalse);
        });
      });
    });

    group('Unhandled arrows trigger navigation', () {
      test('arrow key not consumed by Focusable triggers focus move', () async {
        int activeIndex = -1;

        await testNocterm('unhandled arrow nav', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (event) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(1));
        });
      });

      test('arrow key consumed by Focusable does not trigger focus move',
          () async {
        int activeIndex = -1;

        await testNocterm('consumed arrow no nav', (tester) async {
          await tester.pumpComponent(
            Row(
              children: [
                Focusable(
                  autofocus: true,
                  onKeyEvent: (event) {
                    if (event.logicalKey == LogicalKey.arrowRight) return true;
                    return false;
                  },
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 0;
                    return const Text('A');
                  }),
                ),
                Focusable(
                  onKeyEvent: (_) => false,
                  child: Builder(builder: (context) {
                    if (Focus.of(context)) activeIndex = 1;
                    return const Text('B');
                  }),
                ),
              ],
            ),
          );

          expect(activeIndex, equals(0));

          await tester.sendKey(LogicalKey.arrowRight);
          expect(activeIndex, equals(0));
        });
      });
    });
  });
}
