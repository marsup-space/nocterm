import 'package:characters/characters.dart';

import '../third_party/xterm_pure.dart/src/utils/unicode_v11.dart';

/// Utility class for handling Unicode character display width in terminals
///
/// This implementation handles the display width of Unicode characters,
/// including emojis and other multi-column characters.
class UnicodeWidth {
  /// Calculate the display width of a string in terminal columns
  static int stringWidth(String text) {
    if (text.isEmpty) return 0;

    // Use grapheme clusters for accurate width calculation
    int totalWidth = 0;
    for (final grapheme in text.characters) {
      totalWidth += graphemeWidth(grapheme);
    }

    return totalWidth;
  }

  /// Calculate the display width of a single grapheme cluster
  static int graphemeWidth(String grapheme) {
    if (grapheme.isEmpty) return 0;

    // Handle ZWJ sequences (emoji families, professions, etc.)
    if (grapheme.contains('\u200D')) {
      // ZWJ emoji sequences are typically 2 columns wide
      if (_containsEmoji(grapheme)) {
        return 2;
      }
    }

    // For single-rune graphemes, use existing logic
    final runes = grapheme.runes.toList();
    if (runes.length == 1) {
      return runeWidth(runes[0]);
    }

    // Check for emoji variation selector (FE0F) - requests emoji presentation
    // When present, the grapheme should render as width 2 (emoji style)
    if (runes.contains(0xFE0F)) {
      return 2;
    }

    // For multi-rune graphemes, calculate the base character width
    // and ignore combining marks
    int width = 0;
    bool foundBase = false;

    for (final rune in runes) {
      final runeW = runeWidth(rune);

      // Skip zero-width characters (combining marks, etc.)
      if (runeW == 0) continue;

      // Use the width of the first non-zero-width character as the base
      if (!foundBase && runeW > 0) {
        width = runeW;
        foundBase = true;
      }
    }

    return width;
  }

  /// Check if a string contains emoji characters
  static bool _containsEmoji(String text) {
    for (final rune in text.runes) {
      if (_isEmoji(rune)) return true;
    }
    return false;
  }

  /// Calculate the display width of a single rune/codepoint
  static int runeWidth(int rune) {
    // Tab: at least 1 column.
    if (rune == 0x09) {
      return 1;
    }

    // Zero-width: combining marks, ZWJ, variation selectors. These
    // stack on top of a base character and never advance the cursor.
    if (_isZeroWidth(rune)) {
      return 0;
    }

    // Delegate to the Unicode 11 East Asian Width property table
    // (vendored from xterm_pure at
    // lib/src/third_party/xterm_pure.dart). One lookup covers every
    // CJK ideograph range, kana, hangul, fullwidth/halfwidth forms,
    // CJK Symbols and Punctuation (《, 》, 「, 」, ...), Kangxi
    // radicals, compatibility ideographs, etc. - replacing the
    // hand-maintained range whitelist.
    //
    // East Asian Ambiguous characters (em dash, smart quotes,
    // ellipsis, primes in General Punctuation 0x2010-0x205F) resolve
    // to width 1 here. That matches the default of virtually every
    // terminal; treating them as full-width misaligns ordinary Latin
    // text, which is the common case for this framework.
    final width = unicodeV11.wcwidth(rune);

    // BMP emoji candidates (Misc Symbols ☀⛅, Dingbats ✨❌, and a few
    // neighbours like ⭐⬛ all sit in EAW-Narrow/Ambiguous blocks).
    // For these, presentation decides the width: members with
    // Emoji_Presentation=No render as ONE-cell text glyphs in modern
    // terminals (iTerm2, kitty, WezTerm, xterm.js) unless followed by
    // U+FE0F — the grapheme-level check upgrades those to width 2.
    // Characters with Emoji_Presentation=Yes (⌚⏰⏩◽…) render as emoji
    // by default and stay width 2 even when bare.
    //
    // NB: this OVERRIDES the EAW lookup below only where EAW says 1.
    // CJK-block emoji candidates (〰〽㊗㊙ — U+3030/303D/3297/3299) are
    // also Emoji=Yes + Emoji_Presentation=No, but they are EAW=Wide:
    // the terminal lays them out as full-width glyphs regardless of
    // emoji presentation, so their width stays 2 (the EAW value returned
    // at the bottom of this function). Overriding those to 1 — as a
    // literal reading of emoji-data.txt suggests — desynchronises the
    // measurement from what the terminal actually draws, and every
    // subsequent repaint of the line shifts and leaves stale glyphs
    // behind when scrolling.
    if (rune < 0x1F000 &&
        _isBmpEmoji(rune) &&
        width == 1) {
      return _isEmojiPresentationByDefault(rune) ? 2 : 1;
    }

    // Some characters are visually 2 cells (emoji presentation) but
    // the East Asian Width property classifies them as Narrow or
    // Neutral - regional indicators 0x1F1E6-0x1F1FF, certain
    // Dingbats/Misc Symbols, etc. Layer an emoji allowlist on top
    // to bump them to 2.
    if (width == 1 && _isEmoji(rune)) {
      return 2;
    }

    return width;
  }

