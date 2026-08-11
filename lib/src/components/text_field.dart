import 'dart:async';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:nocterm/nocterm.dart' hide TextAlign;
import 'package:nocterm/src/framework/terminal_canvas.dart';
import '../rendering/mouse_hit_test.dart';
import '../rendering/mouse_tracker.dart';
import '../text/text_layout_engine.dart';
import '../utils/unicode_width.dart';
import '../text/selection_utils.dart' as selection_utils;
import 'text_field/cursor_movement.dart';

/// Provides word boundary offsets for a given text and cursor position.
///
/// [previousBoundary] returns the offset of the word boundary at or before
/// [offset], or 0 if none.
/// [nextBoundary] returns the offset of the word boundary after [offset],
/// or text.length if none.
typedef WordBoundaryProvider = ({
  int Function(String text, int offset) previousBoundary,
  int Function(String text, int offset) nextBoundary,
});

/// Controls the text being edited.
class TextEditingController {
  TextEditingController({String? text})
      : _text = text ?? '',
        _selection = TextSelection.collapsed(offset: text?.length ?? 0);

  String _text;
  TextSelection _selection;
  final _listeners = <VoidCallback>[];

  /// The current text being edited.
  String get text => _text;
  set text(String newText) {
    if (_text != newText) {
      _text = newText;
      _selection = TextSelection.collapsed(offset: newText.length);
      notifyListeners();
    }
  }

  /// The current selection.
  TextSelection get selection => _selection;
  set selection(TextSelection newSelection) {
    if (_selection != newSelection) {
      _selection = newSelection;
      notifyListeners();
    }
  }

  /// Clear the text.
  void clear() {
    text = '';
  }

  /// Add a listener.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners.
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Dispose of the controller.
  void dispose() {
    _listeners.clear();
  }
}

/// Text selection representation.
class TextSelection {
  const TextSelection({
    required this.baseOffset,
    required this.extentOffset,
  });

  const TextSelection.collapsed({required int offset})
      : baseOffset = offset,
        extentOffset = offset;

  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => math.min(baseOffset, extentOffset);
  int get end => math.max(baseOffset, extentOffset);

  TextSelection copyWith({int? baseOffset, int? extentOffset}) {
    return TextSelection(
      baseOffset: baseOffset ?? this.baseOffset,
      extentOffset: extentOffset ?? this.extentOffset,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextSelection &&
        other.baseOffset == baseOffset &&
        other.extentOffset == extentOffset;
  }

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);
}

/// A Material Design text field for terminal UI.
class TextField extends StatefulComponent {
  const TextField({
    super.key,
    this.controller,
    this.focused = false,
    this.onFocusChange,
    this.decoration,
    this.style,
    this.placeholder,
    this.placeholderStyle,
    this.textAlign = TextAlign.left,
    this.readOnly = false,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onPaste,
    this.onKeyEvent,
    this.wordBoundaryProvider,
    this.enabled = true,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.cursorBlinkRate,
    this.selectionColor,
        this.showCursor = true,
    this.width,
    this.height,
    this.styleSegments,
  })   : assert(maxLines == null || maxLines > 0),
        assert(minLines == null || minLines > 0),
        assert(
          (maxLines == null) || (minLines == null) || (maxLines >= minLines),
          "minLines can't be greater than maxLines",
        ),
        assert(!obscureText || maxLines == 1,
            'Obscured fields cannot be multiline.'),
        assert(maxLength == null || maxLength > 0);

  final TextEditingController? controller;
  final bool focused;
  final ValueChanged<bool>? onFocusChange;
  final InputDecoration? decoration;
  final TextStyle? style;
  final String? placeholder;
  final TextStyle? placeholderStyle;
  final TextAlign textAlign;
  final bool readOnly;
  final bool obscureText;
  final String obscuringCharacter;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;

  /// Callback invoked when text is pasted.
  /// Return `true` to indicate the paste was handled (skip default insertion).
  /// Return `false` or null to proceed with default insertion.
  final bool Function(String pastedText)? onPaste;

  /// Callback invoked when a key event occurs, before TextField processes it.
  /// Return `true` to indicate the event was handled (TextField will skip processing).
  /// Return `false` to let TextField handle the event normally.
  /// This allows parent widgets to intercept keys like arrow up/down for custom handling.
  final bool Function(KeyboardEvent event)? onKeyEvent;

  /// Provider for word boundary calculations used by Ctrl+Backspace,
  /// Ctrl+Delete, and Ctrl+Arrow navigation. If null, defaults to
  /// whitespace/punctuation-based boundaries.
  final WordBoundaryProvider? wordBoundaryProvider;

  final bool enabled;

  /// The color of the text cursor.
  ///
  /// If null, defaults to the theme's [TuiThemeData.primary] color.
  final Color? cursorColor;
  final CursorStyle cursorStyle;
  final Duration? cursorBlinkRate;

  /// The color of the text selection highlight.
  ///
  /// If null, defaults to the theme's [TuiThemeData.primary] color with
  /// reduced opacity.
  final Color? selectionColor;
  final bool showCursor;
  final double? width;
  final double? height;

