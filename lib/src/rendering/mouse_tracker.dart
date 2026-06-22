import 'dart:async';

import '../keyboard/mouse_event.dart';
import '../framework/framework.dart';
import 'mouse_hit_test.dart';

/// Signature for mouse enter/exit/hover callbacks.
typedef MouseEventCallback = void Function(MouseEvent event);

/// An annotation that attaches mouse event callbacks to a render object.
class MouseTrackerAnnotation {
  MouseTrackerAnnotation({
    this.onEnter,
    this.onExit,
    this.onHover,
    required this.renderObject,
  });

  final MouseEventCallback? onEnter;

  final MouseEventCallback? onExit;

  final MouseEventCallback? onHover;

  final RenderObject renderObject;

  bool validForMouseTracker = true;

  bool capturing = false;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MouseTrackerAnnotation &&
        other.renderObject == renderObject;
  }

  @override
  int get hashCode => renderObject.hashCode;
}

/// Tracks mouse annotations and dispatches enter/exit/hover events.
///
/// ## Spurious-press deferral
///
/// On macOS a trackpad in the middle of a two-finger scroll will sometimes
/// emit a button-press event when a thumb or palm brushes the surface, with
/// no matching release. If the press is dispatched immediately, every
/// widget that branches on `event.pressed` (e.g. `SelectionArea`'s
/// `_handlePointerDown` or `GestureDetector`'s tap recognizer) starts a
/// drag/click that the user never asked for; the next wheel event then
/// extends the spurious selection across the screen.
///
/// To prevent this, the first left-button press of a new gesture is
/// **parked** rather than dispatched. The press is then either:
///
///   * dispatched together with the next event, if the next event confirms
///     the press (a release, or a motion-with-button for a drag), or
///   * silently dropped, if the next event is a wheel event or any other
///     non-confirming signal, or
///   * flushed through to the widgets anyway, if no event follows within
///     the parked-press timeout (default 100ms) — the assumption being
///     that a real press that has been sitting for 100ms with no follow-up
///     is almost certainly a long-press or slow click, not a trackpad
///     palm brush, and recognizers need to see it to start timers.
///
/// Once a press is confirmed and dispatched, subsequent events behave
/// normally — a release cleanly removes the press, motion events with the
/// button held drive a drag, etc.
class MouseTracker {
  /// The set of annotations currently under the mouse cursor.
  final Set<MouseTrackerAnnotation> _hoveredAnnotations = {};

  /// The set of mouse buttons currently held down.
  ///
  /// Only contains buttons whose press has been confirmed and dispatched.
  /// A parked press is not in this set.
  final Set<MouseButton> _pressedButtons = {};

  /// A press that arrived but has not yet been dispatched, because we are
  /// waiting to see whether the next event confirms it.
  MouseEvent? _pendingPress;

  /// Hit-test result captured alongside [_pendingPress], so we can re-dispatch
  /// the press at its original position once a confirming event arrives or
  /// the parked-press timeout fires.
  MouseHitTestResult? _pendingPressHitTest;

  /// Timer that flushes [_pendingPress] through to the widget tree if no
  /// confirming event arrives in time. This is the escape hatch for slow
  /// real gestures (long-press, slow click) that need the press to be
  /// visible to recognizers in order to start their timers.
  Timer? _pendingPressTimer;

  /// How long a press may sit parked before it is flushed through to
  /// widgets anyway.
  ///
  /// 100ms is chosen as a sweet spot:
  ///   * on a real click the release almost always arrives first (typical
  ///     human click is 50–150ms but the release characteristically
  ///     follows the press within tens of milliseconds), so the press is
  ///     confirmed and dispatched together with the release;
  ///   * on a trackpad-palm-brush during a scroll, a wheel event arrives
  ///     within ~16ms, which drops the press before the timer can fire;
  ///   * on a long-press, the press is flushed at 100ms, recognizers see
  ///     it and start their long-press timer; the timer then fires at
  ///     roughly 100ms + the recognizer's threshold.
  static const _pendingPressTimeout = Duration(milliseconds: 50);

