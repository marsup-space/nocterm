// App-wide hover hint system.
//
// A *hint* is a small floating tooltip that appears when the user hovers
// over a UI element. The system has three moving parts:
//
// 1. [HintController] — a process-wide singleton that tracks the currently
//    active hint (content, position, color, visibility) and notifies
//    listeners when it changes. Components register hints through it and
//    the overlay observes it.
//
// 2. [HintStateMixin] — a mixin on [State] for components that want to
//    expose a hint. Override [HintStateMixin.hintContent] to provide the
//    hint text and [HintStateMixin.hintDelay] to control when it appears
//    (default 500 ms). Wrap your build output in
//    [HintStateMixin.buildWithHint] and the mixin will handle mouse
//    enter/hover/exit and route the hint to the controller.
//
// 3. [HintOverlay] — a top-level wrapper that draws the active hint
//    above all other content. Place it as high in the tree as possible
//    (ideally just inside [NoctermApp]). The hint is positioned at the
//    coordinates handed to [HintController.show] — but those
//    coordinates must be in the overlay's *local* frame, not in
//    absolute terminal cell coordinates. When the overlay is at the
//    top of the tree, its local frame matches the terminal frame
//    and the two are interchangeable.
//
// Usage:
//
// ```dart
// class _MyButtonState extends State<MyButton> with HintStateMixin<MyButton> {
//   @override
//   String? get hintContent => 'Click to submit';
//
//   @override
//   Component build(BuildContext context) {
//     return buildWithHint(
//       Button(label: 'Submit', onPressed: ...),
//     );
//   }
// }
// ```
//
// The [HintOverlay] is wired up at the app root:
//
// ```dart
// NoctermApp(
//   child: HintOverlay(child: MyApp()),
// );
// ```

import 'dart:async';
import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';

/// Where the [HintOverlay] should try to place a hint's tooltip
/// relative to the source of the hint.
///
/// The overlay uses the [HintController.activePlacement] as a
/// preference: it first tries the preferred side, then the
/// opposite, and finally (if both fail to fit on screen) the
/// non-overlapping side that's closest to the source.
enum HintPlacement { above, below, left, right }

// =============================================================================
// HintController
// =============================================================================

/// App-wide singleton that tracks the currently active hover hint.
///
/// Hints are identified by an opaque [Object] request id. A subsequent
/// [show] call with the same id replaces the existing hint in place
/// (resetting the delay timer and updating the position/color). A
/// [show] call with a different id preempts the active hint immediately.
///
/// A hint that hasn't finished its delay timer is *registered* but not
/// *visible* — this lets short hovers (e.g. moving the mouse across a
/// row of hint-enabled buttons) not flash a tooltip if the user doesn't
/// settle on any single one long enough.
class HintController implements Listenable {
  HintController._();

  /// The global instance. Components register hints through
  /// `HintController.instance`; the [HintOverlay] listens to it.
  static final HintController instance = HintController._();

  String? _activeHint;
  Offset? _activePosition;
  Color? _activeColor;
  int? _activeMaxWidth;
  HintPlacement? _activePlacement;
  Rect? _activeSourceBounds;
  bool _visible = false;
  Timer? _pendingTimer;
  Object? _activeRequestId;
  Duration? _pendingDelay;

  final List<VoidCallback> _listeners = [];

  /// Add a listener that gets called whenever the active hint changes.
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Remove a previously registered listener.
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// The currently active hint text, or `null` if no hint is active.
  String? get activeHint => _activeHint;

  /// The position at which the active hint was last requested,
  /// expressed in the [HintOverlay]'s local coordinate system
  /// (i.e. the top-left of the overlay's `Stack`). The overlay
  /// passes this directly to the tooltip's `Positioned` widget, so
  /// the value must be relative to the overlay's frame — *not* the
  /// terminal's top-left. The overlay's own paint pass adds its
  /// frame offset on top.
  ///
  /// May be `null` if no hint is active.
  Offset? get activePosition => _activePosition;

  /// The optional foreground color for the active hint. The
  /// [HintOverlay] uses this to color the tooltip text; when `null` the
  /// theme's foreground color is used.
  Color? get activeColor => _activeColor;

