import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('TextField word-delete bindings', () {
    Future<void> setupField(tester, TextEditingController controller) async {
      await tester.pumpComponent(
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: TextField(
            controller: controller,
            focused: true,
          ),
        ),
      );
    }

    test('Ctrl+Backspace deletes the word to the left of the cursor', () async {
      await testNocterm(
        'Ctrl+Backspace word delete',
        (tester) async {
          final controller = TextEditingController(text: 'hello world foo');
          await setupField(tester, controller);

          // Move cursor to end and clear any selection.
          await tester.sendKey(LogicalKey.end);
          expect(controller.selection.extentOffset, controller.text.length);

          await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.backspace,
            modifiers: ModifierKeys(ctrl: true),
          ));

          expect(controller.text, equals('hello world '));
        },
      );
    });

    test('Alt+Backspace deletes the word to the left of the cursor', () async {
      await testNocterm(
        'Alt+Backspace word delete (terminal-agnostic fallback)',
        (tester) async {
          final controller = TextEditingController(text: 'hello world foo');
          await setupField(tester, controller);

          await tester.sendKey(LogicalKey.end);
          await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.backspace,
            modifiers: ModifierKeys(alt: true),
          ));

          expect(controller.text, equals('hello world '));
        },
      );
    });

    test('Ctrl+W deletes the word to the left of the cursor', () async {
      await testNocterm(
        'Ctrl+W word delete (readline convention)',
        (tester) async {
          final controller = TextEditingController(text: 'hello world foo');
          await setupField(tester, controller);

          await tester.sendKey(LogicalKey.end);
          await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.keyW,
            modifiers: ModifierKeys(ctrl: true),
          ));

          expect(controller.text, equals('hello world '));
        },
      );
    });

    test('plain Backspace still deletes only one character', () async {
      await testNocterm(
        'plain Backspace is unaffected',
        (tester) async {
          final controller = TextEditingController(text: 'hello world foo');
          await setupField(tester, controller);

          await tester.sendKey(LogicalKey.end);
          await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.backspace,
          ));

          expect(controller.text, equals('hello world fo'));
        },
      );
    });

    test('Ctrl+W in the middle of a word deletes back to the previous word',
        () async {
      await testNocterm(
        'Ctrl+W mid-word',
        (tester) async {
          final controller = TextEditingController(text: 'hello world foo');
          await setupField(tester, controller);

          // Position cursor in the middle of "world" (after "wo").
          controller.selection = const TextSelection.collapsed(offset: 8);
          await tester.pump();

          await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.keyW,
            modifiers: ModifierKeys(ctrl: true),
          ));

          // Should remove "wo" + the preceding space, leaving "hello rld foo".
          expect(controller.text, equals('hello rld foo'));
        },
      );
    });
  });
}
