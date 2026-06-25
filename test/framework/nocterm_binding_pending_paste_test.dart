// Tests for NoctermBinding's pending-paste slot — the framework-
// level API that lets TerminalBinding route an IME bracketed paste
// without writing to the system clipboard. Crux's chat_input uses
// [NoctermBinding.instance.hasPendingPasteText] in its Ctrl+V
// handler to distinguish a user-initiated paste (which should also
// attach a clipboard image) from the synthetic Ctrl+V that the
// framework emits for an IME paste (which should NOT touch the
// clipboard).

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  // Initialize a NoctermTestBinding once for the whole group so
  // NoctermBinding.instance is non-null in every test below.
  late NoctermTestBinding binding;

  setUpAll(() {
    binding = NoctermTestBinding(size: const Size(80, 24));
  });

  group('NoctermBinding.pending paste slot', () {
    setUp(() {
      // Each test starts with a clean slot; previous tests may have
      // left text behind.
      NoctermBinding.instance.consumePendingPasteText();
    });

    test('hasPendingPasteText is false on a fresh binding', () {
      expect(NoctermBinding.instance.hasPendingPasteText, isFalse);
    });

    test('setPendingPasteText flips the flag; consume clears it', () {
      NoctermBinding.instance.setPendingPasteText('你好世界');
      expect(NoctermBinding.instance.hasPendingPasteText, isTrue);
      expect(NoctermBinding.instance.consumePendingPasteText(),
          equals('你好世界'));
      expect(NoctermBinding.instance.hasPendingPasteText, isFalse);
    });

    test('consume on an empty slot returns null and keeps flag false', () {
      expect(NoctermBinding.instance.consumePendingPasteText(), isNull);
      expect(NoctermBinding.instance.hasPendingPasteText, isFalse);
    });

    test('a second set after consume is observable again', () {
      NoctermBinding.instance.setPendingPasteText('first');
      expect(NoctermBinding.instance.consumePendingPasteText(),
          equals('first'));
      expect(NoctermBinding.instance.hasPendingPasteText, isFalse);

      NoctermBinding.instance.setPendingPasteText('second');
      expect(NoctermBinding.instance.hasPendingPasteText, isTrue);
      expect(NoctermBinding.instance.consumePendingPasteText(),
          equals('second'));
    });
  });
}