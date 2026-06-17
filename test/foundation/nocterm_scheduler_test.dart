import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('NoctermScheduler', () {
    test('schedule defaults to target-frame cadence', () async {
      await testNocterm('scheduler max fps', (tester) async {
        final scheduler = SchedulerBinding.instance.scheduler;
        final frames = <int>[];
        late SchedulerHandle handle;

        handle = scheduler.schedule(
          (tick) {
            frames.add(tick.frame);
            if (tick.frame == 2) {
              handle.cancel();
            }
          },
          name: 'max',
        );

        expect(handle.fps, SchedulerBinding.instance.targetFps);
        await tester.pump();
        expect(frames, [1]);
        expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);

        await tester.pump();
        expect(frames, [1, 2]);
        expect(handle.isActive, isFalse);
      });
    });

    test('numeric fps runs no faster than requested', () async {
      await testNocterm('scheduler numeric fps', (tester) async {
        SchedulerBinding.instance.targetFrameDuration = FrameRate.fps60;
        final scheduler = SchedulerBinding.instance.scheduler;
        final ticks = <SchedulerTick>[];

        final handle = scheduler.schedule(
          ticks.add,
          fps: 20,
          name: 'twenty',
        );
        expect(handle.fps, 20);

        await tester.pump();
        expect(ticks, hasLength(1));

        await tester.pump();
        expect(ticks, hasLength(1));

        await tester.pump(const Duration(milliseconds: 60));
        expect(ticks, hasLength(2));
        expect(ticks.last.delta.inMilliseconds, greaterThanOrEqualTo(40));

        handle.setFps(const Fps(30));
        expect(handle.fps, 30);
        expect(handle.interval.inMicroseconds, (1000000 / 30).round());

        handle.setFps(Fps.max);
        expect(handle.fps, SchedulerBinding.instance.targetFps);

        handle.cancel();
      });
    });

    test('every waits one interval by default', () async {
      await testNocterm('scheduler every interval', (tester) async {
        final scheduler = SchedulerBinding.instance.scheduler;
        final ticks = <SchedulerTick>[];

        final handle = scheduler.every(
          const Duration(milliseconds: 25),
          ticks.add,
          repeat: 2,
        );

        await tester.pump();
        expect(ticks, hasLength(0));

        await tester.pump(const Duration(milliseconds: 30));
        expect(ticks, hasLength(1));
        expect(handle.isActive, isTrue);

        await tester.pump(const Duration(milliseconds: 30));
        expect(ticks, hasLength(2));
        expect(handle.isActive, isFalse);
      });
    });

    test('once waits for delay and then cancels itself', () async {
      await testNocterm('scheduler once delay', (tester) async {
        final scheduler = SchedulerBinding.instance.scheduler;
        final ticks = <SchedulerTick>[];

        final handle = scheduler.once(
          ticks.add,
          delay: const Duration(milliseconds: 30),
          name: 'once',
        );

        await tester.pump();
        expect(ticks, hasLength(0));
        expect(handle.isActive, isTrue);

        await tester.pump(const Duration(milliseconds: 40));
        expect(ticks, hasLength(1));
        expect(handle.isActive, isFalse);
      });
    });

    test('owner controls pause resume and cancel groups', () async {
      await testNocterm('scheduler owner controls', (tester) async {
        final scheduler = SchedulerBinding.instance.scheduler;
        final owner = Object();
        var count = 0;

        scheduler.schedule(
          (_) => count++,
          owner: owner,
          name: 'owned',
        );

        scheduler.pauseOwner(owner);
        await tester.pump();
        expect(count, 0);
        expect(scheduler.stats.paused, 1);

        scheduler.resumeOwner(owner);
        await tester.pump();
        expect(count, 1);

        scheduler.cancelOwner(owner);
        await tester.pump();
        expect(count, 1);
        expect(scheduler.stats.active, 0);
      });
    });

    test('priority controls callback order within a frame', () async {
      await testNocterm('scheduler priority order', (tester) async {
        final scheduler = SchedulerBinding.instance.scheduler;
        final order = <String>[];

        scheduler.once(
          (_) => order.add('background'),
          priority: SchedulePriority.background,
        );
        scheduler.once(
          (_) => order.add('input'),
          priority: SchedulePriority.input,
        );
        scheduler.once(
          (_) => order.add('normal'),
          priority: SchedulePriority.normal,
        );

        await tester.pump();
        expect(order, ['input', 'normal', 'background']);
      });
    });
  });
}