  /// Check if a BMP rune is an emoji candidate (Emoji=Yes). These are
  /// the characters whose display width depends on emoji presentation:
  /// bare (text presentation) they are 1 cell; with U+FE0F or default
  /// emoji presentation they are 2 cells.
  static bool _isBmpEmoji(int rune) {
    return _isMiscSymbolEmoji(rune) ||
        _isDingbatEmoji(rune) ||
        rune == 0x231A ||
        rune == 0x231B || // Watch, hourglass
        rune == 0x23E9 ||
        rune == 0x23EA || // Fast forward, rewind
        rune == 0x23EB ||
        rune == 0x23EC || // Up/down arrows
        rune == 0x23F0 ||
        rune == 0x23F3 || // Alarm clock, hourglass flowing
        (rune >= 0x25FB && rune <= 0x25FE) || // Squares
        (rune >= 0x2B1B && rune <= 0x2B1C) || // Black/white squares
        rune == 0x2B50 || // Star
        rune == 0x2B55; // Heavy circle
  }

  /// Check if a BMP emoji candidate has Emoji_Presentation=Yes (per
  /// UTS#51 / emoji-data.txt), i.e. it renders as a width-2 emoji even
  /// without a U+FE0F variation selector.
  ///
  /// The set is the union of the Dingbats / Misc-Symbols emoji
  /// allowlists MINUS the handful that are Emoji=Yes but
  /// Emoji_Presentation=No (☀☁☂☃ — text by default, emoji only with
  /// FE0F), plus the watch/arrow/square block that isn't in either
  /// allowlist. Data verified against emoji-data.txt 15.1:
  /// every rune in `_isMiscSymbolEmoji` and `_isDingbatEmoji` except
  /// 0x2600-0x2603 has Emoji_Presentation=Yes.
  static bool _isEmojiPresentationByDefault(int rune) {
    // The few BMP emoji candidates that are text-presentation by
    // default (Emoji=Yes, Emoji_Presentation=No).
    if (rune >= 0x2600 && rune <= 0x2603) return false; // ☀☁☂☃

    return _isMiscSymbolEmoji(rune) ||
        _isDingbatEmoji(rune) ||
        rune == 0x231A || // ⌚ Watch
        rune == 0x231B || // ⌛ Hourglass done
        (rune >= 0x23E9 && rune <= 0x23EC) || // ⏩⏪⏫⏬
        rune == 0x23F0 || // ⏰ Alarm clock
        rune == 0x23F3 || // ⏳ Hourglass not done
        (rune >= 0x25FD && rune <= 0x25FE) || // ◽◾ (25FB/25FC are text-default)
        (rune >= 0x2B1B && rune <= 0x2B1C) || // ⬛⬜
        rune == 0x2B50 || // ⭐ Star
        rune == 0x2B55; // ⭕ Heavy circle
  }

  /// Check if a rune is always zero-width regardless of context
  /// (combining marks, ZWJ, variation selectors).
  static bool _isZeroWidth(int rune) {
    // Combining marks
    if ((rune >= 0x0300 && rune <= 0x036F) ||
        (rune >= 0x1AB0 && rune <= 0x1AFF) ||
        (rune >= 0x1DC0 && rune <= 0x1DFF) ||
        (rune >= 0x20D0 && rune <= 0x20FF) ||
        (rune >= 0xFE20 && rune <= 0xFE2F)) {
      return true;
    }
    // Zero-width joiner and non-joiner
    if (rune == 0x200D || rune == 0x200C) {
      return true;
    }
    // Variation selectors
    if ((rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0xE0100 && rune <= 0xE01EF)) {
      return true;
    }
    return false;
  }

  /// Check if a rune represents an emoji (width 2)
  ///
  /// This uses an allowlist approach for common emoji ranges and specific characters.
  /// Characters not in these ranges are treated as text symbols (width 1) by default.
  static bool _isEmoji(int rune) {
    // Basic emoji blocks - these are primarily emoji
    if ((rune >= 0x1F300 && rune <= 0x1F5FF) || // Misc Symbols and Pictographs
        (rune >= 0x1F600 && rune <= 0x1F64F) || // Emoticons
        (rune >= 0x1F680 && rune <= 0x1F6FF) || // Transport and Map Symbols
        (rune >= 0x1F900 &&
            rune <= 0x1F9FF) || // Supplemental Symbols and Pictographs
        (rune >= 0x1FA70 && rune <= 0x1FAFF)) {
      // Symbols and Pictographs Extended-A
      return true;
    }

    // Regional indicator symbols (flags)
    if (rune >= 0x1F1E6 && rune <= 0x1F1FF) {
      return true;
    }

    // Miscellaneous Symbols (0x2600-0x26FF) - use allowlist for emoji
    // Most symbols here are text symbols, only specific ones are emoji
    if (_isMiscSymbolEmoji(rune)) {
      return true;
    }

    // Dingbats range (0x2700-0x27BF) - use allowlist for emoji
    if (_isDingbatEmoji(rune)) {
      return true;
    }

    // Some specific emojis in other ranges
    if (rune == 0x231A ||
        rune == 0x231B || // Watch, hourglass
        rune == 0x23E9 ||
        rune == 0x23EA || // Fast forward, rewind
        rune == 0x23EB ||
        rune == 0x23EC || // Up/down arrows
        rune == 0x23F0 ||
        rune == 0x23F3 || // Alarm clock, hourglass flowing
        (rune >= 0x25FB && rune <= 0x25FE) || // Squares
        (rune >= 0x2B1B && rune <= 0x2B1C) || // Black/white squares
        rune == 0x2B50 || // Star
        rune == 0x2B55) {
      // Heavy circle
      return true;
    }

    return false;
  }

