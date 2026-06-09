import 'package:nocterm/src/components/text_field/cursor_movement.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CursorMovement', () {
    test('handles Unicode characters correctly in horizontal movement', () {
      final text = 'Hello 世界 🌍';

      // Move right from start
      var offset = CursorMovement.moveCursorHorizontally(
        text: text,
        currentOffset: 0,
        direction: 1,
      );
      expect(offset, 1); // H -> e

      // Move to emoji
      offset = CursorMovement.moveCursorHorizontally(
        text: text,
        currentOffset: 10,
        direction: 1,
      );
      expect(offset,
          11); // Space before emoji -> emoji (emoji is 1 grapheme cluster)
    });

    test('handles wrapped lines in vertical movement', () {
      final text = 'This is a long line that should wrap when displayed';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: true,
          maxWidth: 20, // Force wrapping
        ),
      );

      // Start at position 10 ('l' in 'long')
      final newOffset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 10,
        direction: 1, // Move down
        targetVisualColumn: 10,
      );

      // Should move to the next wrapped line
      expect(newOffset, greaterThan(10));
    });

    test('maintains visual column when moving vertically', () {
      final text = 'Line one\nA much longer second line\nShort';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Start at position 20 (somewhere in second line)
      var offset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20,
        direction: -1, // Move up
        targetVisualColumn: 11,
      );

      // Should try to maintain column position
      expect(offset, lessThan(20));
      expect(offset, lessThanOrEqualTo(8)); // End of first line
    });

    test('moves by word correctly', () {
      final text = 'Hello world, this is a test!';

      // Move forward by word from start
      var offset = CursorMovement.moveCursorByWord(
        text: text,
        currentOffset: 0,
        direction: 1,
      );
      expect(offset, 6); // After 'Hello '

      // Move backward by word
      offset = CursorMovement.moveCursorByWord(
        text: text,
        currentOffset: 12,
        direction: -1,
      );
      expect(offset, 6); // Start of 'world'
    });

    test('finds correct cursor position in laid out text', () {
      final text = 'First line\nSecond line\nThird';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Position at start of second line
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 11, // Just after '\n'
      );

      // The layout engine removes newlines from the lines, so we need to track them
      expect(pos.line, 1); // Second line (0-indexed)
      expect(pos.column, 0); // Start of line
      expect(pos.visualColumn, 0);
    });

    test('handles double-width characters in cursor position', () {
      final text = '你好世界'; // Chinese characters (double-width)
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Position after first character
      // Note: In Dart strings, '你' is 1 character but takes 2 visual columns
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 1, // After '你' (1 character in Dart string)
      );

      expect(pos.visualColumn, 2); // Double-width character
    });

    test('handles line start and end movement', () {
      final text = 'First line\nSecond longer line\nThird';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Move to line start from middle of second line
      var offset = CursorMovement.moveCursorToLineStart(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20, // Somewhere in second line
      );
      expect(offset, 11); // Start of second line

      // Move to line end
      offset = CursorMovement.moveCursorToLineEnd(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20,
      );
      expect(offset, 29); // End of second line
    });

    test('handles multiple consecutive newlines in cursor position', () {
      // "hello\n\nworld" has two newlines: one between "hello" and "",
      // another between "" and "world"
      final text = 'hello\n\nworld';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Layout produces: ["hello", "", "world"]
      expect(layoutResult.lines.length, 3);
      expect(layoutResult.lines[0], 'hello');
      expect(layoutResult.lines[1], '');
      expect(layoutResult.lines[2], 'world');

      // Cursor at start of the empty line (offset 6, after first \n)
      final posEmptyLine = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 6,
      );
      expect(posEmptyLine.line, 1); // Empty line
      expect(posEmptyLine.column, 0);
      expect(posEmptyLine.visualColumn, 0);

      // Cursor at start of "world" (offset 7, after second \n)
      final posWorldStart = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 7,
      );
      expect(posWorldStart.line, 2); // "world" line
      expect(posWorldStart.column, 0);
      expect(posWorldStart.visualColumn, 0);

      // Cursor at the 'r' in "world" (offset 8)
      final posR = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 8,
      );
      expect(posR.line, 2);
      expect(posR.column, 1);
      expect(posR.visualColumn, 1);
    });

    test('handles vertical movement across multiple consecutive newlines', () {
      final text = 'hello\n\nworld';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Start at offset 2 (the 'l' in "hello"), move down
      // Should land on the empty line (line 1)
      var offset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 2,
        direction: 1, // Move down
        targetVisualColumn: 2,
      );
      // Empty line has column 0 only, so cursor should be at offset 6 (start of empty line)
      expect(offset, 6);

      // Move down again from the empty line to "world"
      offset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 6,
        direction: 1, // Move down
        targetVisualColumn: 0,
      );
      // Should be at offset 7 (start of "world")
      expect(offset, 7);
    });
  });
}
