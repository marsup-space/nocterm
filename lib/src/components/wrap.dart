/// Flow layout container for nocterm.
///
/// [Wrap] lays out children left-to-right and wraps to the next line
/// when the next child would exceed the available width — the terminal
/// analogue of Flutter's `Wrap`. Ideal for groups of compact, adaptive
/// width components (e.g. Cards) that should pack side by side when the
/// terminal is wide and stack only when it is narrow.
library;

import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';

/// A flow layout component.
///
/// Children are placed horizontally with [spacing] columns between them;
/// when a child no longer fits on the current line, layout continues on
/// a new line [runSpacing] rows below. The component shrink-wraps its
/// content: its width is the widest line, its height the sum of line
/// heights.
class Wrap extends RenderObjectComponent {
  const Wrap({
    super.key,
    this.spacing = 2.0,
    this.runSpacing = 0.0,
    this.children = const [],
  });

  /// Horizontal gap between children on the same line, in columns.
  final double spacing;

  /// Vertical gap between wrapped lines, in rows. Defaults to 0:
  /// catalog components like Card already carry their own bottom margin,
  /// and stacking both produces a conspicuous double blank line.
  final double runSpacing;

  final List<Component> children;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderWrap(spacing: spacing, runSpacing: runSpacing);
  }

  @override
  void updateRenderObject(BuildContext context, RenderWrap renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }

  @override
  MultiChildRenderObjectElement createElement() =>
      MultiChildRenderObjectElement(this);
}

/// Render object for [Wrap].
class RenderWrap extends RenderObject
    with ContainerRenderObjectMixin<RenderObject> {
  RenderWrap({
    double spacing = 2.0,
    double runSpacing = 1.0,
  })  : _spacing = spacing,
        _runSpacing = runSpacing;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void performLayout() {
    final double maxWidth = constraints.maxWidth;

    double x = 0;
    double y = 0;
    double lineHeight = 0;
    double maxUsedWidth = 0;

    for (final child in children) {
      // Measure each child against the available line width, then decide
      // whether it belongs on the current run or starts a new one.

      child.layout(
        BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: constraints.maxHeight,
        ),
        parentUsesSize: true,
      );

      final w = child.size.width;
      final h = child.size.height;

      // Wrap to the next line when this child no longer fits — but never
      // wrap the first child of a line (it defines the line).
      if (x > 0 && x + w > maxWidth) {
        y += lineHeight + runSpacing;
        x = 0;
        lineHeight = 0;
      }

      final BoxParentData childParentData = child.parentData as BoxParentData;
      childParentData.offset = Offset(x, y);

      x += w + spacing;
      lineHeight = math.max(lineHeight, h);
      maxUsedWidth = math.max(maxUsedWidth, x - spacing);
    }

    final double totalHeight = children.isEmpty ? 0.0 : y + lineHeight;
    size = constraints.constrain(Size(maxUsedWidth, totalHeight));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    for (final child in children) {
      final BoxParentData childParentData = child.parentData as BoxParentData;
      child.paintWithContext(canvas, offset + childParentData.offset);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    // Test children in reverse order (last child first, like paint order)
    for (final child in children.reversed) {
      final BoxParentData childParentData = child.parentData as BoxParentData;
      final childPosition = position - childParentData.offset;
      if (child.hitTest(result, position: childPosition)) {
        return true;
      }
    }
    return false;
  }
}
