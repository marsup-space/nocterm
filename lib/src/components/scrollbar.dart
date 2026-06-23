import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';
import 'package:nocterm/src/rendering/mouse_hit_test.dart';
import 'package:nocterm/src/rendering/mouse_tracker.dart';

/// A scrollbar that can be optionally shown for scrollable widgets.
///
/// Typically used by wrapping a scrollable widget like [SingleChildScrollView]
/// or [ListView]. The scrollbar automatically detects whether the scrollable
/// is reversed from the controller's axis direction.
class Scrollbar extends StatefulComponent {
  const Scrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility = false,
    this.thickness = 1.0,
    this.radius,
    this.trackColor,
    this.thumbColor,
  });

  /// The widget below this widget in the tree.
  ///
  /// The scrollbar will be painted on top of this child. The child should be
  /// a scrollable widget.
  final Component child;

  /// The [ScrollController] used to control the scrollable widget.
  ///
  /// If null, the scrollbar will attempt to find a controller from the child.
  final ScrollController? controller;

  /// Indicates whether the scrollbar thumb should be always visible.
  ///
  /// When false, the scrollbar will only be visible while scrolling.
  /// When true, the scrollbar will always be visible.
  final bool thumbVisibility;

  /// The thickness of the scrollbar in the cross axis of the scrollable.
  final double thickness;

  /// The radius of the scrollbar thumb.
  final double? radius;

  /// The color of the scrollbar track.
  ///
  /// If null, defaults to the theme's [TuiThemeData.surface] color.
  final Color? trackColor;

  /// The color of the scrollbar thumb.
  ///
  /// If null, defaults to the theme's [TuiThemeData.onSurface] color.
  final Color? thumbColor;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

class _ScrollbarState extends State<Scrollbar> {
  ScrollController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = component.controller;
  }

  @override
  void didUpdateComponent(Scrollbar oldWidget) {
    super.didUpdateComponent(oldWidget);
    if (component.controller != oldWidget.controller) {
      _controller = component.controller;
    }
  }

  @override
  Component build(BuildContext context) {
    return _ScrollbarRenderObjectWidget(
      controller: _controller,
      thumbVisibility: component.thumbVisibility,
      thickness: component.thickness,
      trackColor: component.trackColor,
      thumbColor: component.thumbColor,
      child: component.child,
    );
  }
}

class _ScrollbarRenderObjectWidget extends SingleChildRenderObjectComponent {
  const _ScrollbarRenderObjectWidget({
    required this.controller,
    required this.thumbVisibility,
    required this.thickness,
    this.trackColor,
    this.thumbColor,
    required super.child,
  });

  final ScrollController? controller;
  final bool thumbVisibility;
  final double thickness;
  final Color? trackColor;
  final Color? thumbColor;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final theme = TuiTheme.of(context);
    return RenderScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      thickness: thickness,
      trackColor: trackColor ?? theme.surface,
      thumbColor: thumbColor ?? theme.onSurface,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderScrollbar renderObject) {
    final theme = TuiTheme.of(context);
    renderObject
      ..controller = controller
      ..thumbVisibility = thumbVisibility
      ..thickness = thickness
      ..trackColor = trackColor ?? theme.surface
      ..thumbColor = thumbColor ?? theme.onSurface;
  }
}

