import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';

typedef KeyEventHandler = bool Function(KeyboardEvent event);

class Focusable extends StatelessComponent {
  const Focusable({
    super.key,
    this.focused = false,
    this.disabled = false,
    this.autofocus = false,
    required this.onKeyEvent,
    required this.child,
  });

  final bool focused;

  final bool disabled;

  final bool autofocus;

  final KeyEventHandler onKeyEvent;

  final Component child;

  @override
  FocusableElement createElement() => FocusableElement(this);

  @override
  Component build(BuildContext context) => child;
}

class FocusableElement extends StatelessElement {
  FocusableElement(Focusable super.component);

  @override
  Focusable get component => super.component as Focusable;

  bool _hasFocus = false;
  bool _prevRequestedFocus = false;

  bool get isDisabled => component.disabled;

  bool get hasFocus => _hasFocus;

  void notifyFocusChanged(bool hasFocus) {
    if (_hasFocus == hasFocus) return;
    _hasFocus = hasFocus;
    markNeedsBuild();
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    binding.focusManager.register(this);
    if (component.autofocus || component.focused) {
      binding.focusManager.requestFocus(this);
      _prevRequestedFocus = true;
    }
  }

  @override
  void update(Component newComponent) {
    final wasRequestingFocus = _prevRequestedFocus;
    super.update(newComponent);
    final focusable = newComponent as Focusable;
    if (!wasRequestingFocus && focusable.focused) {
      binding.focusManager.requestFocus(this);
      _prevRequestedFocus = true;
    }
    if (!focusable.focused) {
      _prevRequestedFocus = false;
    }
  }

  @override
  void unmount() {
    binding.focusManager.unregister(this);
    super.unmount();
  }

  @override
  Component build() {
    return _FocusStateProvider(
      focused: _hasFocus,
      child: component.child,
    );
  }

  bool handleKeyEvent(KeyboardEvent event) {
    if (!_hasFocus) return false;
    if (component.disabled) return false;
    return component.onKeyEvent(event);
  }
}

class _FocusStateProvider extends InheritedComponent {
  const _FocusStateProvider({
    required this.focused,
    required super.child,
  });

  final bool focused;

  @override
  bool updateShouldNotify(covariant _FocusStateProvider oldComponent) {
    return focused != oldComponent.focused;
  }
}

abstract class Focus {
  static bool of(BuildContext context) {
    final provider =
        context.dependOnInheritedComponentOfExactType<_FocusStateProvider>();
    return provider?.focused ?? false;
  }
}