  /// Update the hovered annotations based on hit test results and dispatch
  /// the event.
  ///
  /// For a left-button press that does not follow an already-tracked press,
  /// the event is *parked* instead of dispatched. The next call to this
  /// method will either flush the parked press (if the new event confirms
  /// it) or drop it (if not).
  void updateAnnotations(MouseHitTestResult hitTestResult, MouseEvent event) {
    // A left-button motion event without a preceding confirmed press cannot be
    // a real drag. Some macOS terminal/trackpad combinations can emit this
    // shape while two-finger scrolling, and treating it as a drag starts text
    // selection. Keep it as hover/move so hover UI still works.
    if (event.button == MouseButton.left &&
        event.pressed &&
        event.isMotion &&
        !_isLeftAlreadyPressed &&
        !event.isPrimaryButtonDown &&
        _pendingPress == null) {
      _dispatchEvent(_asUnpressedMotion(event), hitTestResult);
      return;
    }

    // Park the very first left-button press of a new gesture. We do not
    // know yet whether it is a real click, the start of a drag, or a
    // spurious trackpad press during a scroll.
    if (event.button == MouseButton.left &&
        event.pressed &&
        !_isLeftAlreadyPressed &&
        _pendingPress == null) {
      _pendingPress = event;
      _pendingPressHitTest = hitTestResult;
      _pendingPressTimer?.cancel();
      _pendingPressTimer = Timer(_pendingPressTimeout, _flushPendingPress);
      return;
    }

    // A new event arrived — see if it confirms the parked press.
    final pending = _pendingPress;
    if (pending != null) {
      final pendingHitTest = _pendingPressHitTest!;
      _pendingPress = null;
      _pendingPressHitTest = null;
      _pendingPressTimer?.cancel();
      _pendingPressTimer = null;

      if (_pendingPressIsConfirmed(pending, event)) {
        // Dispatch the parked press first (so downstream widgets see a
        // press → release / press → motion sequence), then fall through
        // to dispatch the current event.
        _dispatchEvent(pending, pendingHitTest);
      }
      // Otherwise the press is silently dropped: the next event was a
      // wheel or other non-confirming signal, so the press was spurious.
    }

    _dispatchEvent(event, hitTestResult);
  }

  /// Whether the parked press at [pending] is confirmed by the arrival of
  /// [next].
  ///
  /// A press is confirmed by:
  ///   * a release of the same button (with or without motion bit), or
  ///   * a motion event that still carries the same button (drag motion).
  bool _pendingPressIsConfirmed(MouseEvent pending, MouseEvent next) {
    if (next.button != pending.button) return false;
    if (!next.pressed) return true; // release
    if (next.pressed && next.isMotion) return true; // motion-with-button
    return false;
  }

  bool get _isLeftAlreadyPressed => _pressedButtons.contains(MouseButton.left);

  /// Flush the parked press to the widget tree. Called by the parked-press
  /// timer when no confirming event arrived in time — at this point we
  /// assume the press is real (just slow) and recognizers need to see it
  /// in order to start their long-press / hold timers.
  void _flushPendingPress() {
    final pending = _pendingPress;
    final hitTest = _pendingPressHitTest;
    _pendingPress = null;
    _pendingPressHitTest = null;
    _pendingPressTimer = null;

    if (pending != null && hitTest != null) {
      _dispatchEvent(pending, hitTest);
    }
  }

