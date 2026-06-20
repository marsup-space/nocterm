import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/mouse_event.dart';
import 'package:nocterm/src/keyboard/mouse_parser.dart';
import 'package:test/test.dart';

void main() {
  group('MouseParser', () {
    test('parses SGR wheel events with modifier bits as wheel buttons', () {
      final cases = <int, MouseButton>{
        64: MouseButton.wheelUp,
        65: MouseButton.wheelDown,
        66: MouseButton.wheelLeft,
        67: MouseButton.wheelRight,
        68: MouseButton.wheelUp,
        69: MouseButton.wheelDown,
        70: MouseButton.wheelLeft,
        71: MouseButton.wheelRight,
        96: MouseButton.wheelUp,
        97: MouseButton.wheelDown,
      };

      for (final entry in cases.entries) {
        final event = MouseParser.parseSGR(
          '\x1b[<${entry.key};10;5M'.codeUnits,
        );

        expect(event, isNotNull, reason: 'button code ${entry.key}');
        expect(event!.button, entry.value, reason: 'button code ${entry.key}');
        expect(event.isWheel, isTrue, reason: 'button code ${entry.key}');
        expect(event.isMotion, isFalse, reason: 'button code ${entry.key}');
      }
    });

    test('InputParser does not turn modified wheel into left press', () {
      final parser = InputParser();
      parser.addBytes('\x1b[<68;10;5M'.codeUnits);

      final inputEvent = parser.parseNext();

      expect(inputEvent, isA<MouseInputEvent>());
      final mouseEvent = (inputEvent as MouseInputEvent).event;
      expect(mouseEvent.button, MouseButton.wheelUp);
      expect(mouseEvent.isWheel, isTrue);
      expect(mouseEvent.button, isNot(MouseButton.left));
    });
  });
}
