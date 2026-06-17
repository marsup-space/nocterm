import 'dart:async';

import 'package:nocterm/src/binding/scheduler_binding.dart';
import 'package:nocterm/src/foundation/nocterm_error.dart';

final _schedulers = Expando<NoctermScheduler>('nocterm scheduler');

/// Adds the component scheduler to [SchedulerBinding] without requiring the
/// binding mixin itself to own another field.
extension NoctermSchedulerBindingExtension on SchedulerBinding {
  NoctermScheduler get scheduler =>
      _schedulers[this] ??= NoctermScheduler._(this);
}

/// Priority bucket for callbacks registered with [NoctermScheduler].
///
/// Lower-priority buckets run later within the transient frame phase.
enum SchedulePriority {
  input,
  animation,
  normal,
  metrics,
  background,
}

/// A requested callback cadence.
///
/// Use [Fps.max] to follow [SchedulerBinding.targetFps]. Numeric `fps`
/// arguments passed to [NoctermScheduler.schedule] are converted to [Fps].
final class Fps {
  const Fps(this.value);
  const Fps._max() : value = null;

  /// Run at the binding's target frame rate.
  static const Fps max = Fps._max();

  /// Requested frames per second, or `null` for [max].
  final num? value;

  bool get isMax => value == null;

  @override
  String toString() => isMax ? 'Fps.max' : 'Fps($value)';
}

/// Data passed to callbacks scheduled with [NoctermScheduler].
final class SchedulerTick {
  const SchedulerTick({
    required this.now,
    required this.delta,
    required this.elapsed,
    required this.frame,
    required this.lateBy,
  });

  /// Wall-clock time for this frame.
  final DateTime now;

  /// Time since this handle last fired. Zero on the first tick.
  final Duration delta;

  /// Time since this handle was scheduled.
  final Duration elapsed;

  /// Number of times this handle has fired, starting at 1.
  final int frame;

  /// How far after the scheduled due time this callback ran.
  final Duration lateBy;
}

typedef ScheduledCallback = void Function(SchedulerTick tick);

/// Handle returned by [NoctermScheduler].
abstract interface class SchedulerHandle {
  bool get isActive;
  bool get isPaused;
  String? get name;
  Object? get owner;
  Duration get interval;
  double get fps;

  void pause();
  void resume();
  void cancel();
  void setFps(Object fps);
  void setInterval(Duration interval);
  void setPriority(SchedulePriority priority);
}

/// Snapshot of scheduled work, useful for tests and debug overlays.
final class SchedulerStats {
  const SchedulerStats({
    required this.active,
    required this.paused,
    required this.byPriority,
  });

  final int active;
  final int paused;
  final Map<SchedulePriority, int> byPriority;
}

enum _ScheduleKind {
  maxFps,
  fps,
  interval,
}

/// Cocos2d-style component scheduler built on top of [SchedulerBinding].
///
/// Prefer this for component-owned timed work instead of creating individual
/// [Timer.periodic] instances. The scheduler uses the frame pipeline, keeps
/// callbacks ordered, and supports owner-based pause/resume/cancel.
final class NoctermScheduler {
  NoctermScheduler._(this._binding);

  /// The scheduler for the current binding.
  static NoctermScheduler get instance => SchedulerBinding.instance.scheduler;

  final SchedulerBinding _binding;
  final List<_ScheduledEntry> _entries = <_ScheduledEntry>[];
  Timer? _wakeTimer;
  int? _frameCallbackId;
  int _nextId = 0;
  bool _handlingFrame = false;

  /// Schedule a recurring frame-driven callback.
  ///
  /// [fps] accepts [Fps.max], [Fps], or a numeric FPS value. Numeric FPS values
  /// are clamped naturally by the binding's target frame rate because callbacks
  /// can only run on framework frames.
  SchedulerHandle schedule(
    ScheduledCallback callback, {
    Object? owner,
    String? name,
    Object fps = Fps.max,
    Duration delay = Duration.zero,
    int? repeat,
    SchedulePriority priority = SchedulePriority.normal,
    bool paused = false,
  }) {
    final cadence = _Cadence.fromFps(fps);
    return _add(
      callback,
      owner: owner,
      name: name,
      cadence: cadence,
      delay: delay,
      repeat: repeat,
      priority: priority,
      paused: paused,
    );
  }