  /// Check if a character in the Miscellaneous Symbols range (0x2600-0x26FF) is an emoji
  static bool _isMiscSymbolEmoji(int rune) {
    if (rune < 0x2600 || rune > 0x26FF) return false;

    // Allowlist of emoji in this range (rest are text symbols)
    return rune == 0x2600 || // ☀ Sun
        rune == 0x2601 || // ☁ Cloud
        rune == 0x2602 || // ☂ Umbrella (can be emoji)
        rune == 0x2603 || // ☃ Snowman
        (rune >= 0x2614 &&
            rune <= 0x2615) || // ☔☕ Umbrella with rain drops, Hot beverage
        (rune >= 0x2648 && rune <= 0x2653) || // ♈-♓ Zodiac signs
        rune == 0x267F || // ♿ Wheelchair
        rune == 0x2693 || // ⚓ Anchor
        rune == 0x26A1 || // ⚡ High voltage
        (rune >= 0x26AA && rune <= 0x26AB) || // ⚪⚫ White/black circles
        (rune >= 0x26BD && rune <= 0x26BE) || // ⚽⚾ Soccer, baseball
        (rune >= 0x26C4 && rune <= 0x26C5) || // ⛄⛅ Snowman, sun behind cloud
        rune == 0x26CE || // ⛎ Ophiuchus
        rune == 0x26D4 || // ⛔ No entry
        rune == 0x26EA || // ⛪ Church
        (rune >= 0x26F2 && rune <= 0x26F3) || // ⛲⛳ Fountain, flag in hole
        rune == 0x26F5 || // ⛵ Sailboat
        rune == 0x26FA || // ⛺ Tent
        rune == 0x26FD; // ⛽ Fuel pump
  }

  /// Check if a character in the Dingbats range (0x2700-0x27BF) is an emoji
  static bool _isDingbatEmoji(int rune) {
    if (rune < 0x2700 || rune > 0x27BF) return false;

    // Allowlist of emoji in this range (rest are text symbols)
    return rune == 0x2705 || // ✅ Check mark button
        (rune >= 0x270A && rune <= 0x270B) || // ✊✋ Raised fist/hand
        rune == 0x2728 || // ✨ Sparkles
        rune == 0x274C || // ❌ Cross mark
        rune == 0x274E || // ❎ Cross mark button
        (rune >= 0x2753 && rune <= 0x2755) || // ❓❔❕ Question/exclamation marks
        rune == 0x2757 || // ❗ Exclamation mark
        (rune >= 0x2795 && rune <= 0x2797) || // ➕➖➗ Plus/minus/divide
        rune == 0x27B0 || // ➰ Curly loop
        rune == 0x27BF; // ➿ Double curly loop
  }

  /// Split a string into grapheme clusters with their positions and widths
  static List<GraphemeInfo> analyzeString(String text) {
    final result = <GraphemeInfo>[];
    final runes = text.runes.toList();
    int columnPosition = 0;

    for (int i = 0; i < runes.length; i++) {
      final rune = runes[i];
      var width = runeWidth(rune);

      // A U+FE0F variation selector upgrades a BMP emoji candidate to
      // emoji presentation (2 cells) — mirror graphemeWidth here so
      // e.g. "☀️" measures 2 even though bare "☀" measures 1.
      if (width == 1 &&
          i + 1 < runes.length &&
          runes[i + 1] == 0xFE0F &&
          _isBmpEmoji(rune)) {
        width = 2;
      }

      // Skip zero-width characters for positioning
      if (width > 0) {
        result.add(GraphemeInfo(
          character: String.fromCharCode(rune),
          runeIndex: i,
          columnPosition: columnPosition,
          displayWidth: width,
        ));
        columnPosition += width;
      }
    }

    return result;
  }
}

/// Information about a grapheme cluster in a string
class GraphemeInfo {
  final String character;
  final int runeIndex;
  final int columnPosition;
  final int displayWidth;

  const GraphemeInfo({
    required this.character,
    required this.runeIndex,
    required this.columnPosition,
    required this.displayWidth,
  });
}