  /// The maximum outer width (including the rounded border) of the
  /// active hint's tooltip, in cells. When `null`, the
  /// [HintOverlay]'s default [HintOverlay.tooltipMaxWidth] is used.
  ///
  /// Setting this lets the *source* of a hint pin the tooltip's
  /// width — for example, the scroll bar wants the tooltip to fill
  /// exactly the space between the chat content and the scrollbar
  /// track so the right edge of the tooltip sits flush against the
  /// thumb.
  int? get activeMaxWidth => _activeMaxWidth;

  /// Where the [HintOverlay] should try to place the active hint's
  /// tooltip relative to its source. The overlay uses this as a
  /// *preference* — it tries this side first, then the opposite,
  /// and finally picks a non-overlapping side if both run off the
  /// edge of the screen. When `null`, the overlay falls back to
  /// [HintPlacement.above].
  HintPlacement? get activePlacement => _activePlacement;

  /// The bounds of the source of the active hint, in the
  /// [HintOverlay]'s local coordinate system. The overlay uses
  /// this to (a) compute a non-overlapping fallback position
  /// when neither the preferred nor the opposite side fits, and
  /// (b) center [HintPlacement.above] / [HintPlacement.below]
  /// tooltips on the source's long axis. When `null`, the
  /// overlay falls back to a 1×1 rect at [activePosition] (the
  /// mouse cursor), which is good enough for small targets
  /// (toolbar buttons) but imprecise for larger ones.
  Rect? get activeSourceBounds => _activeSourceBounds;

  /// Whether the active hint has finished its delay and is currently
  /// visible. Hints that are still waiting for their delay are
  /// registered (so [activeHint] returns a value) but not visible.
  bool get visible => _visible;

  /// The delay currently being applied to the active hint, if any.
  /// Useful for tests and diagnostics; not normally read by app code.
  Duration? get pendingDelay => _pendingDelay;

  /// Show a hint at [position].
  ///
  /// The hint becomes visible after [delay]. If a hint with the same
  /// [requestId] is already active, the existing delay timer is reset
  /// and the position/color updated. A hint with a different
  /// [requestId] preempts the existing one.
  ///
  /// [position] is in the [HintOverlay]'s local coordinate system
  /// (i.e. relative to the top-left of the overlay's `Stack`). This
  /// is *not* the same as the [MouseEvent.x] / [MouseEvent.y]
  /// cell coordinates unless the [HintOverlay] sits at the
  /// terminal's top-left — most apps wrap the overlay in
  /// [NoctermApp] which puts it at the origin, but if you nest
  /// the overlay inside something that adds a paint offset (a
  /// padded [Container], a positioned [Stack] child, etc.), you
  /// must convert from mouse coordinates to overlay coordinates
  /// before calling [show] — typically by subtracting the
  /// overlay's paint offset, which the [RenderObject] of the
  /// component raising the hint has access to via `paintBounds`
  /// or by walking up the tree to find the overlay's `GlobalKey`.
  void show(
    String content,
    Offset position, {
    Duration delay = const Duration(milliseconds: 500),
    Object? requestId,
    Color? color,
    int? maxWidth,
    HintPlacement? placement,
    Rect? sourceBounds,
  }) {
    // Same source re-requesting: update the live fields in place and
    // restart the delay so the hint re-appears at the new position
    // even if the user only jiggled the mouse by a few cells.
    //
    // The overlay only re-reads the live fields when it gets a
    // [_notify] callback. If the hint was already visible, the
    // fields can be updated silently — the overlay would otherwise
    // keep painting the stale content. We track the change and
    // notify when (and only when) at least one field actually
    // differs from what the overlay last rendered.
    if (_activeRequestId != null && _activeRequestId == requestId) {
      var changed = false;
      if (_activePosition != position) {
        _activePosition = position;
        changed = true;
      }
      if (_activeColor != color) {
        _activeColor = color;
        changed = true;
      }
      if (_activeHint != content) {
        _activeHint = content;
        changed = true;
      }
      if (_activeMaxWidth != maxWidth) {
        _activeMaxWidth = maxWidth;
        changed = true;
      }
      if (_activePlacement != placement) {
        _activePlacement = placement;
        changed = true;
      }
      if (_activeSourceBounds != sourceBounds) {
        _activeSourceBounds = sourceBounds;
        changed = true;
      }
      if (delay == Duration.zero) {
        _pendingTimer?.cancel();
        _pendingTimer = null;
        _pendingDelay = null;
        if (!_visible) {
          _visible = true;
          _notify();
        } else if (changed) {
          // The hint is already on screen with a different content
          // / position / color (e.g. the user moved the mouse from
          // one scroll-bar marker to another). The fields above are
          // already updated — just notify the overlay so it picks
          // them up.
          _notify();
        }
      } else if (!_visible) {
        _restartDelay(delay);
      } else if (changed) {
        // Already visible with a non-zero delay: the existing timer
        // is fine, but the overlay still needs to re-render to pick
        // up the new live fields.
        _notify();
      }
      return;
    }

    // Different source (or first call): preempt any active hint and
    // schedule the new one.
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingDelay = null;
    _activeRequestId = requestId;
    _activeHint = content;
    _activePosition = position;
    _activeColor = color;
    _activeMaxWidth = maxWidth;
    _activePlacement = placement;
    _activeSourceBounds = sourceBounds;

    if (delay == Duration.zero) {
      _visible = true;
      _notify();
    } else {
      _visible = false;
      _notify();
      _restartDelay(delay);
    }
  }

