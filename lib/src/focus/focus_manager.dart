import '../components/basic.dart';
import '../components/focusable.dart';
import '../components/focus_scope.dart';
import '../components/render_flex.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';

enum _NavDirection { up, down, left, right }

class FocusManager {
  FocusableElement? _activeFocusable;
  final Set<FocusableElement> _registered = {};

  FocusableElement? get activeFocusable => _activeFocusable;

  void register(FocusableElement element) {
    _registered.add(element);
    if (_activeFocusable == null && !element.isDisabled && element.mounted) {
      requestFocus(element);
    }
  }

  void unregister(FocusableElement element) {
    _registered.remove(element);
    if (_activeFocusable == element) {
      _activeFocusable = null;
      final next = _findFirstEnabled();
      if (next != null) requestFocus(next);
    }
  }

  /// Release focus from the currently active focusable, returning it
  /// to the first registered (non-disabled) focusable — typically the
  /// main input field.
  void unfocus() {
    final current = _activeFocusable;
    if (current == null) return;
    final first = _findFirstEnabled();
    if (first != null && first != current) {
      requestFocus(first);
    }
  }

  void requestFocus(FocusableElement element) {
    if (_activeFocusable == element) return;
    final old = _activeFocusable;
    _activeFocusable = element;
    if (old != null && old.mounted) {
      old.notifyFocusChanged(false);
    }
    if (element.mounted) {
      element.notifyFocusChanged(true);
    }
  }

  bool handleNavigationKey(KeyboardEvent event) {
    final key = event.logicalKey;

    if (key == LogicalKey.tab) {
      _moveTab(event.isShiftPressed ? -1 : 1);
      return true;
    }

    if (key == LogicalKey.arrowUp) return _moveArrow(_NavDirection.up);
    if (key == LogicalKey.arrowDown) return _moveArrow(_NavDirection.down);
    if (key == LogicalKey.arrowLeft) return _moveArrow(_NavDirection.left);
    if (key == LogicalKey.arrowRight) return _moveArrow(_NavDirection.right);

    return false;
  }

  void _moveTab(int direction) {
    if (_registered.isEmpty) return;

    final candidates = _getTabCandidates();
    if (candidates.isEmpty) return;

    if (_activeFocusable == null || !candidates.contains(_activeFocusable)) {
      requestFocus(candidates.first);
      return;
    }

    final idx = candidates.indexOf(_activeFocusable!);
    final nextIdx = (idx + direction + candidates.length) % candidates.length;
    requestFocus(candidates[nextIdx]);
  }

  List<FocusableElement> _getTabCandidates() {
    final scope =
        _activeFocusable != null ? _findFocusScope(_activeFocusable!) : null;
    return _registered
        .where((e) =>
            !e.isDisabled &&
            e.mounted &&
            (scope == null || _isDescendantOf(e, scope)))
        .toList()
      ..sort((a, b) => a.depth.compareTo(b.depth));
  }

  bool _moveArrow(_NavDirection direction) {
    if (_activeFocusable == null) {
      final first = _findFirstEnabled();
      if (first != null) requestFocus(first);
      return first != null;
    }

    final scopeElement = _findNearestFlexScope(_activeFocusable!);

    if (scopeElement == null) {
      return _moveByPosition(direction);
    }

    final renderFlex = _getRenderFlex(scopeElement);
    if (renderFlex == null) return _moveByPosition(direction);

    final isMainAxis = _isMainAxis(direction, renderFlex.direction);

    if (isMainAxis) {
      return _moveWithinScope(direction, scopeElement, renderFlex.direction);
    } else {
      return _moveAcrossScope(direction, scopeElement);
    }
  }

  bool _moveWithinScope(
      _NavDirection direction, Element scopeElement, Axis scopeDirection) {
    final focusables = _getFocusablesInScope(scopeElement);
    if (focusables.isEmpty) return false;

    final idx = focusables.indexOf(_activeFocusable!);
    if (idx == -1) {
      requestFocus(focusables.first);
      return true;
    }

    final isForward = _isForward(direction, scopeDirection);
    final nextIdx = isForward
        ? (idx + 1) % focusables.length
        : (idx - 1 + focusables.length) % focusables.length;

    requestFocus(focusables[nextIdx]);
    return true;
  }

