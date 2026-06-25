// Tests that kitty keyboard protocol sequences for Cmd+A/C/V/X (Meta
// modifier on macOS) still parse correctly after PR #90's
// backward-scanning 4-part form for IME associated text. The
// backward scan was added to disambiguate the 'u' terminator from
// raw 'u' bytes that may appear un-percent-encoded inside the
// associated text. Make sure it doesn't regress 1–3 part parses
// for plain Meta+A/C/V/X.

import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/keyboard_event.dart';
import 'package:nocterm/src/keyboard/logical_key.dart';
import 'package:test/test.dart';

KeyboardEvent? _parseSingle(InputParser parser, List<int> bytes) {
  parser.addBytes(bytes);
  while (true) {
    final event = parser.parseNext();
    if (event == null) return null;
    if (event is KeyboardInputEvent) return event.event;
  }
}

void main() {
  group('kitty protocol Meta+A/C/V/X (macOS Cmd+*)', () {
    test('Cmd+C (\\x1b[99;9u) is Meta+C with logicalKey=keyC', () {
      final parser = InputParser();
      final event = _parseSingle(parser,
          [0x1B, 0x5B, 0x39, 0x39, 0x3B, 0x39, 0x75]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyC));
      expect(event.isMetaPressed, isTrue);
      expect(event.isControlPressed, isFalse);
      expect(event.isShiftPressed, isFalse);
      expect(event.isAltPressed, isFalse);
      expect(event.character, equals('c'));
    });

    test('Cmd+A (\\x1b[97;9u) is Meta+A with logicalKey=keyA', () {
      final parser = InputParser();
      final event = _parseSingle(parser,
          [0x1B, 0x5B, 0x39, 0x37, 0x3B, 0x39, 0x75]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyA));
      expect(event.isMetaPressed, isTrue);
      expect(event.character, equals('a'));
    });

    test('Cmd+V (\\x1b[118;9u) is Meta+V with logicalKey=keyV', () {
      final parser = InputParser();
      final event = _parseSingle(parser,
          [0x1B, 0x5B, 0x31, 0x31, 0x38, 0x3B, 0x39, 0x75]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyV));
      expect(event.isMetaPressed, isTrue);
      expect(event.character, equals('v'));
    });

    test('Cmd+X (\\x1b[120;9u) is Meta+X with logicalKey=keyX', () {
      final parser = InputParser();
      final event = _parseSingle(parser,
          [0x1B, 0x5B, 0x31, 0x32, 0x30, 0x3B, 0x39, 0x75]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyX));
      expect(event.isMetaPressed, isTrue);
      expect(event.character, equals('x'));
    });

    test('Ctrl+C (\\x1b[99;5u) is still Ctrl+C', () {
      // Regression guard: the original Ctrl+C behavior (let the event
      // bubble up to the app for quit handling) must still work.
      final parser = InputParser();
      final event = _parseSingle(parser,
          [0x1B, 0x5B, 0x39, 0x39, 0x3B, 0x35, 0x75]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyC));
      expect(event.isControlPressed, isTrue);
      expect(event.isMetaPressed, isFalse);
    });

    test('4-part IME commit with literal "u" in associated text', () {
      // Exercises the backward-scan terminator disambiguation that
      // PR #90 added. "menu" contains a literal 'u' which is
      // unreserved in URL percent-encoding — the parser must NOT
      // pick that 'u' as the terminator.
      // \x1b[99;1;1;menu u  →  codepoint='c' (99), no modifiers
      //                       (modifier=1 is the kitty-spec "no
      //                       modifier" base value), base layout 1,
      //                       associated text "menu"
      final parser = InputParser();
      final event = _parseSingle(parser, <int>[
        0x1B, 0x5B, 0x39, 0x39, 0x3B, 0x31, 0x3B, 0x31,
        0x3B, 0x6D, 0x65, 0x6E, 0x75, 0x75,
      ]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.keyC));
      expect(event.character, equals('menu'),
          reason: 'associated text should be percent-decoded verbatim '
              'when "u" appears inside it');
      expect(event.isControlPressed, isFalse);
      expect(event.isMetaPressed, isFalse);
    });
  });
}