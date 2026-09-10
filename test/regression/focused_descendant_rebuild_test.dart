import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:test/test.dart';

void main() {
  test('focusing a descendant during an ancestor rebuild drains dirty state',
      () async {
    final errors = <NoctermErrorDetails>[];
    final previousHandler = NoctermError.onError;
    NoctermError.onError = errors.add;
    addTearDown(() => NoctermError.onError = previousHandler);

    await testNocterm('focused descendant rebuild', (tester) async {
      await tester.pumpComponent(const _FocusHarness());
      final state = tester.findState<_FocusHarnessState>();

      state.showEditor();
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('12.0'));
      expect(errors, isEmpty);
    });
  });
}

class _FocusHarness extends StatefulComponent {
  const _FocusHarness();

  @override
  State<_FocusHarness> createState() => _FocusHarnessState();
}

class _FocusHarnessState extends State<_FocusHarness> {
  bool _editing = false;
  final TextEditingController _controller = TextEditingController(text: '12.0');

  void showEditor() => setState(() => _editing = true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) => Focusable(
        focused: true,
        onKeyEvent: (_) => false,
        child: _editing
            ? TextField(controller: _controller, focused: true, width: 8)
            : const Text('12.0'),
      );
}