  /// Dispatch [event] to the annotations under the cursor (per
  /// [hitTestResult]), updating tracker state along the way.
  void _dispatchEvent(MouseEvent event, MouseHitTestResult hitTestResult) {
    _updatePressedButtons(event);
    final effectiveEvent = _eventWithButtons(event);
    _hoveredAnnotations.removeWhere((a) => !a.validForMouseTracker);

    // Collect all annotations from the hit test result
    final Set<MouseTrackerAnnotation> hitAnnotations = {};
    for (final entry in hitTestResult.mouseEntries) {
      if (entry.target is MouseTrackerAnnotationProvider) {
        final annotation =
            (entry.target as MouseTrackerAnnotationProvider).annotation;
        if (annotation != null) {
          hitAnnotations.add(annotation);
        }
      }
    }

    // Determine if any annotation is capturing
    final hasCapture = _hoveredAnnotations.any((a) => a.capturing) ||
        hitAnnotations.any((a) => a.capturing);

    final Set<MouseTrackerAnnotation> newAnnotations = {};

    if (hasCapture) {
      // Only capturing annotations receive events; others are blocked
      for (final annotation in _hoveredAnnotations) {
        if (annotation.capturing && annotation.validForMouseTracker) {
          newAnnotations.add(annotation);
        }
      }
      for (final annotation in hitAnnotations) {
        if (annotation.capturing && annotation.validForMouseTracker) {
          newAnnotations.add(annotation);
        }
      }
    } else {
      newAnnotations.addAll(hitAnnotations);
    }

    // Find annotations that were exited
    final exitedAnnotations = _hoveredAnnotations.difference(newAnnotations);
    for (final annotation in exitedAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onExit?.call(effectiveEvent);
      }
    }

    // Find annotations that were entered
    final enteredAnnotations = newAnnotations.difference(_hoveredAnnotations);
    for (final annotation in enteredAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onEnter?.call(effectiveEvent);
      }
    }

    // Dispatch hover events to all currently hovered annotations
    for (final annotation in newAnnotations) {
      if (annotation.validForMouseTracker) {
        annotation.onHover?.call(effectiveEvent);
      }
    }

    // Update the set of hovered annotations
    _hoveredAnnotations.clear();
    _hoveredAnnotations.addAll(
      newAnnotations.where((a) => a.validForMouseTracker),
    );
  }

  /// Clear all hovered annotations (e.g., when mouse leaves the terminal).
  void clear(MouseEvent event) {
    for (final annotation in _hoveredAnnotations) {
      annotation.onExit?.call(event);
    }
    _hoveredAnnotations.clear();
    _pressedButtons.clear();
    _dropPendingPress();
  }

  void _dropPendingPress() {
    _pendingPress = null;
    _pendingPressHitTest = null;
    _pendingPressTimer?.cancel();
    _pendingPressTimer = null;
  }

  /// Track pressed buttons from press/release events. Wheel events are
  /// ignored — they neither add nor remove a pressed button, because the
  /// user is scrolling rather than holding a button.
  void _updatePressedButtons(MouseEvent event) {
    if (event.isWheel) {
      return;
    }

    if (event.pressed) {
      _pressedButtons.add(event.button);
    } else {
      _pressedButtons.remove(event.button);
    }
  }

  /// Return a copy of [event] enriched with the current pressed-buttons set.
  ///
  /// Wheel events are **not** enriched. A stuck left button (e.g. from a
  /// spurious trackpad press that was confirmed but never released) would
  /// otherwise cause every wheel event to carry `isPrimaryButtonDown = true`,
  /// which triggers unwanted drag/selection in widgets like [SelectionArea]
  /// and [Scrollbar] that branch on that flag inside their `onHover`.
  ///
  /// Widgets that need to know whether the left button is held *during* an
  /// active drag should track their own `_isDragging` state (set on real
  /// pointer-down, cleared on pointer-up) rather than relying on
  /// `isPrimaryButtonDown` for wheel events.
  MouseEvent _eventWithButtons(MouseEvent event) {
    if (event.isWheel) {
      return event;
    }
    return MouseEvent(
      button: event.button,
      x: event.x,
      y: event.y,
      pressed: event.pressed,
      isMotion: event.isMotion,
      buttons: {
        ...event.buttons,
        ..._pressedButtons,
      },
    );
  }

  MouseEvent _asUnpressedMotion(MouseEvent event) {
    return MouseEvent(
      button: event.button,
      x: event.x,
      y: event.y,
      pressed: false,
      isMotion: event.isMotion,
      buttons: event.buttons,
    );
  }
}

/// Interface for render objects that provide mouse tracker annotations.
mixin MouseTrackerAnnotationProvider {
  MouseTrackerAnnotation? get annotation;
}
