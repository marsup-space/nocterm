import 'dart:convert';
import 'logical_key.dart';
import 'keyboard_event.dart';

/// Parses raw terminal input bytes into keyboard events.
class KeyboardParser {
  final List<int> _buffer = [];

  int? _suppressCodepoint;

  /// Parse incoming bytes and return keyboard events.
  /// Returns null if more bytes are needed to complete a sequence.
  KeyboardEvent? parseBytes(List<int> bytes) {
    _buffer.addAll(bytes);

    if (_buffer.isEmpty) return null;

    // Try to parse the current buffer
    final event = _parseBuffer();

    // If we successfully parsed an event, clear the buffer
    if (event != null) {
      _buffer.clear();
    }

    return event;
  }

  KeyboardEvent? _parseBuffer() {
    if (_buffer.isEmpty) return null;

    final first = _buffer[0];

    // Check if this raw byte should be suppressed (duplicate from
    // modifyOtherKeys level 2 or kitty protocol reporting the same
    // printable key as both an escape sequence and a raw byte).
    if (_suppressCodepoint != null && first == _suppressCodepoint) {
      _suppressCodepoint = null;
      _buffer.removeAt(0);
      if (_buffer.isEmpty) return null;
      return _parseBuffer();
    }
    _suppressCodepoint = null;

    // ESC sequences
    if (first == 0x1B) {
      return _parseEscapeSequence();
    }

    // Tab
    if (first == 0x09) {
      return KeyboardEvent(
        logicalKey: LogicalKey.tab,
        character: '\t',
        modifiers: const ModifierKeys(),
      );
    }

    // Enter/Return - 0x0D (CR).
    // We disable icrnl in raw mode so CR passes through verbatim
    // instead of being translated to LF (0x0A). This lets us
    // distinguish Enter (0x0D) from Ctrl+J (0x0A, which falls
    // through to _parseControlChar as keyJ+ctrl).
    if (first == 0x0D) {
      return KeyboardEvent(
        logicalKey: LogicalKey.enter,
        character: '\n',
        modifiers: const ModifierKeys(),
      );
    }

    // Backspace key sends 0x7F on most modern terminals.
    // 0x08 (Ctrl+H) is sent by Ctrl+Backspace on many terminals.
    if (first == 0x7F) {
      return KeyboardEvent(
        logicalKey: LogicalKey.backspace,
        modifiers: const ModifierKeys(),
      );
    }
    if (first == 0x08) {
      return KeyboardEvent(
        logicalKey: LogicalKey.backspace,
        modifiers: const ModifierKeys(ctrl: true),
      );
    }

    // Control characters (Ctrl+A through Ctrl+Z)
    // Note: 0x08 (Ctrl+H), 0x09 (Ctrl+I/Tab), 0x0D (Ctrl+M/Enter) are handled above.
    // 0x0A (Ctrl+J) falls through to here — it is NOT mapped to Enter because
    // we disable icrnl, so Ctrl+J and Enter are distinguishable.
    if (first >= 0x01 && first <= 0x1A) {
      return _parseControlChar(first);
    }

    // Try to decode as UTF-8
    String? decodedChar;
    int bytesConsumed = 0;

    // Determine UTF-8 sequence length
    if (first < 0x80) {
      // Single-byte ASCII
      decodedChar = String.fromCharCode(first);
      bytesConsumed = 1;
    } else if (first >= 0xC0 && first < 0xE0) {
      // Two-byte sequence
      if (_buffer.length >= 2) {
        try {
          decodedChar = utf8.decode(_buffer.sublist(0, 2));
          bytesConsumed = 2;
        } catch (e) {
          // Invalid UTF-8 sequence
        }
      } else {
        // Need more bytes
        return null;
      }
    } else if (first >= 0xE0 && first < 0xF0) {
      // Three-byte sequence
      if (_buffer.length >= 3) {
        try {
          decodedChar = utf8.decode(_buffer.sublist(0, 3));
          bytesConsumed = 3;
        } catch (e) {
          // Invalid UTF-8 sequence
        }
      } else {
        // Need more bytes
        return null;
      }
    } else if (first >= 0xF0) {
      // Four-byte sequence
      if (_buffer.length >= 4) {
        try {
          decodedChar = utf8.decode(_buffer.sublist(0, 4));
          bytesConsumed = 4;
        } catch (e) {
          // Invalid UTF-8 sequence
        }
      } else {
        // Need more bytes
        return null;
      }
    }

    if (decodedChar != null && bytesConsumed > 0) {
      // Remove consumed bytes from buffer
      _buffer.removeRange(
          0, bytesConsumed - 1); // Keep one byte for the main parser to clear

      // Regular character
      final key = LogicalKey.fromCharacter(decodedChar);
      // Check if it's uppercase to infer shift was pressed
      final code = decodedChar.codeUnitAt(0);
      final isUpperCase = (code >= 0x41 && code <= 0x5A) || // A-Z
          (decodedChar != decodedChar.toLowerCase()); // Other uppercase chars
      return KeyboardEvent(
        logicalKey: key ?? LogicalKey(code, 'unknown'),
        character: decodedChar,
        modifiers: ModifierKeys(shift: isUpperCase),
      );
    }

    // Unknown character - create a generic key
    return KeyboardEvent(
      logicalKey: LogicalKey(first, 'unknown'),
      modifiers: const ModifierKeys(),
    );
  }