/// Render object for a scrollbar.
class RenderScrollbar extends RenderObject
    with RenderObjectWithChildMixin<RenderObject>
    implements MouseTrackerAnnotationProvider {
  RenderScrollbar({
    ScrollController? controller,
    required bool thumbVisibility,
    required double thickness,
    required Color trackColor,
    required Color thumbColor,
  })  : _controller = controller,
        _thumbVisibility = thumbVisibility,
        _thickness = thickness,
        _trackColor = trackColor,
        _thumbColor = thumbColor {
    _controller?.addListener(_handleScrollUpdate);
  }

  @override
  MouseTrackerAnnotation? get annotation => _annotation;
  MouseTrackerAnnotation? _annotation;

  bool _isLeftButtonPressed = false;
  bool _isDragging = false;
  bool _isHovered = false;
  double _dragStartLocalY = 0;
  double _dragStartOffset = 0;

  void _setDragging(bool value) {
    if (_isDragging == value) return;
    _isDragging = value;
    _annotation?.capturing = value;
  }

  @protected
  void releaseMouseCapture() {
    _isLeftButtonPressed = false;
    _setDragging(false);
    _annotation?.capturing = false;
    markNeedsPaint();
  }

  Offset _paintOffset = Offset.zero;

  /// The minimum thumb height, capped by the available track height.
  double get minimumThumbHeight => 1.0;

  double _getThumbHeight(double trackHeight, double scrollFraction) {
    return math.min(
      trackHeight,
      math.max(minimumThumbHeight, trackHeight * scrollFraction),
    );
  }

  (double, double, double, double) _getTrackGeometry() {
    final scrollbarHeight = size.height;
    final hasArrows = scrollbarHeight >= 3;
    final trackStart = hasArrows ? 1.0 : 0.0;
    final trackEnd = hasArrows ? scrollbarHeight - 1 : scrollbarHeight;
    final trackHeight = trackEnd - trackStart;
    final scrollFraction = _controller!.viewportDimension /
        (_controller!.maxScrollExtent + _controller!.viewportDimension);
    final thumbHeight = _getThumbHeight(trackHeight, scrollFraction);
    double thumbOffset;
    if (_isReversed) {
      final scrollOffset =
          1.0 - (_controller!.offset / _controller!.maxScrollExtent);
      thumbOffset = trackStart + scrollOffset * (trackHeight - thumbHeight);
    } else {
      final scrollOffset = _controller!.offset / _controller!.maxScrollExtent;
      thumbOffset = trackStart + scrollOffset * (trackHeight - thumbHeight);
    }
    return (trackStart, trackEnd, thumbHeight, thumbOffset);
  }

  bool _isOnThumb(double localY) {
    if (_controller == null || !thumbVisibility) return false;
    if (_controller!.maxScrollExtent <= 0) return false;
    final (trackStart, _, thumbHeight, thumbOffset) = _getTrackGeometry();
    return localY >= thumbOffset && localY < thumbOffset + thumbHeight;
  }

  void _updateAnnotation() {
    _annotation = MouseTrackerAnnotation(
      onEnter: (event) {
        _isHovered = true;
        markNeedsPaint();
        if (_isDragging) {
          _handleDragMove(event);
        }
      },
      onExit: (event) {
        _isHovered = false;
        markNeedsPaint();
        if (_isDragging && !(event.pressed || event.isPrimaryButtonDown)) {
          _setDragging(false);
          _isLeftButtonPressed = false;
        }
      },
      onHover: (event) {
        if (_controller == null || !thumbVisibility) return;

        // Wheel events don't carry button state (MouseTracker intentionally
        // does not enrich them with _pressedButtons). If a drag is stuck
        // because a release event was lost (e.g. a brief UI freeze dropped
        // the mouse-up), a subsequent wheel event gives us a reliable signal
        // that the user is scrolling, not dragging — release the drag and
        // restore mouse capture to normal.
        if (event.isWheel && _isDragging) {
          releaseMouseCapture();
          return;
        }

        if (event.button == MouseButton.left || event.isPrimaryButtonDown) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handleMouseDown(event);
          } else if (leftDown && _isDragging) {
            _handleDragMove(event);
          } else if (!leftDown && _isLeftButtonPressed) {
            releaseMouseCapture();
          }
        }
      },
      renderObject: this,
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateAnnotation();
  }

  @override
  void detach() {
    _annotation?.validForMouseTracker = false;
    super.detach();
  }

  void _handleMouseDown(MouseEvent event) {
    if (_controller == null || !thumbVisibility) return;
    if (size.height < 3) return;
    if (_controller!.maxScrollExtent <= 0) return;

    final localX = event.x.toDouble() - _paintOffset.dx;
    final localY = event.y.toDouble() - _paintOffset.dy;
    final scrollbarX = size.width - thickness;

    if (localX < scrollbarX) return;

    final (trackStart, trackEnd, _, thumbOffset) = _getTrackGeometry();

    if (localY < trackStart) {
      _isReversed ? _controller!.pageDown() : _controller!.pageUp();
    } else if (localY >= trackEnd) {
      _isReversed ? _controller!.pageUp() : _controller!.pageDown();
    } else if (_isOnThumb(localY)) {
      _setDragging(true);
      _dragStartLocalY = localY;
      _dragStartOffset = _controller!.offset;
    } else {
      _scrollToTrackPosition(localY);
    }
  }

  void _handleDragMove(MouseEvent event) {
    if (!_isDragging || _controller == null) return;

    final localY = event.y.toDouble() - _paintOffset.dy;
    final deltaY = localY - _dragStartLocalY;

    final (_, _, thumbHeight, _) = _getTrackGeometry();
    final scrollbarHeight = size.height;
    final hasArrows = scrollbarHeight >= 3;
    final trackStart = hasArrows ? 1.0 : 0.0;
    final trackEnd = hasArrows ? scrollbarHeight - 1 : scrollbarHeight;
    final trackHeight = trackEnd - trackStart;

    if (trackHeight <= thumbHeight) return;

    final scrollableTrack = trackHeight - thumbHeight;
    final deltaFraction = deltaY / scrollableTrack;
    final deltaOffset = deltaFraction * _controller!.maxScrollExtent;
    final newOffset = (_dragStartOffset + deltaOffset).clamp(
      _controller!.minScrollExtent,
      _controller!.maxScrollExtent,
    );
    _controller!.jumpTo(newOffset);
  }

  void _scrollToTrackPosition(double localY) {
    if (_controller == null || _controller!.maxScrollExtent <= 0) return;

    final (_, _, thumbHeight, _) = _getTrackGeometry();
    final scrollbarHeight = size.height;
    final hasArrows = scrollbarHeight >= 3;
    final trackStart = hasArrows ? 1.0 : 0.0;
    final trackEnd = hasArrows ? scrollbarHeight - 1 : scrollbarHeight;
    final trackHeight = trackEnd - trackStart;

    if (trackHeight <= thumbHeight) return;

    final scrollableTrack = trackHeight - thumbHeight;
    final fraction = ((localY - trackStart) / scrollableTrack).clamp(0.0, 1.0);
    final targetOffset = _isReversed
        ? _controller!.maxScrollExtent * (1.0 - fraction)
        : _controller!.maxScrollExtent * fraction;
    _controller!.jumpTo(targetOffset);
  }

  ScrollController? _controller;
  ScrollController? get controller => _controller;
  set controller(ScrollController? value) {
    if (_controller != value) {
      _controller?.removeListener(_handleScrollUpdate);
      _controller = value;
      _controller?.addListener(_handleScrollUpdate);
      markNeedsPaint();
    }
  }

  Color _trackColor;
  Color get trackColor => _trackColor;
  set trackColor(Color value) {
    if (_trackColor != value) {
      _trackColor = value;
      markNeedsPaint();
    }
  }

  Color _thumbColor;
  Color get thumbColor => _thumbColor;
  set thumbColor(Color value) {
    if (_thumbColor != value) {
      _thumbColor = value;
      markNeedsPaint();
    }
  }

  /// Gets whether the scrollbar is reversed from the controller's axis direction.
  bool get _isReversed => _controller?.isReversed ?? false;

  bool _thumbVisibility;
  bool get thumbVisibility => _thumbVisibility;
  set thumbVisibility(bool value) {
    if (_thumbVisibility != value) {
      _thumbVisibility = value;
      markNeedsPaint();
    }
  }

  double _thickness;
  double get thickness => _thickness;
  set thickness(double value) {
    if (_thickness != value) {
      _thickness = value;
      markNeedsLayout();
    }
  }

  void _handleScrollUpdate() {
    markNeedsPaint();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleScrollUpdate);
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) {
    if (_isDragging) return true;
    return position.dx >= size.width - thickness;
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    final isHit = super.hitTest(result, position: position);
    if (isHit && annotation != null && result is MouseHitTestResult) {
      if (_isDragging || position.dx >= size.width - thickness) {
        result.addWithPosition(target: this, localPosition: position);
      }
    }
    return isHit;
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.constrain(Size.zero);
      return;
    }

    // Layout child with slightly reduced width to make room for scrollbar
    final childConstraints = BoxConstraints(
      minWidth: math.max(0, constraints.minWidth - thickness),
      maxWidth: math.max(0, constraints.maxWidth - thickness),
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );

    child!.layout(childConstraints, parentUsesSize: !constraints.isTight);

    // Our size includes the scrollbar
    size = constraints.constrain(Size(
      child!.size.width + thickness,
      child!.size.height,
    ));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    _paintOffset = offset;
    super.paint(canvas, offset);
    if (child == null) return;

    // Paint the child first
    child!.paint(canvas, offset);

    // Paint scrollbar if we have a controller and should show it
    if (_controller != null && thumbVisibility) {
      _paintScrollbar(canvas, offset);
    }
  }

  void _paintScrollbar(TerminalCanvas canvas, Offset offset) {
    final controller = _controller!;

    if (controller.maxScrollExtent <= 0) return;

    final scrollbarX = size.width - thickness;
    final scrollbarHeight = size.height;

    final hasArrows = scrollbarHeight >= 3;
    final trackStart = hasArrows ? 1.0 : 0.0;
    final trackEnd = hasArrows ? scrollbarHeight - 1 : scrollbarHeight;
    final trackHeight = trackEnd - trackStart;

    final scrollFraction = controller.viewportDimension /
        (controller.maxScrollExtent + controller.viewportDimension);
    final thumbHeight = _getThumbHeight(trackHeight, scrollFraction);

    double thumbOffset;
    if (_isReversed) {
      final scrollOffset =
          1.0 - (controller.offset / controller.maxScrollExtent);
      thumbOffset = trackStart + scrollOffset * (trackHeight - thumbHeight);
    } else {
      final scrollOffset = controller.offset / controller.maxScrollExtent;
      thumbOffset = trackStart + scrollOffset * (trackHeight - thumbHeight);
    }

    final idleTrackColor = _dimColor(_trackColor, 0.2);
    final idleThumbColor = _dimColor(_thumbColor, 0.3);
    final hoverThumbColor = _dimColor(_thumbColor, 0.7);
    final dragThumbColor = _thumbColor;

    final activeThumbColor = _isDragging
        ? dragThumbColor
        : _isHovered
            ? hoverThumbColor
            : idleThumbColor;

    final activeTrackColor = _isHovered || _isDragging
        ? _dimColor(_trackColor, 0.4)
        : idleTrackColor;

    for (int y = 0; y < scrollbarHeight.toInt(); y++) {
      canvas.drawText(
        offset + Offset(scrollbarX, y.toDouble()),
        '│',
        style: TextStyle(color: activeTrackColor),
      );
    }

    if (hasArrows) {
      final topArrowActive =
          _isReversed ? !controller.atEnd : !controller.atStart;
      final bottomArrowActive =
          _isReversed ? !controller.atStart : !controller.atEnd;

      final arrowColor =
          _isHovered || _isDragging ? hoverThumbColor : idleThumbColor;

      canvas.drawText(
        offset + Offset(scrollbarX, 0),
        topArrowActive ? '▲' : '│',
        style: TextStyle(color: topArrowActive ? arrowColor : activeTrackColor),
      );

      canvas.drawText(
        offset + Offset(scrollbarX, scrollbarHeight - 1),
        bottomArrowActive ? '▼' : '│',
        style:
            TextStyle(color: bottomArrowActive ? arrowColor : activeTrackColor),
      );
    }

    final thumbStart = thumbOffset.toInt();
    final thumbEnd = math.min(
      (thumbOffset + thumbHeight).toInt(),
      trackEnd.toInt(),
    );

    for (int y = thumbStart; y < thumbEnd; y++) {
      canvas.drawText(
        offset + Offset(scrollbarX, y.toDouble()),
        '█',
        style: TextStyle(color: activeThumbColor),
      );
    }
  }

  Color _dimColor(Color color, double factor) {
    return Color.fromARGB(
      (color.alpha * factor).round().clamp(0, 255),
      color.red,
      color.green,
      color.blue,
    );
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    if (child == null) return false;
    if (_isDragging) return false;

    if (position.dx >= size.width - thickness) {
      return false;
    }

    return child!.hitTest(result, position: position);
  }
}
