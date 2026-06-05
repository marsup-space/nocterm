import 'package:nocterm/src/utils/unicode_width.dart';
import 'package:test/test.dart';

void main() {
  group('Unicode Width Calculation', () {
    test('sparkles emoji width', () {
      final sparkles = '✨';
      final sparklesCode = sparkles.runes.first;

      // ✨ is U+2728
      expect(sparklesCode, equals(0x2728));

      // Should have width of 2 (double-width)
      expect(UnicodeWidth.runeWidth(sparklesCode), equals(2));

      // String width should also be 2
      expect(UnicodeWidth.stringWidth(sparkles), equals(2));
    });

    test('common emoji widths', () {
      final emojis = {
        '✨': 2, // Sparkles
        '⭐': 2, // Star
        '💫': 2, // Dizzy
        '🌟': 2, // Glowing star
        '☀': 2, // Sun
        '☁': 2, // Cloud
        '🚀': 2, // Rocket
        '💻': 2, // Computer
        '🎯': 2, // Target
        '🔥': 2, // Fire
      };

      emojis.forEach((emoji, expectedWidth) {
        expect(
          UnicodeWidth.stringWidth(emoji),
          equals(expectedWidth),
          reason: 'Emoji $emoji should have width $expectedWidth',
        );
      });
    });

    test('ASCII character widths', () {
      final asciiChars = {
        'A': 1,
        'B': 1,
        '1': 1,
        '!': 1,
        ' ': 1,
        '\t': 1, // Tab counts as 1
      };

      asciiChars.forEach((char, expectedWidth) {
        expect(
          UnicodeWidth.stringWidth(char),
          equals(expectedWidth),
          reason: 'ASCII char "$char" should have width $expectedWidth',
        );
      });
    });

    test('CJK character widths', () {
      final cjkChars = {
        '中': 2, // Chinese
        '日': 2, // Japanese
        '한': 2, // Korean
        '文': 2, // Chinese/Japanese
      };

      cjkChars.forEach((char, expectedWidth) {
        expect(
          UnicodeWidth.stringWidth(char),
          equals(expectedWidth),
          reason: 'CJK char "$char" should have width $expectedWidth',
        );
      });
    });

    test('CJK punctuation widths', () {
      // CJK Symbols and Punctuation (U+3000-0x303F) and other fullwidth
      // forms. These were previously reported as width 1, which caused
      // the cell after them to be overwritten by the next character.
      final punctuation = {
        '《': 2, // U+300B Left double angle bracket
        '》': 2, // U+300B Right double angle bracket
        '「': 2, // U+300C Left corner bracket
        '」': 2, // U+300D Right corner bracket
        '『': 2, // U+300E Left white corner bracket
        '』': 2, // U+300F Right white corner bracket
        '〈': 2, // U+3008 Left angle bracket
        '〉': 2, // U+3009 Right angle bracket
        '、': 2, // U+3001 Ideographic comma
        '。': 2, // U+3002 Ideographic full stop
        '【': 2, // U+3010 Left black lenticular bracket
        '】': 2, // U+3011 Right black lenticular bracket
        '　': 2, // U+3000 Ideographic space
      };

      punctuation.forEach((char, expectedWidth) {
        expect(
          UnicodeWidth.runeWidth(char.runes.first),
          equals(expectedWidth),
          reason:
              'CJK punctuation "$char" (U+${char.runes.first.toRadixString(16).toUpperCase()}) should have width $expectedWidth',
        );
      });
    });

    test('CJK punctuation in composed string widths', () {
      // End-to-end check: bracket-wrapped CJK strings should be 8 columns
      // (4 wide chars × 2). Before the CJK Symbols and Punctuation range
      // was added, the brackets reported width 1 each, so these strings
      // measured 6 (4 ideograph cells + 2 single-cell brackets) but
      // actually occupy 8 cells — the next character after the closing
      // bracket would overwrite the trailing cell of the last ideograph.
      expect(UnicodeWidth.stringWidth('《标题》'), equals(8),
          reason: '《标题》 = 4 wide chars × 2 = 8 columns');
      expect(UnicodeWidth.stringWidth('【你好】'), equals(8),
          reason: '【你好】 = 4 wide chars × 2 = 8 columns');
      expect(UnicodeWidth.stringWidth('「中文」'), equals(8),
          reason: '「中文」 = 4 wide chars × 2 = 8 columns');
    });

    test('CJK punctuation full coverage', () {
      // Exhaustive list of Chinese punctuation characters and the ranges
      // that contain them. Each entry is a (character, codepoint) pair.
      // All of these should report width 2.
      final cases = <String, int>{
        // CJK Symbols and Punctuation (U+3000-0x303F)
        '　': 0x3000, // Ideographic space
        '、': 0x3001, // Ideographic comma
        '。': 0x3002, // Ideographic full stop
        '〃': 0x3003, // Ditto mark
        '々': 0x3005, // Ideographic iteration mark
        '〆': 0x3006, // Ideographic closing mark
        '〇': 0x3007, // Ideographic number zero
        '〈': 0x3008, // Left angle bracket
        '〉': 0x3009, // Right angle bracket
        '《': 0x300A, // Left double angle bracket
        '》': 0x300B, // Right double angle bracket
        '「': 0x300C, // Left corner bracket
        '」': 0x300D, // Right corner bracket
        '『': 0x300E, // Left white corner bracket
        '』': 0x300F, // Right white corner bracket
        '【': 0x3010, // Left black lenticular bracket
        '】': 0x3011, // Right black lenticular bracket
        '〒': 0x3012, // Postal mark
        '〓': 0x3013, // Geta mark
        '〔': 0x3014, // Left tortoise shell bracket
        '〕': 0x3015, // Right tortoise shell bracket
        '〖': 0x3016, // Left white lenticular bracket
        '〗': 0x3017, // Right white lenticular bracket
        '〘': 0x3018, // Left white square bracket
        '〙': 0x3019, // Right white square bracket
        '〚': 0x301A, // Left white double square bracket
        '〛': 0x301B, // Right white double square bracket
        '〜': 0x301C, // Wave dash
        '〝': 0x301D, // Reversed double prime
        '〞': 0x301E, // Low double prime
        '〟': 0x301F, // Low kana double prime
        '〰': 0x3030, // Wavy dash

        // General Punctuation, CJK-relevant sub-range (U+2010-0x205F).
        // Treated as wide to match CJK font fallback behaviour.
        '—': 0x2014, // Em dash
        '‛': 0x201B, // Single high-reversed-9 quotation
        '′': 0x2032, // Prime
        '″': 0x2033, // Double prime
        '‹': 0x2039, // Single left-pointing angle quotation
        '›': 0x203A, // Single right-pointing angle quotation
        '※': 0x203B, // Reference mark
        '‼': 0x203C, // Double exclamation mark
        '‽': 0x203D, // Interrobang
        '⁇': 0x2047, // Double question reversal
        '⁈': 0x2048, // Question exclamation mark
        '⁉': 0x2049, // Exclamation question mark
        '…': 0x2026, // Horizontal ellipsis
        '“': 0x201C, // Left double quotation mark
        '”': 0x201D, // Right double quotation mark
        '‘': 0x2018, // Left single quotation mark
        '’': 0x2019, // Right single quotation mark

        // Small Form Variants (U+FE50-0xFE6F).
        '﹏': 0xFE4F, // Bottom of box (sits at top of Small Form Variants)
        '﹑': 0xFE51, // Small ideographic comma
        '﹒': 0xFE52, // Small full stop

        // Vertical Forms (U+FE10-0xFE1F) and CJK Compatibility Forms
        // (U+FE30-0xFE4F) are already in the wide set; spot-check a few.
        '︴': 0xFE34, // Presentation form for vertical wavy low line
        '︵': 0xFE35, // Presentation form for vertical left parenthesis
        '︶': 0xFE36, // Presentation form for vertical right parenthesis

        // Ideographic Description Characters (U+2FF0-0x2FFB).
        '⿰': 0x2FF0, // Ideographic description character (left to right)
        '⿱': 0x2FF1, // Ideographic description character (top to bottom)
      };

      for (final entry in cases.entries) {
        final ch = entry.key;
        final code = entry.value;
        expect(
          UnicodeWidth.runeWidth(code),
          equals(2),
          reason:
              'CJK punctuation "$ch" (U+${code.toRadixString(16).toUpperCase()}) should be wide (2 columns)',
        );
      }
    });

    test('mixed string widths', () {
      final testCases = {
        'Hello World': 11, // All ASCII
        '✨ Features:': 12, // Emoji (2) + space (1) + ASCII (9)
        'Hello 🌍 World': 14, // ASCII (6) + emoji (2) + ASCII (6)
        'Mixed 💻 text': 13, // ASCII (6) + emoji (2) + ASCII (5)
        '🚀 Rocket': 9, // Emoji (2) + space (1) + ASCII (6)
        'Code 💻 + Coffee ☕ = 🎯': 24, // Complex mix
        '中文text': 8, // CJK (4) + ASCII (4)
      };

      testCases.forEach((text, expectedWidth) {
        expect(
          UnicodeWidth.stringWidth(text),
          equals(expectedWidth),
          reason: 'String "$text" should have width $expectedWidth',
        );
      });
    });

    test('emoji range detection', () {
      // Test specific emoji ranges
      final sparklesCode = 0x2728;

      // Check if it's in the expected range
      expect(sparklesCode >= 0x2700 && sparklesCode <= 0x27BF, isTrue);

      // Other emojis in various ranges
      final testEmojis = [
        ('☀', 0x2600), // Sun - Miscellaneous Symbols
        ('☁', 0x2601), // Cloud - Miscellaneous Symbols
        ('✨', 0x2728), // Sparkles - Dingbats
        ('⭐', 0x2B50), // Star - Miscellaneous Symbols and Arrows
      ];

      for (final (emoji, expectedCode) in testEmojis) {
        final code = emoji.runes.first;
        expect(
          code,
          equals(expectedCode),
          reason:
              'Emoji $emoji should have code U+${expectedCode.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('emoji with Narrow East Asian Width still render as wide', () {
      // 🇨 (U+1F1E8) is a regional indicator. The East Asian Width
      // property classifies it as Narrow (Na), so the bundled
      // unicodeV11.wcwidth table returns 1. The emoji allowlist
      // overrides this to 2 so each flag component occupies two
      // cells. (Note: the *string* width of a flag pair like 🇨🇳 is
      // currently limited by a separate pre-existing issue in
      // graphemeWidth, which sums only the first base rune of a
      // multi-rune grapheme. Tracking that separately.)
      expect(UnicodeWidth.runeWidth(0x1F1E8), equals(2),
          reason: 'Regional indicator 🇨 should be 2 columns');
    });

    test('zero-width characters', () {
      // Some characters have zero width (combining marks, etc.)
      // These should be handled correctly
      final zeroWidthJoiner = '\u200D';
      expect(UnicodeWidth.stringWidth(zeroWidthJoiner), equals(0));
    });

    test('string with combining characters', () {
      // Test combining emoji sequences
      final familyEmoji = '👨‍👩‍👧‍👦'; // Family emoji with ZWJ
      // This is a complex emoji that might render as one glyph
      // but has multiple codepoints
      final width = UnicodeWidth.stringWidth(familyEmoji);
      expect(width, greaterThanOrEqualTo(2)); // Should be at least 2
    });

    test('bullet point character', () {
      final bullet = '•';
      final bulletCode = bullet.runes.first;

      // • is U+2022 (Bullet)
      expect(bulletCode, equals(0x2022));

      // Bullet might be width 1 or 2 depending on terminal
      final width = UnicodeWidth.runeWidth(bulletCode);
      expect(width, anyOf(equals(1), equals(2)));
    });

    test('text alignment calculation', () {
      // Test that we can calculate proper alignment
      final text1 = 'Hello World!'; // 12 chars, 12 width
      final text2 = '✨ Features:'; // 11 chars, 12 width

      expect(text1.length, equals(12));
      expect(UnicodeWidth.stringWidth(text1), equals(12));

      expect(text2.length, equals(11));
      expect(UnicodeWidth.stringWidth(text2), equals(12));

      // Both should center the same in a 45-width container
      final containerWidth = 45;
      final offset1 = (containerWidth - UnicodeWidth.stringWidth(text1)) ~/ 2;
      final offset2 = (containerWidth - UnicodeWidth.stringWidth(text2)) ~/ 2;

      expect(offset1, equals(offset2));
      expect(offset1, equals(16)); // (45 - 12) / 2 = 16.5 -> 16
    });
  });
}
