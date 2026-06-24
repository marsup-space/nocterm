// Tests for macOS Terminal.app's "Use Option as Meta" mode, which sends
// `ESC f` / `ESC b` / `ESC d` for Option+→ / Option+← / Option+Delete
// instead of a proper CSI modifier sequence. The parser must translate
// these into Alt+ArrowRight / Alt+ArrowLeft / Alt+Delete so the
// TextField's word-navigation handler can pick them up; otherwise the
// user ends up with literal 'f' / 'b' / 'd' being inserted into the
// input on a default-configured macOS terminal.

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
  group('macOS Option-as-Meta word navigation', () {
    test('ESC f (Option+→) becomes Alt+ArrowRight', () {
      final parser = InputParser();
      final event = _parseSingle(parser, [0x1B, 0x66]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.arrowRight));
      expect(event.isAltPressed, isTrue);
      expect(event.isControlPressed, isFalse);
      expect(event.isShiftPressed, isFalse);
      expect(event.character, isNull,
          reason: 'must not also carry the literal "f" character');
    });

    test('ESC b (Option+←) becomes Alt+ArrowLeft', () {
      final parser = InputParser();
      final event = _parseSingle(parser, [0x1B, 0x62]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.arrowLeft));
      expect(event.isAltPressed, isTrue);
      expect(event.isControlPressed, isFalse);
      expect(event.isShiftPressed, isFalse);
      expect(event.character, isNull);
    });

    test('ESC d (Option+Delete) becomes Alt+Delete', () {
      final parser = InputParser();
      final event = _parseSingle(parser, [0x1B, 0x64]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.delete));
      expect(event.isAltPressed, isTrue);
      expect(event.isControlPressed, isFalse);
      expect(event.isShiftPressed, isFalse);
      expect(event.character, isNull);
    });

    test('ESC 0x7F (Option+Backspace) becomes Alt+Backspace', () {
      // Regression guard: this mapping predates the f/b/d addition and
      // must keep working (it's what powers "delete word backward" on
      // the default macOS terminal).
      final parser = InputParser();
      final event = _parseSingle(parser, [0x1B, 0x7F]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.backspace));
      expect(event.isAltPressed, isTrue);
      expect(event.character, isNull);
    });

    test('other Alt+letter sequences still insert the literal letter', () {
      // The f/b/d mapping is intentionally narrow — every other
      // Option+letter combo on a default-configured terminal still
      // arrives as `ESC <letter>` and must continue to insert the
      // literal character with Alt held. This is the documented
      // tradeoff in input_parser.dart.
      for (final code in [0x61, 0x63, 0x65, 0x67, 0x68, 0x69, 0x6A]) {
        // skip the three mapped ones
        if (code == 0x66 || code == 0x62 || code == 0x64) continue;
        final parser = InputParser();
        final event = _parseSingle(parser, [0x1B, code]);
        expect(event, isNotNull, reason: 'code=0x${code.toRadixString(16)}');
        final ch = String.fromCharCode(code);
        expect(event!.logicalKey, equals(LogicalKey.fromCharacter(ch)));
        expect(event.character, equals(ch));
        expect(event.isAltPressed, isTrue);
      }
    });

    test('a real CSI modifier sequence is unaffected', () {
      // Terminals that DO send a proper CSI modifier sequence (iTerm2
      // with modifyOtherKeys, kitty protocol, etc.) must continue to
      // route through the existing CSI parser — `\x1b[1;3C` should
      // still arrive as Alt+ArrowRight via the normal CSI path, not
      // get double-translated.
      final parser = InputParser();
      final event = _parseSingle(parser, [0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x43]);
      expect(event, isNotNull);
      expect(event!.logicalKey, equals(LogicalKey.arrowRight));
      expect(event.isAltPressed, isTrue);
      expect(event.character, isNull);
    });
  });
}