  bool _moveAcrossScope(_NavDirection direction, Element currentScope) {
    final parentScope = _findNearestFlexScope(currentScope, skipSelf: true);
    if (parentScope == null) {
      return _moveByPosition(direction);
    }

    final parentRenderFlex = _getRenderFlex(parentScope);
    if (parentRenderFlex == null) return false;

    final isMainAxisInParent =
        _isMainAxis(direction, parentRenderFlex.direction);

    if (isMainAxisInParent) {
      return _moveBetweenGroups(direction, parentScope, currentScope);
    } else {
      return _moveAcrossScope(direction, parentScope);
    }
  }

  bool _moveBetweenGroups(
      _NavDirection direction, Element parentScope, Element currentChild) {
    final groups = _getFocusGroups(parentScope);
    if (groups.isEmpty) return false;

    int currentGroupIdx = -1;
    for (int i = 0; i < groups.length; i++) {
      if (_isDescendantOf(currentChild, groups[i]) ||
          currentChild == groups[i]) {
        currentGroupIdx = i;
        break;
      }
    }

    if (currentGroupIdx == -1) return false;

    final parentRenderFlex = _getRenderFlex(parentScope);
    final isForward = _isForward(direction, parentRenderFlex!.direction);
    final nextIdx = isForward ? currentGroupIdx + 1 : currentGroupIdx - 1;

    if (nextIdx < 0 || nextIdx >= groups.length) {
      return _moveAcrossScope(direction, parentScope);
    }

    final targetGroup = groups[nextIdx];
    final targetFocusables = _collectFocusables(targetGroup);
    if (targetFocusables.isEmpty) return false;

    final nearest = _findNearestByPosition(targetFocusables, _activeFocusable!);
    requestFocus(nearest ?? targetFocusables.first);
    return true;
  }

  bool _moveByPosition(_NavDirection direction) {
    if (_activeFocusable == null) return false;

    final scope = _findFocusScope(_activeFocusable!);
    final candidates = _registered
        .where((e) =>
            !e.isDisabled &&
            e.mounted &&
            e != _activeFocusable &&
            (scope == null || _isDescendantOf(e, scope)))
        .toList();

    if (candidates.isEmpty) return false;

    final activePos = _getGlobalCenter(_activeFocusable!);
    if (activePos == null) return false;

    FocusableElement? best;
    double bestScore = double.infinity;

    for (final candidate in candidates) {
      final candidatePos = _getGlobalCenter(candidate);
      if (candidatePos == null) continue;

      if (!_isInDirection(direction, activePos, candidatePos)) continue;

      final score = _distanceScore(direction, activePos, candidatePos);
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best != null) {
      requestFocus(best);
      return true;
    }

    return false;
  }

  // --- Scope / tree helpers ---