  void _restartDelay(Duration delay) {
    _pendingTimer?.cancel();
    _pendingDelay = delay;
    _pendingTimer = Timer(delay, () {
      _pendingTimer = null;
      _pendingDelay = null;
      _visible = true;
      _notify();
    });
  }

  /// Hide the active hint, but only if it belongs to [requestId].
  ///
  /// If [requestId] is `null`, any active hint is hidden. This is
  /// useful for one-shot consumers (e.g. tests) that don't care about
  /// ownership.
  void hide({Object? requestId}) {
    if (requestId != null && _activeRequestId != requestId) return;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingDelay = null;
    _activeRequestId = null;
    _activeHint = null;
    _activePosition = null;
    _activeColor = null;
    _activeMaxWidth = null;
    _activePlacement = null;
    _activeSourceBounds = null;
    _visible = false;
    _notify();
  }

  void _notify() {
    // Copy in case a listener mutates the list.
    for (final l in List<VoidCallback>.of(_listeners)) {
      l();
    }
  }
}

// =============================================================================
// HintStateMixin
// =============================================================================

/// Mixin for [State] subclasses that want to expose a hover hint.
///
/// To enable a hint, override [hintContent] to return the hint text.
/// The hint appears after [hintDelay] of hover (default 500 ms). Wrap
/// your build output in [buildWithHint] and the mixin takes care of
/// the mouse enter/hover/exit wiring.
///
/// Components that need a non-default position (for example, a scroll
/// bar that anchors the tooltip to a marker instead of the mouse)
/// override [hintPosition]. Components that need to react to a mouse
/// move before the hint content is known (e.g. by computing which
/// marker is currently under the mouse) override [onHintHover] and
/// update any state, then call `super.onHintHover(event)` so the
/// controller picks up the new content/position.
mixin HintStateMixin<T extends StatefulComponent> on State<T> {
  Object? _requestIdInstance;

  /// Lazily-created opaque identifier used to associate this state's
  /// hint with the [HintController]. Stable across the lifetime of
  /// the state so that successive mouse moves count as updates to the
  /// same hint (not replacements by a "new" one).
  Object get _requestId => _requestIdInstance ??= Object();

  /// The hint text to show on hover. Returning `null` or an empty
  /// string means "no hint right now"; the [HintController] is told
  /// to hide anything currently registered for this state.
  String? get hintContent => null;

  /// The delay before the hint appears after hover. The default
  /// (500 ms) matches the conventional "tooltip" feel. Components
  /// that want immediate feedback (e.g. scroll bar markers) override
  /// this to return [Duration.zero].
  Duration get hintDelay => const Duration(milliseconds: 500);

  /// Optional foreground color for the hint text. When `null`, the
  /// [HintOverlay] falls back to the theme's foreground color.
  Color? get hintColor => null;

  /// Optional outer width of the tooltip in cells, *including* the
  /// border. When non-null, the [HintOverlay] pins the tooltip to
  /// exactly this width and word-wraps the content to fit inside.
  /// When `null`, the [HintOverlay]'s [HintOverlay.tooltipMaxWidth]
  /// default is used.
  ///
  /// Components that derive the tooltip's anchor from internal
  /// layout (e.g. the scroll bar wants the right edge of the
  /// tooltip to sit flush against the thumb, with the tooltip
  /// filling exactly the space between the chat content and the
  /// scrollbar) override this to pin the width.
  int? get hintMaxWidth => null;

  /// Which side of the source the [HintOverlay] should prefer when
  /// placing the tooltip. Defaults to [HintPlacement.above] so a
  /// tooltip floats above the element the user is hovering. The
  /// overlay may still flip to the opposite side (or pick a
  /// non-overlapping fallback) if the preferred side runs off the
  /// edge of the screen.
  HintPlacement get hintPlacement => HintPlacement.above;

  /// The bounds of the source of the hint, in the [HintOverlay]'s
  /// local coordinate system. Used by the overlay to (a) center
  /// [HintPlacement.above] / [HintPlacement.below] tooltips on
  /// the source's long axis and (b) pick a non-overlapping
  /// fallback position when the preferred and opposite sides
  /// both overflow the screen.
  ///
  /// Default: a 1×1 rect at the mouse cursor — good enough for
  /// small targets like toolbar buttons.  Components that know
  /// their exact bounds (e.g. the scroll bar markers) override
  /// this to give the overlay a tighter anchor.
  Rect hintSourceBounds(MouseEvent event) =>
      Rect.fromLTWH(event.x.toDouble(), event.y.toDouble(), 1, 1);

  /// Whether a hint is enabled for this component. The default
  /// checks that [hintContent] is non-null and non-empty; override
  /// only if you have a more complex predicate (for example, one
  /// that depends on runtime state).
  bool get hintEnabled {
    final c = hintContent;
    return c != null && c.isNotEmpty;
  }

  /// Returns the position where the hint should appear, in the
  /// [HintOverlay]'s local coordinate system (i.e. relative to the
  /// top-left of the overlay's `Stack`). The default follows the
  /// mouse cursor, treating the [MouseEvent]'s `x` / `y` as overlay
  /// coordinates — which is only correct when the overlay sits at
  /// the terminal's top-left. Override to anchor the hint somewhere
  /// else; for components that derive their position from a
  /// render-object-internal layout, the render object can return
  /// the position in its own local frame and the state can return
  /// that as-is (it matches the overlay's local frame whenever the
  /// render object is a descendant of the overlay's `Stack` child).
  Offset hintPosition(MouseEvent event) =>
      Offset(event.x.toDouble(), event.y.toDouble());

  /// Called when the mouse first enters the hinted region. The
  /// default shows the hint (if enabled). Override to perform custom
  /// bookkeeping; the override can call `super.onHintEnter(event)` to
  /// delegate the actual show.
  void onHintEnter(MouseEvent event) => _updateHint(event);

  /// Called for every mouse move while the cursor is inside the
  /// hinted region. The default re-shows the hint at the new mouse
  /// position. Override for the same reasons as [onHintEnter].
  void onHintHover(MouseEvent event) => _updateHint(event);

  /// Called when the mouse leaves the hinted region. The default
  /// hides the hint. Override to perform additional cleanup, then
  /// call `super.onHintExit(event)` to dismiss the hint.
  void onHintExit(MouseEvent event) {
    HintController.instance.hide(requestId: _requestId);
  }

  /// Clean up the mixin's hint registration when the state is
  /// removed permanently. Without this, a hint that's still
  /// "active" on the controller (e.g. because the user navigated
  /// away before the [onHintExit] fired) would stay painted on
  /// top of whatever replaced this widget — a stuck tooltip.
  ///
  /// Components that override [dispose] should call
  /// `super.dispose()` to keep this behavior.
  ///
  /// We override [dispose] (rather than relying only on the
  /// [MouseRegion.onExit] callback) because [RenderMouseRegion.detach]
  /// sets `validForMouseTracker = false` on the annotation, which
  /// causes [MouseTracker] to skip the [onExit] call when the
  /// render object is removed from the tree while the mouse is
  /// still inside it. That happens whenever a hinted widget is
  /// rebuilt away (e.g. conditional visibility, terminal resize,
  /// navigation) — without this dispose hook the tooltip would
  /// stay painted on top of the new content forever.
  @override
  void dispose() {
    HintController.instance.hide(requestId: _requestId);
    super.dispose();
  }

  void _updateHint(MouseEvent event) {
    if (hintEnabled) {
      HintController.instance.show(
        hintContent!,
        hintPosition(event),
        delay: hintDelay,
        requestId: _requestId,
        color: hintColor,
        maxWidth: hintMaxWidth,
        placement: hintPlacement,
        sourceBounds: hintSourceBounds(event),
      );
    } else {
      // Content disappeared (e.g. the hovered item lost its label,
      // or the component has no hint by default). Make sure no stale
      // tooltip is left behind.
      HintController.instance.hide(requestId: _requestId);
    }
  }

  /// Wrap [child] with a [MouseRegion] that drives the hint's
  /// enter/hover/exit lifecycle.
  ///
  /// The [MouseRegion] is *always* created, even when [hintContent]
  /// currently returns `null`. This matters for components whose
  /// [hintContent] is dynamic (e.g. a scroll bar that derives the
  /// hint from the marker currently under the mouse): the first
  /// hover event needs to reach [onHintEnter] / [onHintHover] so the
  /// state can update and reveal the hint. If we short-circuited
  /// when [hintContent] was null, those components would never get
  /// the first event and would need a parallel `MouseRegion` of
  /// their own — which is what the original `HintStateMixin` did
  /// via the "if (!hintEnabled) return child" guard, and what this
  /// version deliberately does not do. The "no hint right now"
  /// decision is made inside [_updateHint] by reading [hintContent]
  /// at the moment the event fires, not at build time.
  Component buildWithHint(Component child) {
    return MouseRegion(
      opaque: false,
      onEnter: onHintEnter,
      onHover: onHintHover,
      onExit: onHintExit,
      child: child,
    );
  }
}