  /// Optional per-character styled segments for rich text rendering.
  ///
  /// When provided, the text field renders each segment with its own
  /// [TextStyle] (including [TextStyle.backgroundColor]) instead of
  /// applying a single style to the whole text. This enables inline
  /// "chip" styling — e.g. `$skill-name` rendered with a highlighted
  /// background while the rest of the text stays plain.
  ///
  /// The segments must cover the full text without gaps or overlaps:
  /// `segments.map((s) => s.text).join() == text`. The layout engine
  /// still operates on the plain [text] from [controller]; segments
  /// only affect paint-time styling.
  ///
  /// When null (the default), the field uses [style] for the entire
  /// text (original behavior).
  final List<StyledTextSegment>? styleSegments;

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField> {
  late TextEditingController _controller;
  bool _controllerIsInternal = false;
  Timer? _cursorTimer;
  bool _cursorVisible = true;
  int _viewOffset = 0; // For horizontal scrolling

  // Reference to the render object for cursor movement
  RenderTextField? _renderTextField;

  void _handleSelectionChangeFromRenderObject(TextSelection newSelection) {
    setState(() {
      _controller.selection = newSelection;
    });
    // Request focus if not already focused (e.g., user clicked in the field)
    if (!component.focused) {
      component.onFocusChange?.call(true);
    }
  }

  @override
  void initState() {
    super.initState();

    if (component.controller == null) {
      _controller = TextEditingController();
      _controllerIsInternal = true;
    } else {
      _controller = component.controller!;
    }

    _controller.addListener(_handleControllerChanged);

    if (component.focused && component.showCursor) {
      _startCursorBlink();
    }
  }

  @override
  void dispose() {
    _stopCursorBlink();
    _controller.removeListener(_handleControllerChanged);

    if (_controllerIsInternal) {
      _controller.dispose();
    }

    super.dispose();
  }

  void _handleControllerChanged() {
    component.onChanged?.call(_controller.text);
    setState(() {
      // Update view offset for horizontal scrolling
      _updateViewOffset();
    });
  }

  @override
  void didUpdateComponent(TextField oldComponent) {
    super.didUpdateComponent(oldComponent);

    // Handle focus changes or blink rate changes
    if (component.focused != oldComponent.focused ||
        component.cursorBlinkRate != oldComponent.cursorBlinkRate) {
      if (component.focused && component.showCursor) {
        _startCursorBlink();
      } else {
        _stopCursorBlink();
      }
    }
  }

  void _startCursorBlink() {
    _cursorVisible = true;
    _cursorTimer?.cancel();

    // Check if blinking is disabled (null blink rate means static cursor)
    if (component.cursorBlinkRate == null) {
      // Non-blinking cursor - always visible
      _cursorVisible = true;
      return;
    }

    // Start blinking with specified rate
    _cursorTimer = Timer.periodic(component.cursorBlinkRate!, (timer) {
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
    });
  }

  void _stopCursorBlink() {
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _cursorVisible = false;
  }

  void _updateViewOffset() {
    // Simple horizontal scrolling for single-line fields
    if (component.maxLines == 1 && component.width != null) {
      final text = _controller.text;
      final cursorPos = _controller.selection.extentOffset;

      // Account for borders and padding to get actual content width
      final decoration = component.decoration ?? const InputDecoration();
      final padding = decoration.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 1);
      final horizontalPadding = padding.left + padding.right;
      final borderWidth =
          decoration.border != null ? 2.0 : 0.0; // 1 on each side
      // Reserve 1 column for cursor display
      final maxVisibleWidth =
          (component.width! - borderWidth - horizontalPadding - 1).toInt();

      if (maxVisibleWidth <= 0) return; // No space to display text

      // Calculate visual column position of cursor (accounting for wide characters)
      final textBeforeCursor =
          text.substring(0, math.min(cursorPos, text.length));
      final cursorVisualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

      // Calculate visual width of currently visible text
      int viewOffsetVisualColumn = 0;
      if (_viewOffset > 0 && _viewOffset <= text.length) {
        viewOffsetVisualColumn =
            UnicodeWidth.stringWidth(text.substring(0, _viewOffset));
      }

      // Adjust view offset to keep cursor visible
      if (cursorVisualColumn < viewOffsetVisualColumn) {
        // Cursor moved before visible area - scroll left
        // Find the character offset that corresponds to the cursor's visual position
        _viewOffset = cursorPos;
      } else if (cursorVisualColumn >=
          viewOffsetVisualColumn + maxVisibleWidth) {
        // Cursor moved after visible area - scroll right
        // We need to find a view offset such that the cursor is visible
        int newOffset = 0;
        int visualWidth = 0;

        // Find the rightmost offset that still shows the cursor
        final graphemes = text.characters.toList();
        for (int i = 0; i <= math.min(cursorPos, graphemes.length); i++) {
          if (i < graphemes.length) {
            final graphemeWidth = UnicodeWidth.graphemeWidth(graphemes[i]);
            if (cursorVisualColumn - visualWidth <= maxVisibleWidth - 1) {
              newOffset = i;
            }
            visualWidth += graphemeWidth;
          }
        }
        _viewOffset = newOffset;
      }
    }
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (component.readOnly || !component.enabled) {
      return false;
    }

    // Allow parent widgets to intercept key events first
    if (component.onKeyEvent != null && component.onKeyEvent!(event)) {
      return true;
    }

    // Let Ctrl+C bubble up to allow app termination
    if (event.logicalKey == LogicalKey.keyC && event.isControlPressed) {
      return false;
    }

    final key = event.logicalKey;

    // Handle Tab/Shift+Tab for focus navigation
    if (key == LogicalKey.tab) {
      // Don't consume tab keys - let them bubble up for focus navigation
      return false;
    }

    final isEnter = key == LogicalKey.enter || key == LogicalKey.numpadEnter;

    // Handle newline insertion: Shift+Enter, Ctrl+Enter, Alt+Enter, or Ctrl+J.
    // Modified-Enter works in kitty-capable terminals. Ctrl+J (0x0A) is a
    // universal fallback — we disable icrnl in raw mode so it's distinct
    // from Enter (0x0D).
    if (isEnter &&
        (event.isShiftPressed ||
            event.isControlPressed ||
            event.isAltPressed)) {
      if (component.maxLines != 1) {
        _insertText('\n');
      }
      return true;
    } else if (event.matches(LogicalKey.keyJ, ctrl: true)) {
      if (component.maxLines != 1) {
        _insertText('\n');
      }
      return true;
    } else if (isEnter) {
      // Plain Enter submits in all fields (both single-line and multi-line)
      component.onEditingComplete?.call();
      component.onSubmitted?.call(_controller.text);
      return true;
    } else if (key == LogicalKey.backspace && event.isControlPressed) {
      _deleteWordBackward();
      return true;
    } else if (key == LogicalKey.backspace && event.isAltPressed) {
      // Alt+Backspace is the readline / macOS / VS Code convention for
      // "delete word backward". It's the most reliable cross-terminal
      // binding for word delete on Windows because Tabby + ConPTY (and
      // some other terminal emulators) strip the Ctrl modifier from
      // Ctrl+Backspace before it reaches ReadConsoleInputW, so the
      // Ctrl+Backspace case above can't fire.
      _deleteWordBackward();
      return true;
    } else if (event.matches(LogicalKey.keyW, ctrl: true)) {
      // Ctrl+W is the readline "unix-word-rubout" binding. Same
      // rationale as Alt+Backspace above: terminal-agnostic fallback
      // for word delete when the terminal strips Ctrl from Backspace.
      _deleteWordBackward();
      return true;
    } else if (key == LogicalKey.backspace) {
      _handleBackspace();
      return true;
    } else if (key == LogicalKey.delete && event.isControlPressed) {
      _deleteWordForward();
      return true;
    } else if (key == LogicalKey.delete && event.isAltPressed) {
      _deleteWordForward();
      return true;
    } else if (key == LogicalKey.keyD && event.isAltPressed) {
      _deleteWordForward();
      return true;
    } else if (key == LogicalKey.delete) {
      _handleDelete();
      return true;
    } else if (key == LogicalKey.arrowLeft &&
        event.isShiftPressed &&
        !event.isControlPressed &&
        !event.isAltPressed) {
      // Plain Shift+Arrow extends the selection by a single character.
      // Shift combined with Ctrl/Alt is handled by the word-move branches
      // below (Shift extends the word selection).
      _moveCursor(-1, true);
      return true;
    } else if (key == LogicalKey.arrowRight &&
        event.isShiftPressed &&
        !event.isControlPressed &&
        !event.isAltPressed) {
      _moveCursor(1, true);
      return true;
    } else if (key == LogicalKey.arrowLeft &&
        (event.isControlPressed || event.isAltPressed)) {
      // Word-level left. Ctrl+Arrow is the Linux/Windows readline
      // convention; Alt+Arrow (Option+Arrow on macOS) is the macOS
      // convention — Ctrl+< / Ctrl+> are bound to Mission Control
      // there, so the user can't use them. Accepting both keeps the
      // binding identical across platforms. Shift extends the
      // selection by a word.
      _moveCursorByWord(-1, event.isShiftPressed);
      return true;
    } else if (key == LogicalKey.arrowRight &&
        (event.isControlPressed || event.isAltPressed)) {
      _moveCursorByWord(1, event.isShiftPressed);
      return true;
    } else if (key == LogicalKey.arrowUp &&
        event.isShiftPressed &&
        component.maxLines != 1) {
      if (event.isControlPressed) return false;
      _moveCursorVertically(-1, true);
      return true;
    } else if (key == LogicalKey.arrowDown &&
        event.isShiftPressed &&
        component.maxLines != 1) {
      if (event.isControlPressed) return false;
      _moveCursorVertically(1, true);
      return true;
    } else if (key == LogicalKey.arrowLeft) {
      _moveCursor(-1, false);
      return true;
    } else if (key == LogicalKey.arrowRight) {
      _moveCursor(1, false);
      return true;
    } else if (key == LogicalKey.arrowUp && component.maxLines != 1) {
      if (event.isControlPressed) return false;
      _moveCursorVertically(-1, false);
      return true;
    } else if (key == LogicalKey.arrowDown && component.maxLines != 1) {
      if (event.isControlPressed) return false;
      _moveCursorVertically(1, false);
      return true;
    } else if (key == LogicalKey.home) {
      _moveCursorToStart();
      return true;
    } else if (key == LogicalKey.end) {
      _moveCursorToEnd();
      return true;
    } else if (event.matches(LogicalKey.keyA, ctrl: true) ||
        event.matches(LogicalKey.keyA, meta: true)) {
      _selectAll();
      return true;
    } else if (event.matches(LogicalKey.keyC, ctrl: true) ||
        event.matches(LogicalKey.keyC, meta: true)) {
      _copy();
      return true;
    } else if (event.matches(LogicalKey.keyX, ctrl: true) ||
        event.matches(LogicalKey.keyX, meta: true)) {
      _cut();
      return true;
    } else if (event.matches(LogicalKey.keyV, ctrl: true) ||
        event.matches(LogicalKey.keyV, meta: true)) {
      _paste();
      return true;
    } else if (event.matches(LogicalKey.keyW, ctrl: true)) {
      // Cmd+W is "close window" on macOS — keep this ctrl-only.
      _deleteWordBackward();
      return true;
    } else if (event.matches(LogicalKey.keyT, ctrl: true)) {
      // Cmd+T is "new tab" on macOS — keep this ctrl-only.
      _transposeCharacters();
      return true;
    } else {
      // Use the character from the event if available (supports UTF-8 and composed characters)
      if (event.character != null) {
        _insertText(event.character!);
        return true;
      }

      // Fallback to getting character from key
      final char = _getCharacterFromKey(key);
      if (char != null) {
        _insertText(char);
        return true;
      }
    }

    return false;
  }

