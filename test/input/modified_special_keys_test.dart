import 'package:nocterm/src/backend/win32_ansi_stdin.dart';
import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/keyboard_parser.dart';
import 'package:nocterm/src/keyboard/logical_key.dart';
import 'package:test/test.dart';

// Bitmask constants from dwControlKeyState. Values match Windows
// LEFT/RIGHT_CTRL_PRESSED (0x0008 / 0x0004), LEFT/RIGHT_ALT_PRESSED
// (0x0002 / 0x0001) and SHIFT_PRESSED (0x0010).
const int _ctrlPressed = 0x0008;
const int _shiftPressed = 0x0010;
const int _altPressed = 0x0002;

// Virtual key codes for the keys we care about in these tests.
const int _vkBack = 0x08;
const int _vkDelete = 0x2E;
const int _vkInsert = 0x2D;
const int _vkPrior = 0x21; // Page Up
const int _vkNext = 0x22; // Page Down

void main() {
  group('KeyboardParser - modified special keys (ESC [ X ; Y ~)', () {
    late KeyboardParser parser;

    setUp(() {
      parser = KeyboardParser();
    });

    test('Ctrl+Delete: ESC [ 3 ; 5 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x33, 0x3B, 0x35, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.modifiers.ctrl, isTrue);
      expect(event.modifiers.shift, isFalse);
      expect(event.modifiers.alt, isFalse);
    });

    test('Shift+Delete: ESC [ 3 ; 2 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x33, 0x3B, 0x32, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.modifiers.shift, isTrue);
      expect(event.modifiers.ctrl, isFalse);
    });

    test('Ctrl+Shift+Delete: ESC [ 3 ; 6 ~ (modifier 6 = shift+ctrl)', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x33, 0x3B, 0x36, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.modifiers.shift, isTrue);
      expect(event.modifiers.ctrl, isTrue);
    });

    test('Alt+Delete: ESC [ 3 ; 3 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x33, 0x3B, 0x33, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.modifiers.alt, isTrue);
    });

    test('Ctrl+Insert: ESC [ 2 ; 5 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x32, 0x3B, 0x35, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.insert));
      expect(event.modifiers.ctrl, isTrue);
    });

    test('Ctrl+PageUp: ESC [ 5 ; 5 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x35, 0x3B, 0x35, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.pageUp));
      expect(event.modifiers.ctrl, isTrue);
    });

    test('Ctrl+PageDown: ESC [ 6 ; 5 ~', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x36, 0x3B, 0x35, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.pageDown));
      expect(event.modifiers.ctrl, isTrue);
    });

    test('plain Delete ESC [ 3 ~ still works (regression)', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x33, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.modifiers.hasAnyModifier, isFalse);
    });

    test('plain PageUp ESC [ 5 ~ still works (regression)', () {
      final event = parser.parseBytes([0x1B, 0x5B, 0x35, 0x7E]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.pageUp));
      expect(event.modifiers.hasAnyModifier, isFalse);
    });
  });

  group(
      'KeyboardParser - Ctrl+Backspace via xterm modifyOtherKeys (ESC [ 27 ; 5 ; 127 ~)',
      () {
    late KeyboardParser parser;

    setUp(() {
      parser = KeyboardParser();
    });

    test('Ctrl+Backspace: ESC [ 27 ; 5 ; 127 ~', () {
      final event = parser.parseBytes([
        0x1B,
        0x5B,
        0x32,
        0x37,
        0x3B,
        0x35,
        0x3B,
        0x31,
        0x32,
        0x37,
        0x7E,
      ]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.modifiers.ctrl, isTrue);
      expect(event.modifiers.shift, isFalse);
      expect(event.modifiers.alt, isFalse);
    });

    test('Shift+Backspace: ESC [ 27 ; 2 ; 127 ~', () {
      final event = parser.parseBytes([
        0x1B,
        0x5B,
        0x32,
        0x37,
        0x3B,
        0x32,
        0x3B,
        0x31,
        0x32,
        0x37,
        0x7E,
      ]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.modifiers.shift, isTrue);
    });

    test('Alt+Backspace: ESC [ 27 ; 3 ; 127 ~', () {
      final event = parser.parseBytes([
        0x1B,
        0x5B,
        0x32,
        0x37,
        0x3B,
        0x33,
        0x3B,
        0x31,
        0x32,
        0x37,
        0x7E,
      ]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.modifiers.alt, isTrue);
    });

    test('plain Backspace (0x7F) still works (regression)', () {
      final event = parser.parseBytes([0x7F]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.modifiers.hasAnyModifier, isFalse);
    });
  });

  group('InputParser - modified special keys', () {
    late InputParser parser;

    setUp(() {
      parser = InputParser();
    });

    test('Ctrl+Delete via InputParser', () {
      parser.addBytes([0x1B, 0x5B, 0x33, 0x3B, 0x35, 0x7E]);
      final event = parser.parseNext();
      expect(event, isA<KeyboardInputEvent>());
      final keyEvent = (event as KeyboardInputEvent).event;
      expect(keyEvent.logicalKey, equals(LogicalKey.delete));
      expect(keyEvent.modifiers.ctrl, isTrue);
    });

    test('Ctrl+Backspace (modifyOtherKeys) via InputParser', () {
      parser.addBytes(
          [0x1B, 0x5B, 0x32, 0x37, 0x3B, 0x35, 0x3B, 0x31, 0x32, 0x37, 0x7E]);
      final event = parser.parseNext();
      expect(event, isA<KeyboardInputEvent>());
      final keyEvent = (event as KeyboardInputEvent).event;
      expect(keyEvent.logicalKey, equals(LogicalKey.backspace));
      expect(keyEvent.modifiers.ctrl, isTrue);
    });
  });

  group('Win32AnsiStdin.translateSpecialKey', () {
    test('plain Backspace (VK_BACK) → 0x7F', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, 0);
      expect(bytes, equals([0x7F]));
    });

    test('Ctrl+Backspace → modifyOtherKeys ESC [ 27 ; 5 ; 127 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, _ctrlPressed);
      expect(
        bytes,
        equals([
          0x1B,
          0x5B,
          0x32,
          0x37,
          0x3B,
          0x35,
          0x3B,
          0x31,
          0x32,
          0x37,
          0x7E,
        ]),
      );
      // And round-trip through the parser must produce Backspace + Ctrl.
      // Sanity: bytes spell out ESC [ 27 ; 5 ; 127 ~ in ASCII.
      expect(String.fromCharCodes(bytes!), equals('\x1B[27;5;127~'));
    });

    test('Shift+Backspace → modifyOtherKeys ESC [ 27 ; 2 ; 127 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, _shiftPressed);
      expect(String.fromCharCodes(bytes!), equals('\x1B[27;2;127~'));
    });

    test('Alt+Backspace → modifyOtherKeys ESC [ 27 ; 3 ; 127 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, _altPressed);
      expect(String.fromCharCodes(bytes!), equals('\x1B[27;3;127~'));
    });

    test('plain Delete (VK_DELETE) → ESC [ 3 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkDelete, 0);
      expect(bytes, equals([0x1B, 0x5B, 0x33, 0x7E]));
    });

    test('Ctrl+Delete → ESC [ 3 ; 5 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkDelete, _ctrlPressed);
      expect(bytes, equals([0x1B, 0x5B, 0x33, 0x3B, 0x35, 0x7E]));
    });

    test('Shift+Delete → ESC [ 3 ; 2 ~', () {
      final bytes =
          Win32AnsiStdin.translateSpecialKey(_vkDelete, _shiftPressed);
      expect(bytes, equals([0x1B, 0x5B, 0x33, 0x3B, 0x32, 0x7E]));
    });

    test('Ctrl+Insert → ESC [ 2 ; 5 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkInsert, _ctrlPressed);
      expect(bytes, equals([0x1B, 0x5B, 0x32, 0x3B, 0x35, 0x7E]));
    });

    test('Ctrl+PageUp → ESC [ 5 ; 5 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkPrior, _ctrlPressed);
      expect(bytes, equals([0x1B, 0x5B, 0x35, 0x3B, 0x35, 0x7E]));
    });

    test('Ctrl+PageDown → ESC [ 6 ; 5 ~', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkNext, _ctrlPressed);
      expect(bytes, equals([0x1B, 0x5B, 0x36, 0x3B, 0x35, 0x7E]));
    });

    test('unknown key returns null (falls through to printable handling)', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(0xFF, 0);
      expect(bytes, isNull);
    });
  });

  group('End-to-end: Ctrl+Backspace byte sequence parses to backspace+ctrl',
      () {
    test('win32 backend + KeyboardParser', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, _ctrlPressed)!;
      final parser = KeyboardParser();
      final event = parser.parseBytes(bytes);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.modifiers.ctrl, isTrue);
      expect(event.isControlPressed, isTrue);
    });

    test('win32 backend + InputParser', () {
      final bytes = Win32AnsiStdin.translateSpecialKey(_vkBack, _ctrlPressed)!;
      final parser = InputParser();
      parser.addBytes(bytes);
      final event = parser.parseNext();
      expect(event, isA<KeyboardInputEvent>());
      final keyEvent = (event as KeyboardInputEvent).event;
      expect(keyEvent.logicalKey, equals(LogicalKey.backspace));
      expect(keyEvent.modifiers.ctrl, isTrue);
    });
  });
}