// =============================================================================
// HintOverlay
// =============================================================================

/// A component that renders the active [HintController] hint as a
/// floating tooltip above its [child].
///
/// Place this near the top of the tree (typically just inside
/// [NoctermApp]) so that the hint is drawn over every other widget.
/// The tooltip is positioned at the global cell coordinates stored in
/// [HintController.activePosition]; a top-level [HintOverlay] means
/// those coordinates are the same as the overlay's local coordinates.
///
/// If no hint is active, the overlay is a no-op pass-through.
class HintOverlay extends StatefulComponent {
  const HintOverlay({
    super.key,
    this.tooltipBackgroundColor,
    this.tooltipBorderColor,
    this.tooltipMaxWidth = 40,
    this.tooltipMaxLines = 4,
    this.child,
  });

  /// The subtree below the overlay.
  final Component? child;

  /// Background color for the tooltip. Defaults to a slightly opaque
  /// panel color when `null`.
  final Color? tooltipBackgroundColor;

  /// Border color for the tooltip. Defaults to a muted accent when
  /// `null`.
  final Color? tooltipBorderColor;

  /// Maximum width of the tooltip in cells, including its border.
  /// Content longer than this is truncated with an ellipsis.
  final int tooltipMaxWidth;

  /// Maximum number of content lines. Multi-line content
  /// (`content` containing `\n`) is split on newlines and the tail
  /// is truncated to fit.
  final int tooltipMaxLines;

