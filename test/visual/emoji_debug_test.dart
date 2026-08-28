import 'package:nocterm/src/utils/unicode_width.dart';
import 'package:test/test.dart';

void main() {
  group('Emoji Variation Selector (FE0F) Width', () {
    test('symbols with FE0F should have width 2', () {
      // Symbols with emoji variation selector (U+FE0F) should render as emoji (width 2)
      final symbolsWithFE0F = {
        "⚠️": "Warning sign",
        "❤️": "Red heart",
        "☎️": "Telephone",
        "✔️": "Check mark",
        "☢️": "Radioactive",
        "☣️": "Biohazard",
        "♻️": "Recycling",
        "⚙️": "Gear",
        "⚔️": "Crossed swords",
        "⚖️": "Balance scale",
        "⚗️": "Alembic",
        "⚛️": "Atom symbol",
        "⚜️": "Fleur-de-lis",
        "☀️": "Sun",
        "☁️": "Cloud",
      };

      for (final entry in symbolsWithFE0F.entries) {
        final symbol = entry.key;
        final name = entry.value;
        final width = UnicodeWidth.stringWidth(symbol);

        expect(
          width,
          equals(2),
          reason: '$name ($symbol) with FE0F should have width 2, got $width',
        );
      }
    });

    test('same symbols without FE0F should have width 1', () {
      // Text symbols without emoji variation selector should have width 1
      final textSymbols = {
        "⚠": "Warning sign",
        "❤": "Heart",
        "☎": "Telephone",
        "✔": "Check mark",
        "☢": "Radioactive",
        "☣": "Biohazard",
        "♻": "Recycling",
        "⚙": "Gear",
        "⚔": "Crossed swords",
        "⚖": "Balance scale",
        "⚗": "Alembic",
        "⚛": "Atom symbol",
        "⚜": "Fleur-de-lis",
      };

      for (final entry in textSymbols.entries) {
        final symbol = entry.key;
        final name = entry.value;
        final width = UnicodeWidth.stringWidth(symbol);

        expect(
          width,
          equals(1),
          reason:
              '$name ($symbol) without FE0F should have width 1, got $width',
        );
      }
    });

    test('emoji presentation by default vs text presentation by default', () {
      // Per UTS#51 emoji-data.txt, ⭐ ✨ ⚡ ⛔ ⬛ ⬜ ✅ ❌ are all
      // Emoji_Presentation=Yes — they render as 2-cell emoji even bare
      // (no FE0F needed). Terminals (iTerm2, Ghostty, kitty) follow
      // this; mis-measuring them as 1 cell breaks table/box alignment.
      final emojiByDefaultBmp = {
        "⭐": "Star",
        "✨": "Sparkles",
        "⚡": "High voltage",
        "⛔": "No entry",
        "⬛": "Black square",
        "⬜": "White square",
        "✅": "Check mark button",
        "❌": "Cross mark",
        "❗": "Exclamation mark",
        "❓": "Question mark",
      };

      for (final entry in emojiByDefaultBmp.entries) {
        final symbol = entry.key;
        final name = entry.value;
        expect(
          UnicodeWidth.stringWidth(symbol),
          equals(2),
          reason:
              '$name ($symbol) is Emoji_Presentation=Yes → width 2 even bare',
        );
        // FE0F is a no-op here — already emoji presentation.
        expect(
          UnicodeWidth.stringWidth(symbol + '\uFE0F'),
          equals(2),
          reason: '$name ($symbol) with FE0F stays width 2',
        );
      }

      // Text-presentation-by-default characters (Emoji=Yes but
      // Emoji_Presentation=No) ARE 1 cell bare and need FE0F to go
      // emoji — the sun/cloud family plus the warning/heart set.
      final textByDefault = {
        "☀": "Sun",
        "☁": "Cloud",
        "☂": "Umbrella",
        "☃": "Snowman",
        "⚠": "Warning sign",
        "❤": "Heart",
        "✔": "Heavy check mark",
      };
      for (final entry in textByDefault.entries) {
        final symbol = entry.key;
        final name = entry.value;
        expect(
          UnicodeWidth.stringWidth(symbol),
          equals(1),
          reason: '$name ($symbol) is text-presentation by default → width 1',
        );
        expect(
          UnicodeWidth.stringWidth(symbol + '\uFE0F'),
          equals(2),
          reason: '$name ($symbol) with FE0F upgrades to width 2',
        );
      }

      // SMP emoji are Emoji_Presentation=Yes as well.
      final emojiByDefaultSmp = {
        "🔶": "Orange diamond",
        "🔷": "Blue diamond",
      };
      for (final entry in emojiByDefaultSmp.entries) {
        final symbol = entry.key;
        final name = entry.value;
        expect(
          UnicodeWidth.stringWidth(symbol),
          equals(2),
          reason: '$name ($symbol) is emoji presentation by default',
        );
      }
    });

    test('FE0F detection in grapheme', () {
      // Verify FE0F is correctly identified
      final withFE0F = "⚠️";
      final withoutFE0F = "⚠";

      expect(withFE0F.runes.contains(0xFE0F), isTrue);
      expect(withoutFE0F.runes.contains(0xFE0F), isFalse);

      expect(UnicodeWidth.graphemeWidth(withFE0F), equals(2));
      expect(UnicodeWidth.graphemeWidth(withoutFE0F), equals(1));
    });
  });
}
