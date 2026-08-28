// Exhaustive BMP emoji width test, generated against UTS#51 emoji-data.txt
// 15.1. Every codepoint with Emoji=Yes below U+1F000 is asserted against the
// width its Emoji_Presentation property dictates:
//   Emoji_Presentation=Yes → 2 columns (renders as emoji even bare)
//   Emoji_Presentation=No  → 1 column  (text glyph bare; emoji only with FE0F)
//
// The expectation map below is machine-generated from
// https://unicode.org/Public/15.1.0/ucd/emoji/emoji-data.txt — do not hand-edit
// individual entries; regenerate if the Unicode version is bumped.

import 'package:nocterm/src/utils/unicode_width.dart';
import 'package:test/test.dart';

void main() {
  group('BMP emoji width — exhaustive vs emoji-data.txt 15.1', () {
    const bmpEmojiExpected = <int, int>{
      0x0023: 1,
      0x002A: 1,
      0x0030: 1,
      0x0031: 1,
      0x0032: 1,
      0x0033: 1,
      0x0034: 1,
      0x0035: 1,
      0x0036: 1,
      0x0037: 1,
      0x0038: 1,
      0x0039: 1,
      0x00A9: 1,
      0x00AE: 1,
      0x203C: 1,
      0x2049: 1,
      0x2122: 1,
      0x2139: 1,
      0x2194: 1,
      0x2195: 1,
      0x2196: 1,
      0x2197: 1,
      0x2198: 1,
      0x2199: 1,
      0x21A9: 1,
      0x21AA: 1,
      0x231A: 2,
      0x231B: 2,
      0x2328: 1,
      0x23CF: 1,
      0x23E9: 2,
      0x23EA: 2,
      0x23EB: 2,
      0x23EC: 2,
      0x23ED: 1,
      0x23EE: 1,
      0x23EF: 1,
      0x23F0: 2,
      0x23F1: 1,
      0x23F2: 1,
      0x23F3: 2,
      0x23F8: 1,
      0x23F9: 1,
      0x23FA: 1,
      0x24C2: 1,
      0x25AA: 1,
      0x25AB: 1,
      0x25B6: 1,
      0x25C0: 1,
      0x25FB: 1,
      0x25FC: 1,
      0x25FD: 2,
      0x25FE: 2,
      0x2600: 1,
      0x2601: 1,
      0x2602: 1,
      0x2603: 1,
      0x2604: 1,
      0x260E: 1,
      0x2611: 1,
      0x2614: 2,
      0x2615: 2,
      0x2618: 1,
      0x261D: 1,
      0x2620: 1,
      0x2622: 1,
      0x2623: 1,
      0x2626: 1,
      0x262A: 1,
      0x262E: 1,
      0x262F: 1,
      0x2638: 1,
      0x2639: 1,
      0x263A: 1,
      0x2640: 1,
      0x2642: 1,
      0x2648: 2,
      0x2649: 2,
      0x264A: 2,
      0x264B: 2,
      0x264C: 2,
      0x264D: 2,
      0x264E: 2,
      0x264F: 2,
      0x2650: 2,
      0x2651: 2,
      0x2652: 2,
      0x2653: 2,
      0x265F: 1,
      0x2660: 1,
      0x2663: 1,
      0x2665: 1,
      0x2666: 1,
      0x2668: 1,
      0x267B: 1,
      0x267E: 1,
      0x267F: 2,
      0x2692: 1,
      0x2693: 2,
      0x2694: 1,
      0x2695: 1,
      0x2696: 1,
      0x2697: 1,
      0x2699: 1,
      0x269B: 1,
      0x269C: 1,
      0x26A0: 1,
      0x26A1: 2,
      0x26A7: 1,
      0x26AA: 2,
      0x26AB: 2,
      0x26B0: 1,
      0x26B1: 1,
      0x26BD: 2,
      0x26BE: 2,
      0x26C4: 2,
      0x26C5: 2,
      0x26C8: 1,
      0x26CE: 2,
      0x26CF: 1,
      0x26D1: 1,
      0x26D3: 1,
      0x26D4: 2,
      0x26E9: 1,
      0x26EA: 2,
      0x26F0: 1,
      0x26F1: 1,
      0x26F2: 2,
      0x26F3: 2,
      0x26F4: 1,
      0x26F5: 2,
      0x26F7: 1,
      0x26F8: 1,
      0x26F9: 1,
      0x26FA: 2,
      0x26FD: 2,
      0x2702: 1,
      0x2705: 2,
      0x2708: 1,
      0x2709: 1,
      0x270A: 2,
      0x270B: 2,
      0x270C: 1,
      0x270D: 1,
      0x270F: 1,
      0x2712: 1,
      0x2714: 1,
      0x2716: 1,
      0x271D: 1,
      0x2721: 1,
      0x2728: 2,
      0x2733: 1,
      0x2734: 1,
      0x2744: 1,
      0x2747: 1,
      0x274C: 2,
      0x274E: 2,
      0x2753: 2,
      0x2754: 2,
      0x2755: 2,
      0x2757: 2,
      0x2763: 1,
      0x2764: 1,
      0x2795: 2,
      0x2796: 2,
      0x2797: 2,
      0x27A1: 1,
      0x27B0: 2,
      0x27BF: 2,
      0x2934: 1,
      0x2935: 1,
      0x2B05: 1,
      0x2B06: 1,
      0x2B07: 1,
      0x2B1B: 2,
      0x2B1C: 2,
      0x2B50: 2,
      0x2B55: 2,
      0x3030: 1,
      0x303D: 1,
      0x3297: 1,
      0x3299: 1,
    };

    // U+3030 (〰 wavy dash) is a deliberate, documented divergence from
    // emoji-data.txt: it is Emoji_Presentation=No (would be width 1) but
    // it is ALSO genuine fullwidth CJK punctuation, and the CJK
    // punctuation suite depends on its wide EAW (width 2). We keep the
    // wide measurement — in practice 〰 appears as CJK punctuation, not
    // as an emoji, so the wide width is the useful one.
    const knownDivergences = {0x3030};

    test('every BMP emoji codepoint matches its Emoji_Presentation width', () {
      final failures = <String>[];

      for (final entry in bmpEmojiExpected.entries) {
        final cp = entry.key;
        final expected = entry.value;
        final actual = UnicodeWidth.runeWidth(cp);
        if (knownDivergences.contains(cp)) {
          // Document the divergence: assert it stays wide, not the
          // emoji-data value.
          expect(actual, equals(2),
              reason: 'U+3030 〰 intentionally stays wide (CJK punctuation)');
          continue;
        }
        if (actual != expected) {
          final pres = expected == 2 ? 'Yes' : 'No';
          failures.add(
            'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            '(${String.fromCharCode(cp)}): expected $expected '
            '(Emoji_Presentation=$pres), got $actual',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: '${failures.length} codepoints disagree with '
            'emoji-data.txt:\n  ${failures.join('\n  ')}',
      );
    });

    test('text-presentation codepoints upgrade to width 2 with FE0F', () {
      final failures = <String>[];

      for (final entry in bmpEmojiExpected.entries) {
        if (entry.value != 1) continue; // only text-by-default ones
        if (knownDivergences.contains(entry.key)) continue; // stays wide
        final cp = entry.key;
        final withFe0f = UnicodeWidth.stringWidth(
          '${String.fromCharCode(cp)}\uFE0F',
        );
        if (withFe0f != 2) {
          failures.add(
            'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            '(${String.fromCharCode(cp)})+FE0F: expected 2, got $withFe0f',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: '${failures.length} text-presentation codepoints did not '
            'upgrade with FE0F:\n  ${failures.join('\n  ')}',
      );
    });
  });
}
