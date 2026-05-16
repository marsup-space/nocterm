import '../framework/framework.dart';

class FocusScope extends StatelessComponent {
  final Component child;

  final bool trapping;

  const FocusScope({
    super.key,
    this.trapping = true,
    required this.child,
  });

  @override
  FocusScopeElement createElement() => FocusScopeElement(this);

  @override
  Component build(BuildContext context) => child;
}

class FocusScopeElement extends StatelessElement {
  FocusScopeElement(FocusScope super.component);

  @override
  FocusScope get component => super.component as FocusScope;

  bool get isTrapping => component.trapping;
}