  KeyboardEvent? _parseEscapeSequence() {
    if (_buffer.length == 1) {
      // Just ESC key pressed
      return KeyboardEvent(
        logicalKey: LogicalKey.escape,
        modifiers: const ModifierKeys(),
      );
    }

    // Check for Alt+key combinations (ESC followed by character)
    if (_buffer.length == 2) {
      final second = _buffer[1];

      // Alt+letter (lowercase)
      if (second >= 0x61 && second <= 0x7A) {
        // Return the base key with Alt modifier
        final char = String.fromCharCode(second);
        final baseKey =
            LogicalKey.fromCharacter(char) ?? LogicalKey(second, 'unknown');
        return KeyboardEvent(
          logicalKey: baseKey,
          character: char,
          modifiers: const ModifierKeys(alt: true),
        );
      }

      // If it's not a complete Alt sequence, might be start of longer sequence
      if (second != 0x5B && second != 0x4F) {
        // Not a CSI or SS3 sequence, treat as ESC + char
        return KeyboardEvent(
          logicalKey: LogicalKey.escape,
          modifiers: const ModifierKeys(),
        );
      }
    }

    // CSI sequences (ESC [ ...)
    if (_buffer.length >= 3 && _buffer[1] == 0x5B) {
      return _parseCSISequence();
    }

    // SS3 sequences (ESC O ...) - used for F1-F4
    if (_buffer.length >= 3 && _buffer[1] == 0x4F) {
      return _parseSS3Sequence();
    }

    // Need more bytes to complete the sequence
    return null;
  }