  /// Schedule a one-shot callback.
  SchedulerHandle once(
    ScheduledCallback callback, {
    Object? owner,
    String? name,
    Duration delay = Duration.zero,
    SchedulePriority priority = SchedulePriority.normal,
    bool paused = false,
  }) {
    return _add(
      callback,
      owner: owner,
      name: name,
      cadence: const _Cadence.maxFps(),
      delay: delay,
      repeat: 1,
      priority: priority,
      paused: paused,
    );
  }

  /// Schedule a wall-clock interval callback.
  ///
  /// By default, the first tick runs after [interval]. Pass
  /// `delay: Duration.zero` to run on the next frame instead.
  SchedulerHandle every(
    Duration interval,
    ScheduledCallback callback, {
    Object? owner,
    String? name,
    Duration? delay,
    int? repeat,
    SchedulePriority priority = SchedulePriority.normal,
    bool paused = false,
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
          interval, 'interval', 'Must be > Duration.zero');
    }
    return _add(
      callback,
      owner: owner,
      name: name,
      cadence: _Cadence.interval(interval),
      delay: delay ?? interval,
      repeat: repeat,
      priority: priority,
      paused: paused,
    );
  }

  void pauseOwner(Object owner) {
    for (final entry in _entries) {
      if (entry.owner == owner && entry.isActive) {
        entry.paused = true;
      }
    }
    _scheduleNextWake();
  }

  void resumeOwner(Object owner) {
    final now = DateTime.now();
    for (final entry in _entries) {
      if (entry.owner == owner && entry.isActive) {
        entry.resumeFrom(now);
      }
    }
    _scheduleNextWake();
  }

  void cancelOwner(Object owner) {
    for (final entry in _entries) {
      if (entry.owner == owner) {
        entry._cancel(scheduleWake: false);
      }
    }
    _compactEntries();
    _scheduleNextWake();
  }

  void pauseAll() {
    for (final entry in _entries) {
      if (entry.isActive) {
        entry.paused = true;
      }
    }
    _scheduleNextWake();
  }

  void resumeAll() {
    final now = DateTime.now();
    for (final entry in _entries) {
      if (entry.isActive) {
        entry.resumeFrom(now);
      }
    }
    _scheduleNextWake();
  }

  void cancelAll() {
    for (final entry in _entries) {
      entry._cancel(scheduleWake: false);
    }
    _compactEntries();
    _scheduleNextWake();
  }

  SchedulerStats get stats {
    final byPriority = <SchedulePriority, int>{};
    var active = 0;
    var paused = 0;
    for (final entry in _entries) {
      if (!entry.isActive) continue;
      active++;
      if (entry.paused) paused++;
      byPriority[entry.priority] = (byPriority[entry.priority] ?? 0) + 1;
    }
    return SchedulerStats(
      active: active,
      paused: paused,
      byPriority: Map<SchedulePriority, int>.unmodifiable(byPriority),
    );
  }

  SchedulerHandle _add(
    ScheduledCallback callback, {
    required Object? owner,
    required String? name,
    required _Cadence cadence,
    required Duration delay,
    required int? repeat,
    required SchedulePriority priority,
    required bool paused,
  }) {
    if (delay < Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'Must be >= Duration.zero');
    }
    if (repeat != null && repeat <= 0) {
      throw ArgumentError.value(repeat, 'repeat', 'Must be null or > 0');
    }

    final now = DateTime.now();
    final entry = _ScheduledEntry(
      scheduler: this,
      id: _nextId++,
      callback: callback,
      owner: owner,
      name: name,
      cadence: cadence,
      priority: priority,
      startTime: now,
      nextDue: now.add(delay),
      remaining: repeat,
      paused: paused,
    );
    _entries.add(entry);
    _scheduleNextWake();
    return entry;
  }

  void _scheduleFramePump() {
    if (_frameCallbackId != null) return;
    _frameCallbackId = _binding.scheduleFrameCallback(
      (rawTimeStamp) {
        _frameCallbackId = null;
        _handleFrame(rawTimeStamp);
      },
      debugLabel: 'NoctermScheduler',
    );
  }

  void _handleFrame(Duration rawTimeStamp) {
    _handlingFrame = true;
    _wakeTimer?.cancel();
    _wakeTimer = null;

    try {
      final now =
          DateTime.fromMicrosecondsSinceEpoch(rawTimeStamp.inMicroseconds);
      final due = _entries.where((entry) => entry.isDue(now)).toList()
        ..sort((a, b) {
          final byPriority = a.priority.index.compareTo(b.priority.index);
          if (byPriority != 0) return byPriority;
          return a.id.compareTo(b.id);
        });

      for (final entry in due) {
        if (!entry.isDue(now)) continue;
        entry._run(now);
      }
    } finally {
      _handlingFrame = false;
      _compactEntries();
      _scheduleNextWake();
    }
  }

  void _scheduleNextWake() {
    _wakeTimer?.cancel();
    _wakeTimer = null;

    if (_handlingFrame) return;

    final now = DateTime.now();
    DateTime? nextWake;

    for (final entry in _entries) {
      if (!entry.isActive || entry.paused) continue;

      if (entry.isDue(now)) {
        _scheduleFramePump();
        return;
      }

      final due = entry.nextDueTime(now);
      if (due == null) continue;
      if (nextWake == null || due.isBefore(nextWake)) {
        nextWake = due;
      }
    }

    if (nextWake == null) return;

    final delay =
        nextWake.isAfter(now) ? nextWake.difference(now) : Duration.zero;
    _wakeTimer = Timer(delay, () {
      _wakeTimer = null;
      _scheduleFramePump();
    });
  }

  void _compactEntries() {
    _entries.removeWhere((entry) => !entry.isActive);
  }

  void _reportCallbackError(
    _ScheduledEntry entry,
    Object error,
    StackTrace stack,
  ) {
    final label = entry.name == null ? '' : ' (${entry.name})';
    NoctermError.reportError(NoctermErrorDetails(
      exception: error,
      stack: stack,
      library: 'nocterm scheduler',
      context: 'during scheduled callback$label',
    ));
  }
}