  String? _getCharacterFromKey(LogicalKey key) {
    // Map common printable keys to characters
    if (key == LogicalKey.space) return ' ';
    if (key == LogicalKey.exclamation) return '!';
    if (key == LogicalKey.quoteDbl) return '"';
    if (key == LogicalKey.numberSign) return '#';
    if (key == LogicalKey.dollar) return '\$';
    if (key == LogicalKey.percent) return '%';
    if (key == LogicalKey.ampersand) return '&';
    if (key == LogicalKey.quoteSingle) return '\'';
    if (key == LogicalKey.parenthesisLeft) return '(';
    if (key == LogicalKey.parenthesisRight) return ')';
    if (key == LogicalKey.asterisk) return '*';
    if (key == LogicalKey.add) return '+';
    if (key == LogicalKey.comma) return ',';
    if (key == LogicalKey.minus) return '-';
    if (key == LogicalKey.period) return '.';
    if (key == LogicalKey.slash) return '/';
    if (key == LogicalKey.colon) return ':';
    if (key == LogicalKey.semicolon) return ';';
    if (key == LogicalKey.less) return '<';
    if (key == LogicalKey.equal) return '=';
    if (key == LogicalKey.greater) return '>';
    if (key == LogicalKey.question) return '?';
    if (key == LogicalKey.at) return '@';
    if (key == LogicalKey.bracketLeft) return '[';
    if (key == LogicalKey.backslash) return '\\';
    if (key == LogicalKey.bracketRight) return ']';
    if (key == LogicalKey.caret) return '^';
    if (key == LogicalKey.underscore) return '_';
    if (key == LogicalKey.backquote) return '`';
    if (key == LogicalKey.braceLeft) return '{';
    if (key == LogicalKey.bar) return '|';
    if (key == LogicalKey.braceRight) return '}';
    if (key == LogicalKey.tilde) return '~';

    // Digits
    if (key == LogicalKey.digit0) return '0';
    if (key == LogicalKey.digit1) return '1';
    if (key == LogicalKey.digit2) return '2';
    if (key == LogicalKey.digit3) return '3';
    if (key == LogicalKey.digit4) return '4';
    if (key == LogicalKey.digit5) return '5';
    if (key == LogicalKey.digit6) return '6';
    if (key == LogicalKey.digit7) return '7';
    if (key == LogicalKey.digit8) return '8';
    if (key == LogicalKey.digit9) return '9';

    // Letters - character is already provided in the event, this is just fallback
    // Note: This method is rarely used now since event.character is preferred

    return null;
  }

  void _insertText(String char) {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    // where text may have been modified externally (e.g., by onChanged callback)
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    // Check if we're at max length
    if (component.maxLength != null) {
      final currentLength = text.characters.length;
      final insertLength = char.characters.length;
      final deleteLength = isCollapsed ? 0 : (clampedEnd - clampedStart);

      if (currentLength - deleteLength + insertLength > component.maxLength!) {
        return;
      }
    }

    // Check max lines for multi-line fields
    if (component.maxLines != null &&
        component.maxLines! > 1 &&
        char.contains('\n')) {
      final currentLines = text.split('\n').length;
      final newLines = char.split('\n').length - 1;

      if (currentLines + newLines > component.maxLines!) {
        return;
      }
    }

    String newText;
    int newOffset;

    if (!isCollapsed) {
      // Replace selected text
      newText =
          text.substring(0, clampedStart) + char + text.substring(clampedEnd);
      newOffset = clampedStart + char.length;
    } else {
      // Insert at cursor position
      newText = text.substring(0, clampedExtentOffset) +
          char +
          text.substring(clampedExtentOffset);
      newOffset = clampedExtentOffset + char.length;
    }

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newOffset);

