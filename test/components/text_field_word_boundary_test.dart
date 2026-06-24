import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

int _defaultPreviousBoundary(String text, int offset) {
  int pos = offset;
  while (pos > 0 && _isSpace(text.codeUnitAt(pos - 1))) {
    pos--;
  }
  while (pos > 0 && !_isSpace(text.codeUnitAt(pos - 1))) {
    pos--;
  }
  return pos;
}

int _defaultNextBoundary(String text, int offset) {
  final len = text.length;
  int pos = offset;
  while (pos < len && !_isSpace(text.codeUnitAt(pos))) {
    pos++;
  }
  while (pos < len && _isSpace(text.codeUnitAt(pos))) {
    pos++;
  }
  return pos;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A || codeUnit == 0x0D;

final WordBoundaryProvider testWordBoundaryProvider = (
  previousBoundary: _defaultPreviousBoundary,
  nextBoundary: _defaultNextBoundary,
);

void main() {
  group('Ctrl+Backspace word deletion', () {
    test('deletes last word with default logic', () async {
      await testNocterm('ctrl+backspace default', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        expect(controller.text, equals('hello world'));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });

    test('deletes last word with wordBoundaryProvider', () async {
      await testNocterm('ctrl+backspace with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        expect(controller.text, equals('hello world'));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });

    test('deletes word then spaces with provider', () async {
      await testNocterm('ctrl+backspace deletes word+spaces', (tester) async {
        final controller = TextEditingController(text: 'hello world  ');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });
  });

  group('Ctrl+Delete forward word deletion', () {
    test('deletes next word with default logic', () async {
      await testNocterm('ctrl+delete default', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        // Move cursor to beginning
        for (int i = 0; i < 11; i++) {
          await tester.sendKey(LogicalKey.arrowLeft);
        }

        // Move to after "hello "
        for (int i = 0; i < 6; i++) {
          await tester.sendKey(LogicalKey.arrowRight);
        }

        expect(controller.selection.extentOffset, equals(6));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.delete,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });

    test('deletes next word with wordBoundaryProvider', () async {
      await testNocterm('ctrl+delete with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        for (int i = 0; i < 11; i++) {
          await tester.sendKey(LogicalKey.arrowLeft);
        }
        for (int i = 0; i < 6; i++) {
          await tester.sendKey(LogicalKey.arrowRight);
        }

        expect(controller.selection.extentOffset, equals(6));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.delete,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });
  });

  group('Alternative keybindings for word deletion', () {
    test('Alt+Backspace deletes word backward', () async {
      await testNocterm('alt+backspace', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: ModifierKeys(alt: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });

    test('Ctrl+W deletes word backward', () async {
      await testNocterm('ctrl+w', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyW,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });

    test('Alt+Delete deletes word forward', () async {
      await testNocterm('alt+delete', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        // Move cursor to after "hello "
        for (int i = 0; i < 5; i++) {
          await tester.sendKey(LogicalKey.arrowLeft);
        }

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.delete,
          modifiers: ModifierKeys(alt: true),
        ));

        expect(controller.text, equals('hello '));
      });
    });
  });

  group('Ctrl+Arrow word navigation with provider', () {
    test('moves cursor by word backward', () async {
      await testNocterm('ctrl+left with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        expect(controller.selection.extentOffset, equals(11));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowLeft,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.selection.extentOffset, equals(6));
      });
    });

    test('moves cursor by word forward', () async {
      await testNocterm('ctrl+right with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        // Move to start
        for (int i = 0; i < 11; i++) {
          await tester.sendKey(LogicalKey.arrowLeft);
        }
        expect(controller.selection.extentOffset, equals(0));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowRight,
          modifiers: ModifierKeys(ctrl: true),
        ));

        expect(controller.selection.extentOffset, equals(6));
      });
    });
  });

  // macOS binds Ctrl+< / Ctrl+> to Mission Control, so the user can't use
  // Ctrl+Arrow for word movement there. Option+Arrow (Alt+Arrow) is the
  // macOS-native equivalent and must produce the same behavior.
  group('Alt+Arrow word navigation (macOS Option+Arrow)', () {
    test('moves cursor by word backward with provider', () async {
      await testNocterm('alt+left with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        expect(controller.selection.extentOffset, equals(11));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowLeft,
          modifiers: ModifierKeys(alt: true),
        ));

        expect(controller.selection.extentOffset, equals(6));
      });
    });

    test('moves cursor by word forward with provider', () async {
      await testNocterm('alt+right with provider', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        for (int i = 0; i < 11; i++) {
          await tester.sendKey(LogicalKey.arrowLeft);
        }
        expect(controller.selection.extentOffset, equals(0));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowRight,
          modifiers: ModifierKeys(alt: true),
        ));

        expect(controller.selection.extentOffset, equals(6));
      });
    });

    test('moves cursor by word backward with default boundary', () async {
      await testNocterm('alt+left default', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
            ),
          ),
        );

        expect(controller.selection.extentOffset, equals(11));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowLeft,
          modifiers: ModifierKeys(alt: true),
        ));

        expect(controller.selection.extentOffset, equals(6));
      });
    });

    test('Shift+Alt+Arrow extends selection by word', () async {
      await testNocterm('shift+alt+left extends selection', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        expect(controller.selection.extentOffset, equals(11));
        expect(controller.selection.isCollapsed, isTrue);

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowLeft,
          modifiers: ModifierKeys(alt: true, shift: true),
        ));

        // Selection should now span from after "hello " (offset 6) to
        // the original cursor position (offset 11).
        expect(controller.selection.isCollapsed, isFalse);
        expect(controller.selection.baseOffset, equals(11));
        expect(controller.selection.extentOffset, equals(6));
      });
    });

    test('plain Shift+Arrow still extends by character', () async {
      // Regression guard: the new word-move branches must not swallow
      // plain Shift+Arrow (no Ctrl, no Alt).
      await testNocterm('shift+left extends by one char', (tester) async {
        final controller = TextEditingController(text: 'hello world');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 5,
            child: TextField(
              controller: controller,
              focused: true,
              wordBoundaryProvider: testWordBoundaryProvider,
            ),
          ),
        );

        expect(controller.selection.extentOffset, equals(11));

        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.arrowLeft,
          modifiers: ModifierKeys(shift: true),
        ));

        expect(controller.selection.isCollapsed, isFalse);
        expect(controller.selection.extentOffset, equals(10));
      });
    });
  });
}
