import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('Wrap', () {
    test('places fitting children on a row and wraps the next child', () async {
      await testNocterm(
        'wrap children',
        (tester) async {
          await tester.pumpComponent(
            Wrap(
              spacing: 1,
              children: const [
                SizedBox(width: 5, child: Text('first')),
                SizedBox(width: 5, child: Text('next')),
                SizedBox(width: 5, child: Text('third')),
              ],
            ),
          );

          final first = tester.terminalState.findText('first').single;
          final second = tester.terminalState.findText('next').single;

          final third = tester.terminalState.findText('third').single;
          expect((first.x, first.y), equals((0, 0)));
          expect((second.x, second.y), equals((6, 0)));
          expect((third.x, third.y), equals((0, 1)));
        },
        size: const Size(12, 4),
      );
    });
  });
}