    // Reset target column after text modification
    _renderTextField?.resetTargetColumn();
  }

  void _handleBackspace() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _controller.text =
          text.substring(0, clampedStart) + text.substring(clampedEnd);
      _controller.selection = TextSelection.collapsed(offset: clampedStart);
    } else if (clampedExtentOffset > 0) {
      // Delete the grapheme cluster before cursor
      final textBefore = text.substring(0, clampedExtentOffset);
      final textAfter = text.substring(clampedExtentOffset);

      // Use grapheme clusters to delete the entire cluster
      final graphemes = textBefore.characters;
      if (graphemes.isNotEmpty) {
        final newTextBefore = graphemes.skipLast(1).toString();
        _controller.text = newTextBefore + textAfter;
        _controller.selection =
            TextSelection.collapsed(offset: newTextBefore.length);
      }
    }
  }

  void _handleDelete() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _controller.text =
          text.substring(0, clampedStart) + text.substring(clampedEnd);
      _controller.selection = TextSelection.collapsed(offset: clampedStart);
    } else if (clampedExtentOffset < textLength) {
      // Delete the grapheme cluster after cursor
      final textBefore = text.substring(0, clampedExtentOffset);
      final textAfter = text.substring(clampedExtentOffset);

      // Use grapheme clusters to delete the entire cluster
      final graphemesAfter = textAfter.characters;
      if (graphemesAfter.isNotEmpty) {
        final newTextAfter = graphemesAfter.skip(1).toString();
        final cursorPos = clampedExtentOffset;
        _controller.text = textBefore + newTextAfter;
        _controller.selection = TextSelection.collapsed(offset: cursorPos);
      }
    }
  }

  void _moveCursor(int delta, bool extendSelection) {
    _renderTextField?.moveCursorHorizontally(delta, extendSelection);
  }

  void _moveCursorByWord(int direction, bool extendSelection) {
    final provider = component.wordBoundaryProvider;
    if (provider != null) {
      final text = _controller.text;
      final currentOffset = _controller.selection.extentOffset;
      final newOffset = direction < 0
          ? provider.previousBoundary(text, currentOffset)
          : provider.nextBoundary(text, currentOffset);
      final newSelection = extendSelection
          ? _controller.selection.copyWith(extentOffset: newOffset)
          : TextSelection.collapsed(offset: newOffset);
      if (newSelection != _controller.selection) {
        _controller.selection = newSelection;
      }
      return;
    }
    _renderTextField?.moveCursorByWord(direction, extendSelection);
  }

  void _deleteWordBackward() {
    final text = _controller.text;
    final selection = _controller.selection;

    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      _controller.text =
          text.substring(0, clampedStart) + text.substring(clampedEnd);
      _controller.selection = TextSelection.collapsed(offset: clampedStart);
      return;
    }

    if (clampedExtentOffset == 0) return;

    final int start;
    final provider = component.wordBoundaryProvider;
    if (provider != null) {
      start = provider.previousBoundary(text, clampedExtentOffset);
    } else {
      start = _defaultPreviousWordBoundary(text, clampedExtentOffset);
    }

    _controller.text =
        text.substring(0, start) + text.substring(clampedExtentOffset);
    _controller.selection = TextSelection.collapsed(offset: start);
  }

  void _deleteWordForward() {
    final text = _controller.text;
    final selection = _controller.selection;

    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      _controller.text =
          text.substring(0, clampedStart) + text.substring(clampedEnd);
      _controller.selection = TextSelection.collapsed(offset: clampedStart);
      return;
    }

    if (clampedExtentOffset >= textLength) return;

    final int end;
    final provider = component.wordBoundaryProvider;
    if (provider != null) {
      end = provider.nextBoundary(text, clampedExtentOffset);
    } else {
      end = _defaultNextWordBoundary(text, clampedExtentOffset);
    }

    _controller.text =
        text.substring(0, clampedExtentOffset) + text.substring(end);
    _controller.selection =
        TextSelection.collapsed(offset: clampedExtentOffset);
  }

  static int _defaultPreviousWordBoundary(String text, int offset) {
    int start = offset;
    while (start > 0 && _isSpace(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
      start--;
    }
    return start;
  }

  static int _defaultNextWordBoundary(String text, int offset) {
    final len = text.length;
    int end = offset;
    while (end < len && !_isSpace(text.codeUnitAt(end))) {
      end++;
    }
    while (end < len && _isSpace(text.codeUnitAt(end))) {
      end++;
    }
    return end;
  }

  static bool _isSpace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }

  void _transposeCharacters() {
    final text = _controller.text;
    final selection = _controller.selection;

    if (selection.extentOffset == 0 || text.length < 2) return;

    final chars = text.characters.toList();
    int pos = selection.extentOffset;

    // Find character positions
    int charCount = 0;
    int charIndex = 0;
    for (int i = 0; i < chars.length; i++) {
      if (charCount >= pos) {
        charIndex = i;
        break;
      }
      charCount += chars[i].length;
    }

    if (charIndex >= chars.length) {
      charIndex = chars.length - 1;
    }

    // Transpose characters
    if (charIndex > 0) {
      final temp = chars[charIndex - 1];
      chars[charIndex - 1] =
          chars[charIndex == chars.length ? charIndex - 1 : charIndex];
      chars[charIndex == chars.length ? charIndex - 1 : charIndex] = temp;

      _controller.text = chars.join();

      // Move cursor forward if not at end
      if (pos < text.length) {
        _moveCursor(1, false);
      }
    }
  }

  void _moveCursorVertically(int direction, bool extendSelection) {
    _renderTextField?.moveCursorVertically(direction, extendSelection);
  }

  void _moveCursorToStart() {
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _renderTextField?.resetTargetColumn();
  }

  void _moveCursorToEnd() {
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _renderTextField?.resetTargetColumn();
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _copy() {
    // Copy selected text to clipboard using OSC 52
    if (!_controller.selection.isCollapsed) {
      final text = _controller.text;
      final selection = _controller.selection;

      // Clamp selection offsets to valid range to handle race conditions
      final textLength = text.length;
      final clampedStart = selection.start.clamp(0, textLength);
      final clampedEnd = selection.end.clamp(0, textLength);

      if (clampedStart < clampedEnd) {
        final selectedText = text.substring(clampedStart, clampedEnd);
        ClipboardManager.copy(selectedText);
      }
    }
  }

  void _cut() {
    // Copy selected text to clipboard and then delete it
    if (!_controller.selection.isCollapsed) {
      final text = _controller.text;
      final selection = _controller.selection;

      // Clamp selection offsets to valid range to handle race conditions
      final textLength = text.length;
      final clampedStart = selection.start.clamp(0, textLength);
      final clampedEnd = selection.end.clamp(0, textLength);

      if (clampedStart < clampedEnd) {
        final selectedText = text.substring(clampedStart, clampedEnd);

        // Copy to clipboard using OSC 52
        ClipboardManager.copy(selectedText);

        // Delete the selected text
        _controller.text =
            text.substring(0, clampedStart) + text.substring(clampedEnd);
        _controller.selection = TextSelection.collapsed(offset: clampedStart);
      }
    }
  }

  void _paste() {
    // Prefer framework-stashed paste text (set by TerminalBinding
    // for a PasteInputEvent) over the system clipboard, so IME-
    // committed text on macOS — which the IME wraps in bracketed-
    // paste markers — doesn't clobber the user's clipboard. Real
    // Ctrl+V has no pending text and falls through to the
    // clipboard as before.
    final pending = NoctermBinding.instance.consumePendingPasteText();
    if (pending != null && pending.isNotEmpty) {
      _insertClipboardText(pending);
      return;
    }
    _pasteFromClipboard();
  }

  /// Resolve the clipboard text and insert it.
  ///
  /// Sources, in priority order:
  ///  1. An OSC 52 query to the terminal ([TerminalBinding.readClipboardViaOsc52])
  ///     — reads the real system clipboard with no external tool, on terminals
  ///     that answer it (Ghostty, WezTerm, kitty, …).
  ///  2. The host-provided tool reader ([NoctermBinding.systemClipboardTextReader])
  ///     — e.g. wl-paste/xclip/pbpaste, for terminals without OSC 52 reads.
  ///  3. The session-internal buffer ([ClipboardManager.paste]) — last resort.
  Future<void> _pasteFromClipboard() async {
    String? text;
    try {
      text = await TerminalBinding.readClipboardViaOsc52();
    } catch (_) {
      text = null;
    }
    if (text == null) {
      final reader = NoctermBinding.systemClipboardTextReader;
      if (reader != null) {
        try {
          text = await reader();
        } catch (_) {
          text = null;
        }
      }
    }
    text ??= ClipboardManager.paste();
    if (text != null && text.isNotEmpty) {
      _insertClipboardText(text);
    }
  }

  void _insertClipboardText(String clipboardText) {
    if (clipboardText.isNotEmpty) {
      if (component.maxLines == 1) {
        // Single-line field: replace all newlines/carriage returns with spaces
        // This prevents accidentally submitting the form when pasting multi-line text
        clipboardText = clipboardText.replaceAll(RegExp(r'[\r\n]+'), ' ');
      } else {
        // Multi-line field: preserve newlines but normalize to \n only
        // Replace Windows-style \r\n and old Mac-style \r with Unix-style \n
        // Note: Pasting via Ctrl+V processes the text as a single string insertion,
        // so newlines won't trigger Enter key events or form submission
        clipboardText = clipboardText.replaceAll(RegExp(r'\r\n'), '\n');
        clipboardText = clipboardText.replaceAll(RegExp(r'\r'), '\n');
      }

      // Call onPaste callback if provided
      // If callback returns true, the paste was handled externally - skip default insertion
      final handled = component.onPaste?.call(clipboardText) ?? false;
      if (!handled) {
        _insertText(clipboardText);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final decoration = component.decoration ?? const InputDecoration();

    return Focusable(
      focused: component.focused,
      autofocus: component.focused && component.enabled,
      disabled: !component.enabled,
      onKeyEvent: _handleKeyEvent,
      child: Builder(builder: (context) {
        final isFocused = Focus.of(context);

        final actualText = _controller.text;
        String displayText = actualText;
        if (component.obscureText) {
          displayText = component.obscuringCharacter * displayText.length;
        }

        if (component.maxLines == 1 && component.width != null) {
          final padding = decoration.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 1);
          final horizontalPadding = padding.left + padding.right;
          final borderWidth = decoration.border != null ? 2.0 : 0.0;
          final maxVisibleWidth =
              (component.width! - borderWidth - horizontalPadding - 1).toInt();

          if (maxVisibleWidth > 0 && _viewOffset < displayText.length) {
            final graphemes = displayText.characters.toList();

            if (_viewOffset < graphemes.length) {
              int startIdx = _viewOffset;
              int endIdx = _viewOffset;
              int visualWidth = 0;

              while (
                  endIdx < graphemes.length && visualWidth < maxVisibleWidth) {
                final graphemeWidth =
                    UnicodeWidth.graphemeWidth(graphemes[endIdx]);
                if (visualWidth + graphemeWidth <= maxVisibleWidth) {
                  visualWidth += graphemeWidth;
                  endIdx++;
                } else {
                  break;
                }
              }

              displayText = graphemes.sublist(startIdx, endIdx).join();
            } else {
              displayText = '';
            }
          }
        }

        final theme = TuiTheme.of(context);
        final effectiveCursorColor = component.cursorColor ?? theme.primary;
        final effectiveSelectionColor =
            component.selectionColor ?? theme.primary.withOpacity(0.4);

        Component content = _TextFieldContent(
          text: actualText,
          placeholder: component.placeholder,
          style: component.style,
          placeholderStyle: component.placeholderStyle,
          selection: _controller.selection,
          viewOffset: _viewOffset,
          cursorVisible: _cursorVisible && isFocused && component.showCursor,
          cursorColor: effectiveCursorColor,
          cursorStyle: component.cursorStyle,
          selectionColor: effectiveSelectionColor,
          textAlign: component.textAlign,
          maxLines: component.maxLines,
          isFocused: isFocused,
          obscureText: component.obscureText,
          obscuringCharacter: component.obscuringCharacter,
          onSelectionChange: _handleSelectionChangeFromRenderObject,
          onRenderObjectCreate: (renderObject) {
            _renderTextField = renderObject;
          },
          styleSegments: component.styleSegments,
        );

        if (decoration.border != null || decoration.fillColor != null) {
          content = Container(
            width: component.width,
            height:
                component.height ?? (component.maxLines ?? 1).toDouble() + 2,
            padding: decoration.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              border: isFocused
                  ? decoration.focusedBorder ?? decoration.border
                  : decoration.border,
              color: decoration.fillColor,
            ),
            child: content,
          );
        }

        return content;
      }),
    );
  }
}