  KeyboardEvent? _parseCSISequence() {
    // Try kitty keyboard protocol: CSI codepoint ; modifier u
    {
      final result = _parseKittySequence();
      if (result != null) return result;
    }

    // Try xterm modifyOtherKeys: CSI 27 ; modifier ; charcode ~
    {
      final result = _parseModifyOtherKeysSequence();
      if (result != null) return result;
    }

    // Kitty-protocol legacy functional keys with an explicit modifier field:
    // CSI 1 ; <modifier> <letter>  (e.g. ESC [ 1 ; 1 A = plain Up). See the
    // identical clause in InputParser for the full rationale — under the
    // kitty disambiguate flag Ghostty always includes the modifier parameter,
    // which none of the legacy branches below claim. Purely additive.
    {
      final result = _parseKittyLegacyFunctional();
      if (result != null) return result;
    }

    // Arrow keys: ESC [ A/B/C/D
    if (_buffer.length == 3) {
      switch (_buffer[2]) {
        case 0x41:
          return KeyboardEvent(
            logicalKey: LogicalKey.arrowUp,
            modifiers: const ModifierKeys(),
          );
        case 0x42:
          return KeyboardEvent(
            logicalKey: LogicalKey.arrowDown,
            modifiers: const ModifierKeys(),
          );
        case 0x43:
          return KeyboardEvent(
            logicalKey: LogicalKey.arrowRight,
            modifiers: const ModifierKeys(),
          );
        case 0x44:
          return KeyboardEvent(
            logicalKey: LogicalKey.arrowLeft,
            modifiers: const ModifierKeys(),
          );
        case 0x48:
          return KeyboardEvent(
            logicalKey: LogicalKey.home,
            modifiers: const ModifierKeys(),
          );
        case 0x46:
          return KeyboardEvent(
            logicalKey: LogicalKey.end,
            modifiers: const ModifierKeys(),
          );
        case 0x5A:
          return KeyboardEvent(
            logicalKey: LogicalKey.tab,
            modifiers: const ModifierKeys(shift: true),
          ); // ESC [ Z is Shift+Tab
      }
    }

    // Modified arrow keys and other sequences
    if (_buffer.length >= 6) {
      final sequence = String.fromCharCodes(_buffer);

      // Shift+Arrow: ESC [ 1 ; 2 A/B/C/D
      if (sequence.startsWith('\x1B[1;2')) {
        switch (_buffer[5]) {
          case 0x41:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowUp,
              modifiers: const ModifierKeys(shift: true),
            );
          case 0x42:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowDown,
              modifiers: const ModifierKeys(shift: true),
            );
          case 0x43:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowRight,
              modifiers: const ModifierKeys(shift: true),
            );
          case 0x44:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowLeft,
              modifiers: const ModifierKeys(shift: true),
            );
        }
      }

      // Alt+Arrow: ESC [ 1 ; 3 A/B/C/D
      if (sequence.startsWith('\x1B[1;3')) {
        switch (_buffer[5]) {
          case 0x41:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowUp,
              modifiers: const ModifierKeys(alt: true),
            );
          case 0x42:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowDown,
              modifiers: const ModifierKeys(alt: true),
            );
          case 0x43:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowRight,
              modifiers: const ModifierKeys(alt: true),
            );
          case 0x44:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowLeft,
              modifiers: const ModifierKeys(alt: true),
            );
        }
      }

      // Ctrl+Arrow: ESC [ 1 ; 5 A/B/C/D
      if (sequence.startsWith('\x1B[1;5')) {
        switch (_buffer[5]) {
          case 0x41:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowUp,
              modifiers: const ModifierKeys(ctrl: true),
            );
          case 0x42:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowDown,
              modifiers: const ModifierKeys(ctrl: true),
            );
          case 0x43:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowRight,
              modifiers: const ModifierKeys(ctrl: true),
            );
          case 0x44:
            return KeyboardEvent(
              logicalKey: LogicalKey.arrowLeft,
              modifiers: const ModifierKeys(ctrl: true),
            );
        }
      }
    }

    // Modified special keys with ~ terminator: ESC [ X ; Y ~
    // Example: ESC [ 3 ; 5 ~ = Ctrl+Delete. Modifier uses the same
    // 1+bitmask encoding as kitty/modifyOtherKeys.
    if (_buffer.length >= 6 &&
        _buffer.contains(0x7E) &&
        _buffer.contains(0x3B)) {
      final tildeIndex = _buffer.indexOf(0x7E);
      final semicolonIndex = _buffer.indexOf(0x3B);
      if (semicolonIndex > 2 && semicolonIndex < tildeIndex) {
        final keyParam =
            String.fromCharCodes(_buffer.sublist(2, semicolonIndex));
        final modParam = String.fromCharCodes(
            _buffer.sublist(semicolonIndex + 1, tildeIndex));
        final keyCode = int.tryParse(keyParam);
        final modValue = int.tryParse(modParam);
        if (keyCode != null && modValue != null) {
          final modifiers = _decodeModifiers(modValue);
          LogicalKey? key;
          switch (keyCode) {
            case 2:
              key = LogicalKey.insert;
              break;
            case 3:
              key = LogicalKey.delete;
              break;
            case 5:
              key = LogicalKey.pageUp;
              break;
            case 6:
              key = LogicalKey.pageDown;
              break;
          }
          if (key != null) {
            return KeyboardEvent(logicalKey: key, modifiers: modifiers);
          }
        }
      }
    }

    // Function keys and special keys with ~ terminator
    if (_buffer.contains(0x7E)) {
      int tildeIndex = _buffer.indexOf(0x7E);
      final paramStr = String.fromCharCodes(_buffer.sublist(2, tildeIndex));
      final parts = paramStr.split(';');
      final keyCode = int.tryParse(parts[0]);
      final modifierValue = parts.length > 1 ? int.tryParse(parts[1]) : null;

      if (keyCode != null) {
        final modifiers = modifierValue != null
            ? _decodeModifiers(modifierValue)
            : const ModifierKeys();
        final logicalKey = switch (keyCode) {
          2 => LogicalKey.insert,
          3 => LogicalKey.delete,
          5 => LogicalKey.pageUp,
          6 => LogicalKey.pageDown,
          15 => LogicalKey.f5,
          17 => LogicalKey.f6,
          18 => LogicalKey.f7,
          19 => LogicalKey.f8,
          20 => LogicalKey.f9,
          21 => LogicalKey.f10,
          23 => LogicalKey.f11,
          24 => LogicalKey.f12,
          _ => null,
        };
        if (logicalKey != null) {
          return KeyboardEvent(
            logicalKey: logicalKey,
            modifiers: modifiers,
          );
        }
      }

      return null;
    }

    // Check if we need more bytes (sequence not complete)
    // CSI sequences typically end with a letter or ~
    final lastByte = _buffer.last;
    if ((lastByte >= 0x40 && lastByte <= 0x7E) || lastByte == 0x7E) {
      // Sequence is complete but we don't recognize it
      return null;
    }

    // Need more bytes
    return null;
  }

  /// Parse kitty-protocol legacy functional keys of the form
  /// `CSI 1 ; <modifier> <final-letter>` (A/B/C/D arrows, H/F Home/End,
  /// P/Q/S F1–F4). Mirrors `InputParser._parseKittyLegacyFunctional` — see
  /// that method for the full rationale. Returns null when the buffer doesn't
  /// hold a complete sequence of this exact shape.
  KeyboardEvent? _parseKittyLegacyFunctional() {
    if (_buffer.length < 6) return null;
    if (_buffer[1] != 0x5B) return null; // '['
    if (_buffer[2] != 0x31) return null; // '1'
    if (_buffer[3] != 0x3B) return null; // ';'

    int i = 4;
    final modStart = i;
    while (i < _buffer.length &&
        _buffer[i] >= 0x30 &&
        _buffer[i] <= 0x39) {
      i++;
    }
    if (i == modStart) return null; // no modifier digits
    if (i >= _buffer.length) return null; // incomplete; wait for more bytes

    final finalByte = _buffer[i];
    final modValue =
        int.tryParse(String.fromCharCodes(_buffer.sublist(modStart, i)));
    if (modValue == null) return null;
    final modifiers = _decodeModifiers(modValue);

    final LogicalKey? key = switch (finalByte) {
      0x41 => LogicalKey.arrowUp,
      0x42 => LogicalKey.arrowDown,
      0x43 => LogicalKey.arrowRight,
      0x44 => LogicalKey.arrowLeft,
      0x48 => LogicalKey.home,
      0x46 => LogicalKey.end,
      0x50 => LogicalKey.f1,
      0x51 => LogicalKey.f2,
      0x53 => LogicalKey.f4,
      // 0x45 ('E') keypad Begin and 0x52 ('R', conflicts with cursor-position
      // report) are intentionally unmapped.
      _ => null,
    };
    if (key == null) return null;

    return KeyboardEvent(logicalKey: key, modifiers: modifiers);
  }

  KeyboardEvent? _parseSS3Sequence() {
    if (_buffer.length != 3) return null;

    // F1-F4 use SS3 sequences
    switch (_buffer[2]) {
      case 0x50:
        return KeyboardEvent(
          logicalKey: LogicalKey.f1,
          modifiers: const ModifierKeys(),
        );
      case 0x51:
        return KeyboardEvent(
          logicalKey: LogicalKey.f2,
          modifiers: const ModifierKeys(),
        );
      case 0x52:
        return KeyboardEvent(
          logicalKey: LogicalKey.f3,
          modifiers: const ModifierKeys(),
        );
      case 0x53:
        return KeyboardEvent(
          logicalKey: LogicalKey.f4,
          modifiers: const ModifierKeys(),
        );
    }

    return null;
  }

  KeyboardEvent? _parseControlChar(int code) {
    // Ctrl+A through Ctrl+Z
    // Control characters 0x01-0x1A correspond to Ctrl+A through Ctrl+Z
    if (code >= 0x01 && code <= 0x1A) {
      // Convert to the base letter (A=0x41, B=0x42, etc.)
      final letterCode = code + 0x40; // 0x01 + 0x40 = 0x41 ('A')
      final letter = String.fromCharCode(letterCode).toLowerCase();
      final baseKey = LogicalKey.fromCharacter(letter) ??
          LogicalKey(letterCode, 'ctrl+$letter');

      return KeyboardEvent(
        logicalKey: baseKey,
        modifiers: const ModifierKeys(ctrl: true),
      );
    }

    return null;
  }

  /// Parse kitty keyboard protocol sequence: CSI codepoint ; modifier u
  /// Supports `:` sub-parameters per the kitty spec (e.g. \x1b[13:10;2u).
  KeyboardEvent? _parseKittySequence() {
    // Find 'u' terminator (0x75)
    // Valid parameter bytes: digits (0x30-0x39), ';' (0x3B), ':' (0x3A)
    int uIndex = -1;
    for (int i = 2; i < _buffer.length; i++) {
      if (_buffer[i] == 0x75) {
        uIndex = i;
        break;
      }
      if (_buffer[i] != 0x3B && // ';'
          _buffer[i] != 0x3A && // ':' (sub-parameter separator)
          !(_buffer[i] >= 0x30 && _buffer[i] <= 0x39)) {
        return null;
      }
    }

    if (uIndex == -1) return null;

    final paramStr = String.fromCharCodes(_buffer.sublist(2, uIndex));
    final parts = paramStr.split(';');

    if (parts.isEmpty || parts.length > 3) return null;

    // The codepoint field may contain `:` sub-parameters (e.g. "13:10").
    // Per the kitty spec, the first value is the Unicode codepoint.
    final codepointStr = parts[0].split(':').first;
    final codepoint = int.tryParse(codepointStr);
    if (codepoint == null) return null;

    // The modifier field may also contain `:` sub-parameters (e.g. "2:1").
    // The first value is the modifier bitmask.
    final modifierStr = parts.length >= 2 ? parts[1].split(':').first : null;
    final modifierValue =
        modifierStr != null ? int.tryParse(modifierStr) : null;
    final modifiers = modifierValue != null
        ? _decodeModifiers(modifierValue)
        : const ModifierKeys();

    return _codepointToKeyEvent(codepoint, modifiers);
  }

  /// Parse xterm modifyOtherKeys sequence: CSI 27 ; modifier ; charcode ~
  KeyboardEvent? _parseModifyOtherKeysSequence() {
    if (_buffer.length < 3 || _buffer[2] != 0x32) return null;

    // Find '~' terminator
    int tildeIndex = -1;
    for (int i = 2; i < _buffer.length; i++) {
      if (_buffer[i] == 0x7E) {
        tildeIndex = i;
        break;
      }
    }

    if (tildeIndex == -1) return null;

    final paramStr = String.fromCharCodes(_buffer.sublist(2, tildeIndex));
    final parts = paramStr.split(';');

    if (parts.length != 3) return null;

    final marker = int.tryParse(parts[0]);
    if (marker != 27) return null;

    final modifierValue = int.tryParse(parts[1]);
    final charCode = int.tryParse(parts[2]);
    if (modifierValue == null || charCode == null) return null;

    final modifiers = _decodeModifiers(modifierValue);
    return _codepointToKeyEvent(charCode, modifiers);
  }

  /// Decode modifier bitmask. Value is 1 + bitmask.
  /// Bit 0 = shift, Bit 1 = alt, Bit 2 = ctrl, Bit 3 = super/meta
  ModifierKeys _decodeModifiers(int value) {
    final bitmask = value - 1;
    return ModifierKeys(
      shift: (bitmask & 1) != 0,
      alt: (bitmask & 2) != 0,
      ctrl: (bitmask & 4) != 0,
      meta: (bitmask & 8) != 0,
    );
  }

  /// Convert a Unicode codepoint to a KeyboardEvent.
  KeyboardEvent _codepointToKeyEvent(int codepoint, ModifierKeys modifiers) {
    // When a printable character arrives via kitty/modifyOtherKeys,
    // the terminal may also send the raw byte afterward. Flag it
    // for suppression so we don't get duplicate input.
    if (modifiers == const ModifierKeys() &&
        codepoint >= 0x20 &&
        codepoint < 0x7F) {
      _suppressCodepoint = codepoint;
    }

    switch (codepoint) {
      case 13:
        return KeyboardEvent(
          logicalKey: LogicalKey.enter,
          character: '\n',
          modifiers: modifiers,
        );
      case 57414: // Kitty numpad enter (0xE00E)
        return KeyboardEvent(
          logicalKey: LogicalKey.numpadEnter,
          character: '\n',
          modifiers: modifiers,
        );
      case 9:
        return KeyboardEvent(
          logicalKey: LogicalKey.tab,
          character: '\t',
          modifiers: modifiers,
        );
      case 27:
        return KeyboardEvent(
          logicalKey: LogicalKey.escape,
          modifiers: modifiers,
        );
      case 127:
        return KeyboardEvent(
          logicalKey: LogicalKey.backspace,
          modifiers: modifiers,
        );
      case 1: // modifyOtherKeys: Home
        return KeyboardEvent(
          logicalKey: LogicalKey.home,
          modifiers: modifiers,
        );
      case 2: // modifyOtherKeys: Insert
        return KeyboardEvent(
          logicalKey: LogicalKey.insert,
          modifiers: modifiers,
        );
      case 3: // modifyOtherKeys: Delete
        return KeyboardEvent(
          logicalKey: LogicalKey.delete,
          modifiers: modifiers,
        );
      case 4: // modifyOtherKeys: End
        return KeyboardEvent(
          logicalKey: LogicalKey.end,
          modifiers: modifiers,
        );
      case 5: // modifyOtherKeys: PageUp
        return KeyboardEvent(
          logicalKey: LogicalKey.pageUp,
          modifiers: modifiers,
        );
      case 6: // modifyOtherKeys: PageDown
        return KeyboardEvent(
          logicalKey: LogicalKey.pageDown,
          modifiers: modifiers,
        );
      case 57419: // Kitty Delete (0xE04B)
        return KeyboardEvent(
          logicalKey: LogicalKey.delete,
          modifiers: modifiers,
        );
      case 57420: // Kitty Insert (0xE04C)
        return KeyboardEvent(
          logicalKey: LogicalKey.insert,
          modifiers: modifiers,
        );
      case 57421: // Kitty Home (0xE04D)
        return KeyboardEvent(
          logicalKey: LogicalKey.home,
          modifiers: modifiers,
        );
      case 57422: // Kitty End (0xE04E)
        return KeyboardEvent(
          logicalKey: LogicalKey.end,
          modifiers: modifiers,
        );
      case 57423: // Kitty PageUp (0xE04F)
        return KeyboardEvent(
          logicalKey: LogicalKey.pageUp,
          modifiers: modifiers,
        );
      case 57424: // Kitty PageDown (0xE050)
        return KeyboardEvent(
          logicalKey: LogicalKey.pageDown,
          modifiers: modifiers,
        );
      default:
        final char = String.fromCharCode(codepoint);
        final key = LogicalKey.fromCharacter(char) ??
            LogicalKey(codepoint, 'codepoint($codepoint)');
        return KeyboardEvent(
          logicalKey: key,
          character: char,
          modifiers: modifiers,
        );
    }
  }

  /// Clear any buffered input
  void clear() {
    _buffer.clear();
    _suppressCodepoint = null;
  }
}
