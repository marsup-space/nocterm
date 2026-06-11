import 'package:nocterm/src/backend/stdio_backend.dart';
import 'package:test/test.dart';

void main() {
  group('sttyIcrnlArguments', () {
    test('uses the GNU device flag on Linux', () {
      expect(
        sttyIcrnlArguments(enabled: false, isLinux: true),
        equals(['-F', '/dev/tty', '-icrnl']),
      );
      expect(
        sttyIcrnlArguments(enabled: true, isLinux: true),
        equals(['-F', '/dev/tty', 'icrnl']),
      );
    });

    test('uses the BSD device flag on macOS', () {
      expect(
        sttyIcrnlArguments(enabled: false, isLinux: false),
        equals(['-f', '/dev/tty', '-icrnl']),
      );
      expect(
        sttyIcrnlArguments(enabled: true, isLinux: false),
        equals(['-f', '/dev/tty', 'icrnl']),
      );
    });
  });
}