/// Internal component for rendering text field content
class _TextFieldContent extends SingleChildRenderObjectComponent {
  const _TextFieldContent({
    required this.text,
    this.placeholder,
    this.style,
    this.placeholderStyle,
    required this.selection,
    required this.viewOffset,
    required this.cursorVisible,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.selectionColor,
    required this.textAlign,
    this.maxLines,
    required this.isFocused,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.onSelectionChange,
    this.onRenderObjectCreate,
    this.styleSegments,
  });

  final String text;
  final String? placeholder;
  final TextStyle? style;
  final TextStyle? placeholderStyle;
  final TextSelection selection;
  final int viewOffset;
  final bool cursorVisible;
  final Color? cursorColor;
  final CursorStyle cursorStyle;
  final Color? selectionColor;
  final TextAlign textAlign;
  final int? maxLines;
  final bool isFocused;
  final bool obscureText;
  final String obscuringCharacter;
  final void Function(TextSelection)? onSelectionChange;
  final void Function(RenderTextField)? onRenderObjectCreate;
  final List<StyledTextSegment>? styleSegments;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final renderObject = RenderTextField(
      text: text,
      placeholder: placeholder,
      style: style,
      placeholderStyle: placeholderStyle,
      selection: selection,
      viewOffset: viewOffset,
      cursorVisible: cursorVisible,
      cursorColor: cursorColor,
      cursorStyle: cursorStyle,
      selectionColor: selectionColor,
      textAlign: textAlign,
      maxLines: maxLines,
      isFocused: isFocused,
      obscureText: obscureText,
      obscuringCharacter: obscuringCharacter,
      onSelectionChange: onSelectionChange,
      styleSegments: styleSegments,
    );
    onRenderObjectCreate?.call(renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(BuildContext context, RenderTextField renderObject) {
    renderObject
      ..text = text
      ..placeholder = placeholder
      ..style = style
      ..placeholderStyle = placeholderStyle
      ..selection = selection
      ..viewOffset = viewOffset
      ..cursorVisible = cursorVisible
      ..cursorColor = cursorColor
      ..cursorStyle = cursorStyle
      ..selectionColor = selectionColor
      ..textAlign = textAlign
      ..maxLines = maxLines
      ..isFocused = isFocused
      ..obscureText = obscureText
      ..obscuringCharacter = obscuringCharacter
      ..styleSegments = styleSegments;
  }
}

/// Render object for text field
class RenderTextField extends RenderObject with MouseTrackerAnnotationProvider {
  RenderTextField({
    required String text,
    String? placeholder,
    TextStyle? style,
    TextStyle? placeholderStyle,
    required TextSelection selection,
    required int viewOffset,
    required bool cursorVisible,
    Color? cursorColor,
    CursorStyle cursorStyle = CursorStyle.block,
    Color? selectionColor,
    required TextAlign textAlign,
    int? maxLines,
    required bool isFocused,
    bool obscureText = false,
    String obscuringCharacter = '•',
    this.onSelectionChange,
    List<StyledTextSegment>? styleSegments,
  })  : _text = text,
        _placeholder = placeholder,
        _style = style,
        _placeholderStyle = placeholderStyle,
        _selection = selection,
        _viewOffset = viewOffset,
        _cursorVisible = cursorVisible,
        _cursorColor = cursorColor,
        _cursorStyle = cursorStyle,
        _selectionColor = selectionColor,
        _textAlign = textAlign,
        _maxLines = maxLines,
        _isFocused = isFocused,
        _obscureText = obscureText,
        _obscuringCharacter = obscuringCharacter,
        _styleSegments = styleSegments {
    _updateMouseAnnotation();
  }

  String _text;
  String? _placeholder;
  TextStyle? _style;
  TextStyle? _placeholderStyle;
  TextSelection _selection;
  int _viewOffset;
  bool _cursorVisible;
  Color? _cursorColor;
  CursorStyle _cursorStyle;
  Color? _selectionColor;
  TextAlign _textAlign;