final class _Cadence {
  const _Cadence._(this.kind, this.duration, this.requestedFps);
  const _Cadence.maxFps() : this._(_ScheduleKind.maxFps, null, null);
  const _Cadence.interval(Duration duration)
      : this._(_ScheduleKind.interval, duration, null);
  _Cadence.fps(double fps)
      : this._(
          _ScheduleKind.fps,
          Duration(microseconds: (1000000 / fps).round()),
          fps,
        );

  final _ScheduleKind kind;
  final Duration? duration;
  final double? requestedFps;

  static _Cadence fromFps(Object fps) {
    if (fps == Fps.max) return const _Cadence.maxFps();
    if (fps is Fps) {
      if (fps.isMax) return const _Cadence.maxFps();
      final value = fps.value!.toDouble();
      if (value <= 0) {
        throw ArgumentError.value(value, 'fps', 'Must be > 0');
      }
      return _Cadence.fps(value);
    }
    if (fps is num) {
      final value = fps.toDouble();
      if (value <= 0) {
        throw ArgumentError.value(value, 'fps', 'Must be > 0');
      }
      return _Cadence.fps(value);
    }
    throw ArgumentError.value(fps, 'fps', 'Expected Fps.max, Fps, or num');
  }
}

final class _ScheduledEntry implements SchedulerHandle {
  _ScheduledEntry({
    required this.scheduler,
    required this.id,
    required this.callback,
    required this.owner,
    required this.name,
    required this.cadence,
    required this.priority,
    required this.startTime,
    required this.nextDue,
    required this.remaining,
    required this.paused,
  });

