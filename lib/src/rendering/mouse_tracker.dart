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
class MouseTracker {
  /// The set of annotations currently under the mouse cursor.
  final Set<MouseTrackerAnnotation> _hoveredAnnotations = {};

  /// The set of mouse buttons currently held down.
  final Set<MouseButton> _pressedButtons = {};

  /// Wall-clock time at which each currently-pressed button was first
  /// observed, keyed by that button.
  ///
  /// Used together with [_pressConfirmed] to detect "spurious" press events
  /// (e.g. macOS trackpad palm brushes during a two-finger scroll) that the
  /// OS never follows up with a release. Without this tracking the button
  /// would stay latched forever and poison every subsequent hover/wheel
  /// event with a stale `isPrimaryButtonDown=true`.
  final Map<MouseButton, DateTime> _pressTimestamps = {};

  /// Whether a press has been confirmed by a subsequent motion-with-button
  /// event. Only unconfirmed presses are eligible for stale-press cleanup;
  /// a real drag that is still in motion must not be dropped.
  final Map<MouseButton, bool> _pressConfirmed = {};

  /// Debounced timer for stale-press cleanup. Reset on every event so that
  /// an active drag (whose motion events keep arriving) never has its
  /// confirmation window expire.
  Timer? _stalePressTimer;

  /// A press is considered stale if it is unconfirmed for this long.
  ///
  /// 200ms comfortably spans:
  ///   * a single click (press → release is usually <100ms),
  ///   * a drag (press → first motion-with-button is usually <50ms),
  /// while still being short enough that a spurious trackpad press during
  /// a scroll is cleaned up before its side effects become visible.
  static const _stalePressTimeout = Duration(milliseconds: 200);

  /// Update the hovered annotations based on hit test results and dispatch events.
  void updateAnnotations(MouseHitTestResult hitTestResult, MouseEvent event) {
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
    _pressTimestamps.clear();
    _pressConfirmed.clear();
    _stalePressTimer?.cancel();
    _stalePressTimer = null;
  }

  /// Track pressed buttons from press/release events.
  void _updatePressedButtons(MouseEvent event) {
    // Ignore wheel events; they do not change button state. But they are
    // a strong signal that the user is scrolling rather than holding a
    // button, so use the opportunity to drop any unconfirmed press that
    // has already aged past the timeout — this catches the "spurious
    // trackpad press during scroll" case immediately instead of waiting
    // for the debounced timer to fire.
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      _dropStalePresses();
      _scheduleStalePressCheck();
      return;
    }

    final now = DateTime.now();
    if (event.pressed) {
      if (!_pressedButtons.contains(event.button)) {
        _pressedButtons.add(event.button);
        _pressTimestamps[event.button] = now;
        _pressConfirmed[event.button] = false;
      }
    } else {
      _pressedButtons.remove(event.button);
      _pressTimestamps.remove(event.button);
      _pressConfirmed.remove(event.button);
    }

    // A motion event that carries a held button confirms the press. This
    // is what distinguishes a real drag from a spurious press that the
    // OS will never follow up with a release.
    if (event.isMotion && event.pressed) {
      _pressConfirmed[event.button] = true;
    }

    _scheduleStalePressCheck();
  }

  /// (Re)arm the debounced stale-press timer. Every event resets it, so
  /// an active drag (whose motion events keep arriving) never has its
  /// confirmation window expire.
  void _scheduleStalePressCheck() {
    _stalePressTimer?.cancel();
    _stalePressTimer = Timer(_stalePressTimeout, _dropStalePresses);
  }

  /// Drop any press that is unconfirmed and older than the timeout.
  ///
  /// Called both synchronously (on every wheel event) and from the
  /// debounced timer. The next hover/wheel event picks up the new state
  /// via [_eventWithButtons] and is no longer enriched with a stale
  /// `buttons: {left}`.
  void _dropStalePresses() {
    final now = DateTime.now();
    final stale = <MouseButton>[];

    _pressTimestamps.forEach((button, pressedAt) {
      final confirmed = _pressConfirmed[button] ?? false;
      if (!confirmed && now.difference(pressedAt) >= _stalePressTimeout) {
        stale.add(button);
      }
    });

    for (final button in stale) {
      _pressedButtons.remove(button);
      _pressTimestamps.remove(button);
      _pressConfirmed.remove(button);
    }
  }

  /// Return a copy of [event] enriched with the current pressed-buttons set.
  MouseEvent _eventWithButtons(MouseEvent event) {
    return MouseEvent(
      button: event.button,
      x: event.x,
      y: event.y,
      pressed: event.pressed,
      isMotion: event.isMotion,
      buttons: Set<MouseButton>.of(_pressedButtons),
    );
  }
}

/// Interface for render objects that provide mouse tracker annotations.
mixin MouseTrackerAnnotationProvider {
  MouseTrackerAnnotation? get annotation;
}