  /// Optional per-character styled segments for rich text rendering.
  /// When provided, text is painted segment-by-segment with each
  /// segment's own style (including backgroundColor). The base
  /// [_style] is used as a fallback for segments that don't specify
  /// a color.
  List<StyledTextSegment>? _styleSegments;
  List<StyledTextSegment>? get styleSegments => _styleSegments;
  set styleSegments(List<StyledTextSegment>? value) {
    if (_styleSegments != value) {
      _styleSegments = value;
      _styledLines = null;
      markNeedsPaint();
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;
  int? _maxLines;
  bool _isFocused;
  bool _obscureText;
  String _obscuringCharacter;

  // Callback for selection changes
  final void Function(TextSelection)? onSelectionChange;

  // Store the layout result for proper Unicode rendering
  TextLayoutResult? _layoutResult;

  // Cache of styled lines — computed from _styleSegments + _layoutResult.
  // Null when styleSegments is null (original single-style behavior).
  List<List<StyledTextSegment>>? _styledLines;

  // Track target visual column for vertical movement
  int? _targetVisualColumn;

  // Mouse interaction state
  MouseTrackerAnnotation? _mouseAnnotation;
  bool _isLeftButtonPressed = false;
  int? _dragAnchorOffset;
  DateTime? _lastClickTime;
  int? _lastClickOffset;
  static const _doubleClickTimeout = Duration(milliseconds: 500);

  @override
  MouseTrackerAnnotation? get annotation => _mouseAnnotation;

  set text(String value) {
    if (_text != value) {
      _text = value;
      _styledLines = null;
      markNeedsLayout();
    }
  }

  set placeholder(String? value) {
    if (_placeholder != value) {
      _placeholder = value;
      markNeedsPaint();
    }
  }

  set style(TextStyle? value) {
    if (_style != value) {
      _style = value;
      markNeedsPaint();
    }
  }

  set placeholderStyle(TextStyle? value) {
    if (_placeholderStyle != value) {
      _placeholderStyle = value;
      markNeedsPaint();
    }
  }

  set selection(TextSelection value) {
    if (_selection != value) {
      _selection = value;
      markNeedsPaint();
    }
  }

  set viewOffset(int value) {
    if (_viewOffset != value) {
      _viewOffset = value;
      markNeedsPaint();
    }
  }

  set cursorVisible(bool value) {
    if (_cursorVisible != value) {
      _cursorVisible = value;
      markNeedsPaint();
    }
  }

  set cursorColor(Color? value) {
    if (_cursorColor != value) {
      _cursorColor = value;
      markNeedsPaint();
    }
  }

  set cursorStyle(CursorStyle value) {
    if (_cursorStyle != value) {
      _cursorStyle = value;
      markNeedsPaint();
    }
  }

  set selectionColor(Color? value) {
    if (_selectionColor != value) {
      _selectionColor = value;
      markNeedsPaint();
    }
  }

  set textAlign(TextAlign value) {
    if (_textAlign != value) {
      _textAlign = value;
      markNeedsPaint();
    }
  }

  set maxLines(int? value) {
    if (_maxLines != value) {
      _maxLines = value;
      markNeedsLayout();
    }
  }

  set isFocused(bool value) {
    if (_isFocused != value) {
      _isFocused = value;
      markNeedsPaint();
    }
  }

  set obscureText(bool value) {
    if (_obscureText != value) {
      _obscureText = value;
      markNeedsLayout();
    }
  }

  set obscuringCharacter(String value) {
    if (_obscuringCharacter != value) {
      _obscuringCharacter = value;
      if (_obscureText) {
        markNeedsLayout();
      }
    }
  }

  /// Move cursor horizontally
  void moveCursorHorizontally(int direction, bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorHorizontally(
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor vertically
  void moveCursorVertically(int direction, bool extendSelection) {
    if (_layoutResult == null) return;

    // Get current position if we don't have a target column
    if (_targetVisualColumn == null) {
      final currentPos = CursorMovement.getCursorPosition(
        layoutResult: _layoutResult!,
        text: _text,
        cursorOffset: _selection.extentOffset,
      );
      _targetVisualColumn = currentPos.visualColumn;
    }

    final newOffset = CursorMovement.moveCursorVertically(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
      targetVisualColumn: _targetVisualColumn!,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor by word
  void moveCursorByWord(int direction, bool extendSelection) {
    final newOffset = CursorMovement.moveCursorByWord(
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor to start of current line
  void moveCursorToLineStart(bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorToLineStart(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor to end of current line
  void moveCursorToLineEnd(bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorToLineEnd(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Reset target visual column (used when text changes)
  void resetTargetColumn() {
    _targetVisualColumn = null;
  }

  /// Returns the terminal screen coordinates (column, row) of the text cursor,
  /// or null if the cursor position cannot be determined or the field is not focused.
  ///
  /// This is used by the binding layer to position the physical terminal cursor
  /// so that IME (Input Method Editor) composition windows (e.g. Chinese Pinyin)
  /// appear at the correct location instead of flickering across the screen
  /// during differential rendering.
  ///
  /// The position is returned even when the cursor is in its blink-off phase
  /// so the IME window stays anchored at the correct location.
  Offset? getImeCursorPosition() {
    if (!_isFocused || _layoutResult == null) {
      return null;
    }

    final lines = _layoutResult!.lines;

    if (_text.isEmpty && _placeholder == null) {
      // Empty field - cursor at beginning
      final globalOffset = _globalPaintOffset;
      return Offset(globalOffset.dx, globalOffset.dy);
    }

    // Find which line the cursor is on (same logic as _paintCursor)
    int charCount = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length;

      if (charCount + lineLength >= _selection.extentOffset ||
          i == lines.length - 1) {
        final positionInLine =
            (_selection.extentOffset - charCount).clamp(0, lineLength);

        // Calculate visual position using Unicode width
        final textBeforeCursor = line.substring(0, positionInLine);
        final visualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

        // Combine global offset with cursor position within the field
        final globalOffset = _globalPaintOffset;
        return Offset(
          globalOffset.dx + visualColumn,
          globalOffset.dy + i,
        );
      }

      charCount += lineLength;
      // Only add 1 for actual newline characters, not wrapped lines.
      // Check the character right after this line's content in the
      // original text.
      if (i < lines.length - 1 &&
          charCount < _text.length &&
          _text[charCount] == '\n') {
        charCount++;
      }
    }

    return null;
  }

  // --- Mouse interaction ---

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _mouseAnnotation?.validForMouseTracker = true;
  }

  @override
  void detach() {
    _mouseAnnotation?.validForMouseTracker = false;
    super.detach();
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    if (!bounds.contains(position)) return false;

    if (result is MouseHitTestResult && _mouseAnnotation != null) {
      result.addWithPosition(target: this, localPosition: position);
    }

    return hitTestSelf(position);
  }

  void _updateMouseAnnotation() {
    _mouseAnnotation = MouseTrackerAnnotation(
      onEnter: (event) {
        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown) {
            _isLeftButtonPressed = false;
          }
        }
      },
      onExit: (event) {
        if (_dragAnchorOffset != null) {
          // End drag when leaving the region, matching SelectionArea behavior.
          _handlePointerMove(event);
          _handlePointerUp(event);
        }
        _isLeftButtonPressed = false;
      },
      onHover: (event) {
        if (event.isWheel) {
          return;
        }

        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown && _isLeftButtonPressed) {
            _isLeftButtonPressed = false;
            _handlePointerUp(event);
          } else if (leftDown && _isLeftButtonPressed) {
            _handlePointerMove(event);
          }
        }
      },
      renderObject: this,
    );
  }

  Offset get _globalPaintOffset {
    double x = 0, y = 0;
    RenderObject? node = this;
    while (node != null) {
      if (node.parentData is BoxParentData) {
        final pd = node.parentData as BoxParentData;
        x += pd.offset.dx;
        y += pd.offset.dy;
      }
      node = node.parent;
    }
    return Offset(x, y);
  }

  int _getCharIndexFromMousePosition(int mouseX, int mouseY) {
    final gpo = _globalPaintOffset;
    final localX = mouseX - gpo.dx;
    final localY = mouseY - gpo.dy;

    // For obscured text, the layout lines contain obscuring characters (e.g. '•')
    // which may have different byte lengths than the real text. We must pass the
    // obscured text so character index computation matches the visual layout.
    final textForHitTest =
        _obscureText ? _obscuringCharacter * _text.length : _text;

    final charIndex = selection_utils.getCharacterIndexAtLocalPosition(
      localPos: Offset(localX, localY),
      text: textForHitTest,
      lines: _layoutResult?.lines ?? const [],
    );

    // For single-line fields with horizontal scrolling, the visible text starts
    // at _viewOffset but the layout contains the full text. The local x=0
    // corresponds to the character at _viewOffset, so we must add the offset.
    if (_maxLines == 1 && _viewOffset > 0) {
      return (charIndex + _viewOffset).clamp(0, _text.length);
    }

    return charIndex;
  }

  void _handlePointerDown(MouseEvent event) {
    if (_layoutResult == null) return;

    final charIndex = _getCharIndexFromMousePosition(event.x, event.y);
    final now = DateTime.now();

    // Double-click detection
    if (_lastClickTime != null &&
        _lastClickOffset != null &&
        now.difference(_lastClickTime!) < _doubleClickTimeout &&
        (_lastClickOffset! - charIndex).abs() <= 1) {
      _selectWordAt(charIndex);
      _lastClickTime = null;
      _lastClickOffset = null;
      _dragAnchorOffset = null;
      return;
    }

    // Single click - position cursor
    _lastClickTime = now;
    _lastClickOffset = charIndex;
    _dragAnchorOffset = charIndex;

    final newSelection = TextSelection.collapsed(offset: charIndex);
    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  void _handlePointerMove(MouseEvent event) {
    if (_dragAnchorOffset == null || _layoutResult == null) return;

    final charIndex = _getCharIndexFromMousePosition(event.x, event.y);

    final newSelection = TextSelection(
      baseOffset: _dragAnchorOffset!,
      extentOffset: charIndex,
    );

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  void _handlePointerUp(MouseEvent event) {
    _dragAnchorOffset = null;
  }

  void _selectWordAt(int offset) {
    if (_text.isEmpty) return;
    final clampedOffset = offset.clamp(0, _text.length - 1);

    int start = clampedOffset;
    int end = clampedOffset;

    while (start > 0 && !_isWordBoundary(_text[start - 1])) {
      start--;
    }
    while (end < _text.length && !_isWordBoundary(_text[end])) {
      end++;
    }

    if (start == end) {
      // Double-click on whitespace/punctuation: just position cursor there
      final newSelection = TextSelection.collapsed(offset: clampedOffset);
      if (newSelection != _selection) {
        _selection = newSelection;
        _targetVisualColumn = null;
        onSelectionChange?.call(newSelection);
        markNeedsPaint();
      }
      return;
    }

    final newSelection = TextSelection(baseOffset: start, extentOffset: end);
    _selection = newSelection;
    _targetVisualColumn = null;
    onSelectionChange?.call(newSelection);
    markNeedsPaint();
  }

  static bool _isWordBoundary(String char) {
    // Treat whitespace and common punctuation as word boundaries
    const boundaries = {
      ' ',
      '\t',
      '\n',
      '\r',
      '.',
      ',',
      ';',
      ':',
      '!',
      '?',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '<',
      '>',
      '"',
      "'",
      '/',
      '\\',
      '|',
      '-',
      '+',
      '=',
      '*',
      '&',
      '^',
      '%',
      '#',
      '@',
      '~',
      '`',
    };
    return boundaries.contains(char);
  }

  @override
  void performLayout() {
    // Use TextLayoutEngine for proper Unicode text wrapping
    String textToLayout =
        _text.isEmpty && _placeholder != null ? _placeholder! : _text;

    // Apply text obscuring if needed
    if (_obscureText && _text.isNotEmpty) {
      textToLayout = _obscuringCharacter * _text.length;
    }

    // Reserve 1 column for the cursor block to be displayed within bounds
    // This ensures the cursor doesn't appear to go "into the wall" at line ends
    final availableWidth =
        constraints.maxWidth.isFinite ? constraints.maxWidth.toInt() : 80;
    final maxWidth = (availableWidth - 1)
        .clamp(1, double.infinity)
        .toInt(); // Reserve space for cursor

    final config = TextLayoutConfig(
      softWrap: _maxLines != 1, // Enable wrapping for multi-line fields
      overflow: TextOverflow.clip,
      textAlign: _textAlign,
      maxLines: _maxLines,
      maxWidth: maxWidth,
    );

    _layoutResult = TextLayoutEngine.layout(textToLayout, config);

    // Size based on actual layout result
    final actualHeight = _layoutResult!.actualHeight.toDouble();
    size = constraints.constrain(Size(
      constraints.maxWidth,
      actualHeight,
    ));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);

    if (_layoutResult == null) return;

    final textStyle = _text.isEmpty && _placeholder != null
        ? (_placeholderStyle ?? TextStyle(color: Colors.gray))
        : (_style ?? const TextStyle());

    final lines = _layoutResult!.lines;
    final alignmentWidth = size.width.toInt();

    // Paint each line from the layout result
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Calculate horizontal offset based on text alignment
      final xOffset = offset.dx +
          TextLayoutEngine.calculateAlignmentOffset(
            line,
            alignmentWidth,
            _textAlign,
          );

      // Apply justification if needed
      String displayLine = line;
      if (_textAlign == TextAlign.justify && i < lines.length - 1) {
        displayLine = TextLayoutEngine.justifyLine(line, alignmentWidth,
            isLastLine: false);
      }

      if (_styleSegments != null) {
        _paintLineWithSegments(
            canvas, Offset(xOffset, offset.dy + i), displayLine, textStyle, i);
      } else {
        _paintLineWithSelection(
            canvas, Offset(xOffset, offset.dy + i), displayLine, textStyle, i);
      }
    }

    // Paint cursor only for the focused field
    if (_cursorVisible && _isFocused) {
      _paintCursor(canvas, offset);
    }
  }

  /// Maps styled segments to the laid-out lines (similar to
  /// RenderParagraph._mapSegmentsToLines). Called lazily and cached
  /// in [_styledLines].
  List<List<StyledTextSegment>> _computeStyledLines() {
    if (_styledLines != null) return _styledLines!;
    if (_layoutResult == null || _styleSegments == null) return const [];

    final lines = _layoutResult!.lines;
    final List<List<StyledTextSegment>> result = [];

    // Flatten segments into (grapheme, style) pairs.
    final List<(String, TextStyle?)> charStyles = [];
    for (final segment in _styleSegments!) {
      for (final grapheme in segment.text.characters) {
        charStyles.add((grapheme, segment.style));
      }
    }

    int charIndex = 0;
    for (final line in lines) {
      final List<StyledTextSegment> lineSegments = [];
      // Skip newlines.
      while (
          charIndex < charStyles.length && charStyles[charIndex].$1 == '\n') {
        charIndex++;
      }
      final lineGraphemeCount = line.characters.length;
      int linePos = 0;
      while (linePos < lineGraphemeCount && charIndex < charStyles.length) {
        final (char, style) = charStyles[charIndex];
        if (char == '\n') {
          charIndex++;
          continue;
        }
        final currentStyle = style;
        final buffer = StringBuffer();
        while (charIndex < charStyles.length &&
            linePos < lineGraphemeCount &&
            charStyles[charIndex].$2 == currentStyle &&
            charStyles[charIndex].$1 != '\n') {
          buffer.write(charStyles[charIndex].$1);
          charIndex++;
          linePos++;
        }
        if (buffer.isNotEmpty) {
          lineSegments.add(StyledTextSegment(buffer.toString(), currentStyle));
        }
      }
      result.add(lineSegments);
    }

    _styledLines = result;
    return result;
  }

  /// Paints a line using per-segment styles. Selection highlighting
  /// is applied on top of the segment background.
  void _paintLineWithSegments(TerminalCanvas canvas, Offset offset,
      String line, TextStyle baseStyle, int lineIndex) {
    final styledLines = _computeStyledLines();
    if (lineIndex >= styledLines.length) {
      // Fallback: paint with base style.
      _paintLineWithSelection(canvas, offset, line, baseStyle, lineIndex);
      return;
    }

    final segments = styledLines[lineIndex];
    final lines = _layoutResult?.lines ?? const [];
    final hasSelection = !_selection.isCollapsed;

    // Calculate line start offset in the full text.
    final lineStartOffset = (lines.isNotEmpty && lineIndex < lines.length)
        ? selection_utils.lineStartOffsets(_text, lines)[lineIndex]
        : 0;
    final lineEndOffset = lineStartOffset + line.length;

    final selStart = hasSelection
        ? math.min(_selection.start, _selection.end)
        : 0;
    final selEnd =
        hasSelection ? math.max(_selection.start, _selection.end) : 0;
    final hasLineSelection =
        hasSelection && selEnd > lineStartOffset && selStart < lineEndOffset;

    final selectionColor = _selectionColor ?? Colors.blue;
    double currentX = offset.dx;
    int charOffset = lineStartOffset;

    for (final segment in segments) {
      final segText = segment.text;
      final segEnd = charOffset + segText.length;
      final segStyle = segment.style ?? baseStyle;

      if (hasLineSelection && selEnd > charOffset && selStart < segEnd) {
        final localSelStart = (selStart - charOffset).clamp(0, segText.length);
        final localSelEnd = (selEnd - charOffset).clamp(0, segText.length);

        // Before selection.
        if (localSelStart > 0) {
          final before = segText.substring(0, localSelStart);
          canvas.drawText(Offset(currentX, offset.dy), before, style: segStyle);
          currentX += UnicodeWidth.stringWidth(before);
        }
        // Selected portion.
        if (localSelStart < localSelEnd) {
          final selected = segText.substring(localSelStart, localSelEnd);
          final selStyle = segStyle.copyWith(
            color: selection_utils.foregroundForSelection(selectionColor),
            backgroundColor: selectionColor,
          );
          canvas.drawText(Offset(currentX, offset.dy), selected, style: selStyle);
          currentX += UnicodeWidth.stringWidth(selected);
        }
        // After selection.
        if (localSelEnd < segText.length) {
          final after = segText.substring(localSelEnd);
          canvas.drawText(Offset(currentX, offset.dy), after, style: segStyle);
          currentX += UnicodeWidth.stringWidth(after);
        }
      } else {
        canvas.drawText(Offset(currentX, offset.dy), segText, style: segStyle);
        currentX += UnicodeWidth.stringWidth(segText);
      }
      charOffset = segEnd;
    }
  }

  void _paintLineWithSelection(TerminalCanvas canvas, Offset offset,
      String line, TextStyle style, int lineIndex) {
    selection_utils.paintTextWithSelection(
      canvas: canvas,
      offset: offset,
      line: line,
      style: style,
      lineIndex: lineIndex,
      text: _text,
      lines: _layoutResult?.lines ?? const [],
      selectionStart: _selection.isCollapsed ? null : _selection.start,
      selectionEnd: _selection.isCollapsed ? null : _selection.end,
      selectionColor: _selectionColor ?? Colors.blue,
    );
  }

  void _paintCursor(TerminalCanvas canvas, Offset offset) {
    if (_layoutResult == null) return;

    final cursorColor = _cursorColor ?? Colors.white;
    final lines = _layoutResult!.lines;

    if (_text.isEmpty && _placeholder == null) {
      // Empty field - show cursor at beginning
      _drawCursorAtPosition(canvas, offset, ' ', 0, cursorColor);
      return;
    }

    // Find which line the cursor is on
    int charCount = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length;

      // Check if cursor is on this line
      if (charCount + lineLength >= _selection.extentOffset ||
          i == lines.length - 1) {
        final positionInLine =
            (_selection.extentOffset - charCount).clamp(0, lineLength);

        // Calculate visual position using Unicode width
        final textBeforeCursor = line.substring(0, positionInLine);
        final visualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

        final cursorOffset =
            offset + Offset(visualColumn.toDouble(), i.toDouble());

        // Get the character at cursor position (or space if at end)
        final charAtCursor =
            positionInLine < line.length ? line[positionInLine] : ' ';

        _drawCursorAtPosition(
            canvas, cursorOffset, charAtCursor, positionInLine, cursorColor);
        break;
      }

      charCount += lineLength;
      // Only add 1 for actual newline characters, not wrapped lines.
      // Check the character right after this line's content in the
      // original text — if it's a newline, the layout engine split
      // on it, so we must account for the extra byte.
      if (i < lines.length - 1 &&
          charCount < _text.length &&
          _text[charCount] == '\n') {
        charCount++;
      }
    }
  }

  void _drawCursorAtPosition(
    TerminalCanvas canvas,
    Offset position,
    String charUnderCursor,
    int cursorPos,
    Color cursorColor,
  ) {
    switch (_cursorStyle) {
      case CursorStyle.block:
        // Filled block - traditional terminal cursor
        final blockStyle = TextStyle(
          color: Colors.black,
          backgroundColor: cursorColor,
        );
        canvas.drawText(position, charUnderCursor, style: blockStyle);
        break;

      case CursorStyle.underline:
        // Draw the character with underline decoration
        final underlineStyle = TextStyle(
          color: _style?.color ?? Colors.white,
          backgroundColor: _style?.backgroundColor,
          decoration: TextDecoration.underline,
        );
        canvas.drawText(position, charUnderCursor, style: underlineStyle);
        break;

      case CursorStyle.blockOutline:
        // Draw block outline - invert the colors
        final outlineStyle = TextStyle(
          color: Colors.black,
          backgroundColor: cursorColor,
        );
        canvas.drawText(position, charUnderCursor, style: outlineStyle);
        break;
    }
  }
}

/// Input decoration for text fields
class InputDecoration {
  const InputDecoration({
    this.hintText,
    this.labelText,
    this.helperText,
    this.errorText,
    this.prefixText,
    this.suffixText,
    this.counter,
    this.filled,
    this.fillColor,
    this.border,
    this.focusedBorder,
    this.errorBorder,
    this.contentPadding,
  });

  final String? hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final String? prefixText;
  final String? suffixText;
  final Component? counter;
  final bool? filled;
  final Color? fillColor;
  final BoxBorder? border;
  final BoxBorder? focusedBorder;
  final BoxBorder? errorBorder;
  final EdgeInsets? contentPadding;
}

// TextAlign is now imported from text_layout_engine.dart

/// Cursor style options for the text field
enum CursorStyle {
  /// A filled block cursor (default terminal style)
  block,

  /// An underline cursor
  underline,

  /// An outlined block cursor
  blockOutline,
}

/// Type definitions
typedef ValueChanged<T> = void Function(T value);