  @override
  State<HintOverlay> createState() => _HintOverlayState();
}

class _HintOverlayState extends State<HintOverlay> {
  HintController get _controller => HintController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onHintChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onHintChanged);
    super.dispose();
  }

  void _onHintChanged() {
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final hint = _controller.activeHint;
    final position = _controller.activePosition;
    final visible = _controller.visible;
    // The source of a hint can pin its width via
    // [HintController.activeMaxWidth] (e.g. the scroll bar sets it
    // to the space between the chat content and the thumb so the
    // tooltip's right edge sits flush against the thumb). When
    // unset, fall back to the [HintOverlay]'s own default.
    final maxWidth = _controller.activeMaxWidth ?? component.tooltipMaxWidth;

    // Always wrap in a [LayoutBuilder] so the widget type doesn't
    // change when the tooltip appears/disappears.  Switching from a
    // plain [Stack] to a [LayoutBuilder] would cause the framework to
    // deactivate the entire subtree (including any [Hinted] children)
    // and recreate it — which destroys the hover state and, with the
    // [HintStateMixin.dispose] hook, prematurely hides the tooltip.
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Resolve tooltip position only when we have something to show.
        Offset? tooltipDxDy;
        if (visible && hint != null && position != null) {
          final sourceBounds = _controller.activeSourceBounds ??
              Rect.fromLTWH(position.dx, position.dy, 1, 1);
          final placement =
              _controller.activePlacement ?? HintPlacement.above;
          // Estimate tooltip height from the actual content line
          // count, capped at [tooltipMaxLines].  Using
          // [tooltipMaxLines] directly overestimates the height
          // for short hints (e.g. a 2-line hint gets 6 cells
          // instead of 4), which creates an ugly gap between the
          // tooltip bottom and the source.
          final contentLines =
              1 + '\n'.allMatches(hint).length;
          final clampedLines =
              contentLines.clamp(1, component.tooltipMaxLines);
          final tooltipSize = Size(
            maxWidth.toDouble(),
            (clampedLines + 2).toDouble(), // +2 for top/bottom border
          );
          tooltipDxDy = _resolveTooltipPosition(
            sourceBounds: sourceBounds,
            tooltipSize: tooltipSize,
            stackSize: stackSize,
            preferredPlacement: placement,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (component.child != null) component.child!,
            if (tooltipDxDy != null)
              Positioned(
                left: tooltipDxDy.dx,
                top: tooltipDxDy.dy,
                child: _HintTooltip(
                  content: hint!,
                  color: _controller.activeColor,
                  backgroundColor: component.tooltipBackgroundColor,
                  borderColor: component.tooltipBorderColor,
                  maxWidth: maxWidth,
                  maxLines: component.tooltipMaxLines,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Pick the top-left cell of the tooltip, in the Stack's local
  /// coordinate system, given where the source is, how big the
  /// tooltip will be, and which side the source would prefer.
  ///
  /// The algorithm is the three-step policy the user asked for:
  ///   1. Try the [preferredPlacement] as-is.
  ///   2. If that runs off the edge of [stackSize], flip to the
  ///      *opposite* side and try that.
  ///   3. If the opposite also runs off the edge, find a placement
  ///      that does not overlap [sourceBounds] at all (so the
  ///      tooltip can't cover the element the user is hovering)
  ///      and that is as close to the source as possible.
  ///
  /// The returned position is the top-left cell of the tooltip; it
  /// is *not* clamped to the stack. If the tooltip is larger than
  /// the stack (which shouldn't happen in practice) it will run off
  /// the edge and the Stack's `clipBehavior` will chop it.
  Offset _resolveTooltipPosition({
    required Rect sourceBounds,
    required Size tooltipSize,
    required Size stackSize,
    required HintPlacement preferredPlacement,
  }) {
    // Center of a Rect along each axis. The framework's [Rect] is
    // minimal and doesn't expose a `center` getter, so we compute
    // it inline.
    double centerX(Rect r) => r.left + r.width / 2;
    double centerY(Rect r) => r.top + r.height / 2;

    Offset positionFor(Rect source, Size tooltip, HintPlacement p) {
      switch (p) {
        case HintPlacement.above:
          return Offset(
            centerX(source) - tooltip.width / 2,
            source.top - tooltip.height - 1,
          );
        case HintPlacement.below:
          return Offset(
            centerX(source) - tooltip.width / 2,
            source.bottom + 1,
          );
        case HintPlacement.left:
          return Offset(
            source.left - tooltip.width - 1,
            centerY(source) - tooltip.height / 2,
          );
        case HintPlacement.right:
          return Offset(
            source.right + 1,
            centerY(source) - tooltip.height / 2,
          );
      }
    }

    bool fits(Offset pos, Size tooltip, Size bounds) {
      return pos.dx >= 0 &&
          pos.dy >= 0 &&
          pos.dx + tooltip.width <= bounds.width &&
          pos.dy + tooltip.height <= bounds.height;
    }

    // Two rects overlap iff they intersect on *both* axes. The
    // framework's [Rect] doesn't expose `overlaps`, so we check
    // directly.
    bool overlaps(Rect a, Rect b) =>
        a.left < b.right &&
        a.right > b.left &&
        a.top < b.bottom &&
        a.bottom > b.top;

    // Clamp a proposed position so the tooltip stays inside the
    // stack.  This turns a near-miss (e.g. the tooltip's *center*
    // is aligned with a marker near the top edge, so the top
    // border overflows by 2 cells) into a valid position without
    // flipping to the opposite side.
    Offset clampToBounds(Offset pos, Size tooltip, Size bounds) {
      final maxDx = (bounds.width - tooltip.width).clamp(0, double.infinity);
      final maxDy = (bounds.height - tooltip.height).clamp(0, double.infinity);
      return Offset(
        pos.dx.clamp(0.0, maxDx).toDouble(),
        pos.dy.clamp(0.0, maxDy).toDouble(),
      );
    }

    // ════════════════════════════════════════════════════════════
    // Positioning policy
    // ════════════════════════════════════════════════════════════
    //
    // 1. Preferred side with horizontal nudge.  Keep the vertical
    //    gap; only shift left/right if the tooltip overflows.
    // 2. Opposite side with horizontal nudge.
    // 3. All four sides, non-overlapping, unclamped.  Pick closest.
    // 4. Full clamp (both axes — last resort; may overlap source).
    //
    // Horizontal nudging is safe because it just shifts the tooltip
    // laterally — it doesn't destroy the 1-cell gap.  Vertical
    // clamping *does* destroy the gap, so we only use it as a last
    // resort (step 4).

    // Helper: clamp X only, leave Y alone.
    Offset clampX(Offset pos, Size tooltip, Size bounds) {
      final maxDx = (bounds.width - tooltip.width).clamp(0, double.infinity);
      return Offset(pos.dx.clamp(0.0, maxDx).toDouble(), pos.dy);
    }

    // Step 1 — preferred side, X-nudged
    final preferred =
        positionFor(sourceBounds, tooltipSize, preferredPlacement);
    final preferredX = clampX(preferred, tooltipSize, stackSize);
    if (fits(preferredX, tooltipSize, stackSize)) return preferredX;

    // Step 2 — opposite side, X-nudged
    final opposite = switch (preferredPlacement) {
      HintPlacement.above => HintPlacement.below,
      HintPlacement.below => HintPlacement.above,
      HintPlacement.left => HintPlacement.right,
      HintPlacement.right => HintPlacement.left,
    };
    final oppositePos = positionFor(sourceBounds, tooltipSize, opposite);
    final oppositeX = clampX(oppositePos, tooltipSize, stackSize);
    if (fits(oppositeX, tooltipSize, stackSize)) return oppositeX;

    // Step 3 — all four sides, non-overlapping, unclamped
    Offset? best;
    double bestDistance = double.infinity;
    for (final p in HintPlacement.values) {
      final pos = positionFor(sourceBounds, tooltipSize, p);
      final posX = clampX(pos, tooltipSize, stackSize);
      if (!fits(posX, tooltipSize, stackSize)) continue;
      final tooltipRect =
          Rect.fromLTWH(posX.dx, posX.dy, tooltipSize.width, tooltipSize.height);
      if (overlaps(tooltipRect, sourceBounds)) continue;
      final dx = posX.dx - centerX(sourceBounds);
      final dy = posX.dy - centerY(sourceBounds);
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < bestDistance) {
        best = posX;
        bestDistance = dist;
      }
    }
    if (best != null) return best;

    // Step 4 — full clamp (last resort; may overlap source)
    final clampedPreferred =
        clampToBounds(preferred, tooltipSize, stackSize);
    if (fits(clampedPreferred, tooltipSize, stackSize)) {
      return clampedPreferred;
    }

    final clampedOpposite =
        clampToBounds(oppositePos, tooltipSize, stackSize);
    // Give up; let the Stack clip
    return preferred;
  }
}

// =============================================================================
// Hinted wrapper
// =============================================================================

/// Wraps a [child] with a hover-driven hint tooltip.
///
/// This is the convenient "I just want a hint on this widget" entry
/// point: drop a `Hinted` around any subtree, give it a [hint]
/// string, and the app-wide [HintOverlay] will draw a tooltip after
/// a hover. The tooltip's preferred side is controlled by [placement]
/// (default: above the source), and its delay follows [delay]
/// (default: the [HintStateMixin] default of 500 ms).
///
/// Use this when the widget you want to hint isn't a `StatefulComponent`
/// (so [HintStateMixin] isn't an option), or when the hint is
/// decoupled from the widget's own state and just describes the
/// widget from the outside.
class Hinted extends StatefulComponent {
  const Hinted({
    super.key,
    required this.hint,
    this.delay,
    this.placement = HintPlacement.above,
    this.color,
    required this.child,
  });

  /// The hint text. Empty / null strings disable the hint.
  final String hint;

  /// Override the default 500 ms hover delay. `null` means "use
  /// the [HintStateMixin] default".
  final Duration? delay;

  /// Which side of the source the tooltip should prefer.
  final HintPlacement placement;

  /// Optional foreground color for the tooltip.
  final Color? color;

  /// The subtree to wrap.
  final Component child;

  @override
  State<Hinted> createState() => _HintedState();
}

class _HintedState extends State<Hinted> with HintStateMixin<Hinted> {
  @override
  String? get hintContent {
    final h = component.hint;
    return h.isEmpty ? null : h;
  }

  @override
  Duration get hintDelay => component.delay ?? super.hintDelay;

  @override
  HintPlacement get hintPlacement => component.placement;

  @override
  Color? get hintColor => component.color;

  @override
  Component build(BuildContext context) => buildWithHint(component.child);
}

// =============================================================================
// Internal: _HintTooltip
// =============================================================================

/// The leaf widget that draws a single tooltip. Exposed as a separate
/// widget (rather than inlined into [HintOverlay]) so that the
/// layout-time computation of width/height is isolated from the
/// active-hint state in [_HintOverlayState].
class _HintTooltip extends StatelessComponent {
  const _HintTooltip({
    required this.content,
    this.color,
    this.backgroundColor,
    this.borderColor,
    this.maxWidth = 40,
    this.maxLines = 4,
  });

  final String content;
  final Color? color;
  final Color? backgroundColor;
  final Color? borderColor;
  final int maxWidth;
  final int maxLines;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final fg = color ?? theme.onSurface;
    final bg = backgroundColor ?? _defaultTooltipBackground(theme);
    final border = borderColor ?? _defaultTooltipBorder(theme);

    // The tooltip is *always* [maxWidth] cells wide (including the
    // border) — even when the content is shorter. This is the
    // behavior the scroll bar relies on to keep the tooltip's
    // right edge pinned against the thumb regardless of label
    // length. The [BoxDecoration] border takes 1 cell on each
    // side, so the inner [Text] widget sees [maxWidth] − 2 cells
    // of width and word-wraps accordingly.
    //
    // `softWrap: true` (the default for [Text]) plus
    // `overflow: TextOverflow.ellipsis` plus `maxLines: maxLines`
    // gives us the same behavior the previous, hand-rolled
    // _wrapText / _truncateToWidth used to provide: word-wrap
    // to the available width, ellipsize words that don't fit,
    // and clamp the total height to [maxLines] rows (with the
    // last visible row getting a trailing `…` if the content was
    // truncated).
    final outerWidth = maxWidth < 3 ? 3 : maxWidth;
    return SizedBox(
      width: outerWidth.toDouble(),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: BoxBorder.all(color: border, style: BoxBorderStyle.rounded),
        ),
        padding: EdgeInsets.zero,
        child: Text(
          content,
          style: TextStyle(color: fg),
          softWrap: true,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Fallback background used when the caller didn't supply a
  /// [tooltipBackgroundColor] and the theme has no obvious "overlay"
  /// surface. The color is opaque so it reliably covers the cell
  /// underneath, regardless of the theme's actual surface tint.
  static Color _defaultTooltipBackground(TuiThemeData theme) {
    if (theme.surface.alpha == 0xFF) return theme.surface;
    return theme.brightness == Brightness.light
        ? const Color(0xF0F5F5F5)
        : const Color(0xF021222C);
  }

  static Color _defaultTooltipBorder(TuiThemeData theme) {
    if (theme.outlineVariant.alpha == 0xFF) return theme.outlineVariant;
    return theme.outline;
  }
}