  Element? _findNearestFlexScope(Element element, {bool skipSelf = false}) {
    Element? current = skipSelf ? element.parent : element;
    while (current != null) {
      if (current is MultiChildRenderObjectElement &&
          current.renderObject is RenderFlex) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  Element? _findFocusScope(Element element) {
    Element? current = element.parent;
    while (current != null) {
      if (current is FocusScopeElement) return current;
      current = current.parent;
    }
    return null;
  }

  RenderFlex? _getRenderFlex(Element scopeElement) {
    if (scopeElement is MultiChildRenderObjectElement &&
        scopeElement.renderObject is RenderFlex) {
      return scopeElement.renderObject as RenderFlex;
    }
    return null;
  }

  List<FocusableElement> _getFocusablesInScope(Element scopeElement) {
    final result = <FocusableElement>[];
    for (final focusable in _registered) {
      if (!focusable.mounted || focusable.isDisabled) continue;
      if (!_isDescendantOf(focusable, scopeElement)) continue;
      if (_isInsideNestedFlex(focusable, scopeElement)) continue;
      result.add(focusable);
    }
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }

  bool _isInsideNestedFlex(Element element, Element ancestorFlex) {
    Element? current = element.parent;
    while (current != null && current != ancestorFlex) {
      if (current is MultiChildRenderObjectElement &&
          current.renderObject is RenderFlex) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  List<Element> _getFocusGroups(Element parentScopeElement) {
    final groups = <Element>[];
    parentScopeElement.visitChildren((child) {
      if (_containsFocusable(child)) {
        groups.add(child);
      }
    });
    return groups;
  }

  bool _containsFocusable(Element element) {
    if (element is FocusableElement && element.mounted && !element.isDisabled) {
      return true;
    }
    bool found = false;
    element.visitChildren((child) {
      if (!found) found = _containsFocusable(child);
    });
    return found;
  }

  List<FocusableElement> _collectFocusables(Element root) {
    final result = <FocusableElement>[];
    void visit(Element element) {
      if (element is FocusableElement &&
          element.mounted &&
          !element.isDisabled) {
        result.add(element);
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return result;
  }

  bool _isDescendantOf(Element descendant, Element ancestor) {
    Element? current = descendant.parent;
    while (current != null) {
      if (current == ancestor) return true;
      current = current.parent;
    }
    return false;
  }

  // --- Position helpers ---

  Offset? _getGlobalCenter(FocusableElement element) {
    final ro = _findRenderObject(element);
    if (ro == null || !ro.hasSize) return null;
    final offset = _accumulateOffset(ro);
    return Offset(
        offset.dx + ro.size.width / 2, offset.dy + ro.size.height / 2);
  }

  RenderObject? _findRenderObject(Element element) {
    if (element is RenderObjectElement) return element.renderObject;
    RenderObject? result;
    element.visitChildren((child) {
      result ??= _findRenderObject(child);
    });
    return result;
  }

  Offset _accumulateOffset(RenderObject renderObject) {
    Offset offset = Offset.zero;
    RenderObject? current = renderObject;
    while (current != null) {
      if (current.parentData is BoxParentData) {
        offset = (current.parentData as BoxParentData).offset + offset;
      }
      current = current.parent;
    }
    return offset;
  }

  bool _isInDirection(_NavDirection dir, Offset from, Offset to) {
    switch (dir) {
      case _NavDirection.up:
        return to.dy < from.dy;
      case _NavDirection.down:
        return to.dy > from.dy;
      case _NavDirection.left:
        return to.dx < from.dx;
      case _NavDirection.right:
        return to.dx > from.dx;
    }
  }

  double _distanceScore(_NavDirection dir, Offset from, Offset to) {
    final dx = (to.dx - from.dx).abs();
    final dy = (to.dy - from.dy).abs();
    switch (dir) {
      case _NavDirection.up:
      case _NavDirection.down:
        return dy + dx * 10;
      case _NavDirection.left:
      case _NavDirection.right:
        return dx + dy * 10;
    }
  }

  FocusableElement? _findNearestByPosition(
      List<FocusableElement> candidates, FocusableElement reference) {
    final refPos = _getGlobalCenter(reference);
    if (refPos == null) return null;

    FocusableElement? best;
    double bestDist = double.infinity;
    for (final candidate in candidates) {
      final pos = _getGlobalCenter(candidate);
      if (pos == null) continue;
      final dist = (pos.dx - refPos.dx).abs() + (pos.dy - refPos.dy).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = candidate;
      }
    }
    return best;
  }

  // --- Direction helpers ---

  bool _isMainAxis(_NavDirection direction, Axis axis) {
    switch (axis) {
      case Axis.horizontal:
        return direction == _NavDirection.left ||
            direction == _NavDirection.right;
      case Axis.vertical:
        return direction == _NavDirection.up || direction == _NavDirection.down;
    }
  }

  bool _isForward(_NavDirection direction, Axis axis) {
    switch (axis) {
      case Axis.horizontal:
        return direction == _NavDirection.right;
      case Axis.vertical:
        return direction == _NavDirection.down;
    }
  }

  FocusableElement? _findFirstEnabled() {
    // Registration order is tree mount order, which is the intuitive
    // fallback target for Escape: the application's primary input is
    // normally registered first. Sorting only by depth loses that order
    // for same-depth siblings because Set iteration is not ordered.
    for (final element in _registered) {
      if (!element.isDisabled && element.mounted) return element;
    }
    return null;
  }
}