  final NoctermScheduler scheduler;
  final int id;
  final ScheduledCallback callback;
  @override
  final Object? owner;
  @override
  final String? name;
  _Cadence cadence;
  SchedulePriority priority;
  final DateTime startTime;
  DateTime nextDue;
  DateTime? lastTick;
  int? remaining;
  bool paused;
  bool _cancelled = false;
  int _frame = 0;

  @override
  bool get isActive => !_cancelled;

  @override
  bool get isPaused => paused;

  @override
  Duration get interval {
    switch (cadence.kind) {
      case _ScheduleKind.maxFps:
        return scheduler._binding.targetFrameDuration;
      case _ScheduleKind.fps:
      case _ScheduleKind.interval:
        return cadence.duration!;
    }
  }

  @override
  double get fps {
    switch (cadence.kind) {
      case _ScheduleKind.maxFps:
        return scheduler._binding.targetFps;
      case _ScheduleKind.fps:
        return cadence.requestedFps!;
      case _ScheduleKind.interval:
        return 1000000 / cadence.duration!.inMicroseconds;
    }
  }

  bool isDue(DateTime now) {
    if (!isActive || paused) return false;
    if (now.isBefore(nextDue)) return false;
    return true;
  }

  DateTime? nextDueTime(DateTime now) {
    if (!isActive || paused) return null;
    if (cadence.kind == _ScheduleKind.maxFps && !now.isBefore(nextDue)) {
      return now;
    }
    return nextDue;
  }

  void resumeFrom(DateTime now) {
    if (!isActive) return;
    paused = false;
    if (nextDue.isBefore(now)) {
      nextDue = now;
    }
  }

  void _run(DateTime now) {
    if (!isActive || paused) return;

    _frame++;
    final scheduledFor = nextDue;
    final tick = SchedulerTick(
      now: now,
      delta: lastTick == null ? Duration.zero : now.difference(lastTick!),
      elapsed: now.difference(startTime),
      frame: _frame,
      lateBy: now.isAfter(scheduledFor)
          ? now.difference(scheduledFor)
          : Duration.zero,
    );
    lastTick = now;

    try {
      callback(tick);
    } catch (error, stack) {
      scheduler._reportCallbackError(this, error, stack);
    }

    if (!isActive) return;

    if (remaining != null) {
      remaining = remaining! - 1;
      if (remaining! <= 0) {
        cancel();
        return;
      }
    }

    _advanceNextDue(now, scheduledFor);
  }

  void _advanceNextDue(DateTime now, DateTime scheduledFor) {
    switch (cadence.kind) {
      case _ScheduleKind.maxFps:
        nextDue = now;
        return;
      case _ScheduleKind.fps:
      case _ScheduleKind.interval:
        final step = cadence.duration!;
        var due = scheduledFor.add(step);
        while (!due.isAfter(now)) {
          due = due.add(step);
        }
        nextDue = due;
        return;
    }
  }

  @override
  void pause() {
    if (!isActive) return;
    paused = true;
    scheduler._scheduleNextWake();
  }

  @override
  void resume() {
    resumeFrom(DateTime.now());
    scheduler._scheduleNextWake();
  }

  @override
  void cancel() {
    _cancel();
  }

  void _cancel({bool scheduleWake = true}) {
    if (_cancelled) return;
    _cancelled = true;
    if (scheduleWake) {
      scheduler._scheduleNextWake();
    }
  }

  @override
  void setFps(Object fps) {
    if (!isActive) return;
    cadence = _Cadence.fromFps(fps);
    nextDue = DateTime.now();
    scheduler._scheduleNextWake();
  }

  @override
  void setInterval(Duration interval) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
          interval, 'interval', 'Must be > Duration.zero');
    }
    if (!isActive) return;
    cadence = _Cadence.interval(interval);
    nextDue = DateTime.now().add(interval);
    scheduler._scheduleNextWake();
  }

  @override
  void setPriority(SchedulePriority priority) {
    if (!isActive) return;
    this.priority = priority;
  }
}
