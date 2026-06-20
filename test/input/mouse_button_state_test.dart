import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';
import 'package:matcher/matcher.dart' as matcher;

void main() {
  group('Mouse button state', () {
    test('motion release after normal press clears button', () async {
      await testNocterm('motion release after normal press', (tester) async {
        int tapCount = 0;

        await tester.pumpComponent(
          Container(
            width: 80,
            height: 24,
            child: GestureDetector(
              onTap: () => tapCount++,
              child: Container(
                width: 20,
                height: 5,
                child: const Center(child: Text('[Click me]')),
              ),
            ),
          ),
        );

        await tester.sendMouseEvent(
          const MouseEvent(
            button: MouseButton.left,
            x: 10,
            y: 2,
            pressed: true,
          ),
        );

        await tester.sendMouseEvent(
          const MouseEvent(
            button: MouseButton.left,
            x: 10,
            y: 2,
            pressed: false,
            isMotion: true,
          ),
        );

        expect(
          tapCount,
          1,
          reason: 'Motion-marked release should still complete the click',
        );

        await tester.tap(10, 2);
        expect(
          tapCount,
          2,
          reason: 'Subsequent clicks should not inherit a stuck button state',
        );
      });
    });

    test('unconfirmed press is auto-cleared after the stale-press window',
        () async {
      await testNocterm(
        'unconfirmed press is auto-cleared after the stale-press window',
        (tester) async {
          int tapCount = 0;

          await tester.pumpComponent(
            Container(
              width: 80,
              height: 24,
              child: GestureDetector(
                onTap: () => tapCount++,
                child: Container(
                  width: 20,
                  height: 5,
                  child: const Center(child: Text('[Click me]')),
                ),
              ),
            ),
          );

          // Simulate the macOS trackpad "palm brush during two-finger scroll"
          // failure mode: a press event arrives from the OS but is never
          // followed by a release.
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.left,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );

          // Wait past the stale-press window so the debounced timer can
          // fire and clear the unconfirmed press.
          await Future<void>.delayed(const Duration(milliseconds: 250));

          // A real click after the spurious one should still register.
          await tester.tap(10, 2);
          expect(
            tapCount,
            1,
            reason:
                'Spurious press should be dropped, not poison the next click',
          );
        },
      );
    });

    test('unconfirmed press is cleared synchronously on the next wheel event',
        () async {
      await testNocterm(
        'unconfirmed press is cleared synchronously on the next wheel event',
        (tester) async {
          int tapCount = 0;

          await tester.pumpComponent(
            Container(
              width: 80,
              height: 24,
              child: GestureDetector(
                onTap: () => tapCount++,
                child: Container(
                  width: 20,
                  height: 5,
                  child: const Center(child: Text('[Click me]')),
                ),
              ),
            ),
          );

          // Spurious press, then nothing for a while, then a wheel event
          // (which on macOS trackpad is what immediately follows the
          // spurious press in the real failure mode).
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.left,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );

          await Future<void>.delayed(const Duration(milliseconds: 250));

          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.wheelUp,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );

          // The next real click should still work — the wheel event
          // triggered the synchronous stale-press cleanup.
          await tester.tap(10, 2);
          expect(
            tapCount,
            1,
            reason: 'Wheel event should clear stale press synchronously, '
                'not poison the next click',
          );
        },
      );
    });

    test('motion-with-button confirms the press so a real drag survives',
        () async {
      await testNocterm(
        'motion-with-button confirms the press so a real drag survives',
        (tester) async {
          // Observe the `buttons` field on hover events. The tracker
          // enriches every event with its current `_pressedButtons` set
          // (via `MouseTracker._eventWithButtons`), so the field of any
          // non-state-mutating event we read here reflects exactly what
          // the tracker believes is held down.
          final observedButtons = <Set<MouseButton>>[];

          await tester.pumpComponent(
            Container(
              width: 80,
              height: 24,
              child: MouseRegion(
                onHover: (event) => observedButtons.add(event.buttons),
                opaque: true,
                child: const SizedBox.expand(),
              ),
            ),
          );

          // Press, then drag motion that carries the held button. This is
          // what a real drag looks like to the tracker; the press must be
          // confirmed by the motion-with-button event so the watchdog does
          // not drop it.
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.left,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.left,
              x: 11,
              y: 2,
              pressed: true,
              isMotion: true,
            ),
          );

          // Wait past the stale-press window. The press is confirmed, so
          // the debounced watchdog timer must NOT clear it.
          await Future<void>.delayed(const Duration(milliseconds: 250));

          // Now send a wheel event. This triggers the synchronous
          // stale-press check, which must leave the confirmed press
          // untouched. The enriched `buttons` field on the event the
          // MouseRegion sees is the ground truth for the tracker's state.
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.wheelUp,
              x: 12,
              y: 2,
              pressed: true,
            ),
          );

          // Force a pump so onHover is delivered.
          await tester.pump();

          expect(
            observedButtons,
            matcher.isNotEmpty,
            reason: 'MouseRegion should have received at least one hover event',
          );
          expect(
            observedButtons.last,
            contains(MouseButton.left),
            reason: 'Confirmed press (real drag) must survive the '
                'stale-press watchdog; the wheel event should be enriched '
                'with `buttons: {left}`, got: $observedButtons',
          );
        },
      );
    });

    test(
        'spurious press during a scroll never reaches the widget tree '
        '(regression for the trackpad palm-brush case)',
        () async {
      await testNocterm(
        'spurious press during scroll is dropped before any dispatch',
        (tester) async {
          // Record every event the MouseRegion sees, in order.
          final observedEvents = <MouseEvent>[];

          await tester.pumpComponent(
            Container(
              width: 80,
              height: 24,
              child: MouseRegion(
                onHover: (event) => observedEvents.add(event),
                onEnter: (event) => observedEvents.add(event),
                onExit: (event) => observedEvents.add(event),
                opaque: true,
                child: const SizedBox.expand(),
              ),
            ),
          );

          // The real failure mode: a stray press event arrives in the
          // middle of an active scroll, with a wheel event right behind
          // it. The user is *not* pressing anything; the OS just lost
          // the touch's release.
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.left,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );
          await tester.sendMouseEvent(
            const MouseEvent(
              button: MouseButton.wheelUp,
              x: 10,
              y: 2,
              pressed: true,
            ),
          );
          await tester.pump();

          // The wheel event itself is fine to dispatch — that's what
          // actually scrolls the viewport. The press must NOT be in the
          // observed event list, because if it were, SelectionArea (or
          // any other widget branching on `event.pressed` for the left
          // button) would treat it as the start of a drag and the next
          // wheel would extend that bogus selection across the screen.
          final sawLeftPress = observedEvents.any(
            (e) => e.button == MouseButton.left && e.pressed,
          );
          expect(
            sawLeftPress,
            isFalse,
            reason:
                'Spurious left-button press during a scroll must be dropped '
                'before dispatch, got: $observedEvents',
          );
          // The wheel event did make it through — that's how scrolling
          // actually works.
          expect(
            observedEvents.any(
              (e) => e.button == MouseButton.wheelUp,
            ),
            isTrue,
            reason: 'Wheel events must still dispatch normally; got: '
                '$observedEvents',
          );
        },
      );
    });
  });
}
