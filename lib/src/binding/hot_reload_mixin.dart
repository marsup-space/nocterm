import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:hotreloader/hotreloader.dart';
import 'package:watcher/watcher.dart';

import '../foundation/nocterm_error.dart';
import '../framework/framework.dart';

/// Mixin that adds hot reload support to TUI bindings
mixin HotReloadBinding on NoctermBinding {
  HotReloader? _reloader;
  final List<StreamSubscription<WatchEvent>> _watchers = [];
  Timer? _debounceTimer;
  bool _reloadInProgress = false;

  static final _logFile = File('.dart_tool/nocterm_hot_reload.log');

  static void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    try {
      _logFile.writeAsStringSync('[$timestamp] $message\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Initialize hot reload support
  ///
  /// This should only be called in development mode
  Future<void> initializeHotReload() async {
    if (_reloader != null) return;

    final bool vmServiceEnabled = Platform.executableArguments.any((arg) =>
        arg.contains('--enable-vm-service') ||
        arg.contains('--observe') ||
        arg.contains('--enable-asserts'));

    if (!vmServiceEnabled) {
      _log(
          'VM service not enabled. Run with --enable-vm-service to enable hot reload.');
      return;
    }

    try {
      try {
        _logFile.parent.createSync(recursive: true);
        if (_logFile.existsSync()) _logFile.deleteSync();
        _logFile.writeAsStringSync('');
      } catch (_) {}

      try {
        final info = await Service.getInfo();
        if (info.serverUri != null && info.serverWebSocketUri != null) {
          _log(
              'DevTools URL: ${info.serverUri}devtools/?uri=${info.serverWebSocketUri}');
        }
      } catch (e) {
        _log('Could not retrieve VM service URL: $e');
      }

      _reloader = await HotReloader.create(
        automaticReload: false,
        onBeforeReload: (ctx) {
          if (_reloadInProgress) return false;
          _reloadInProgress = true;
          if (ctx.event case final event?) {
            _log('Change detected: ${event.path}');
          }
          return true;
        },
        onAfterReload: (ctx) {
          _reloadInProgress = false;
          switch (ctx.result) {
            case HotReloadResult.Failed:
              _log('Hot reload FAILED');
            case HotReloadResult.Succeeded:
              _log('Hot reload succeeded, reassembling...');
              _performReassembleAfterReload();
            case HotReloadResult.PartiallySucceeded:
              _log('Hot reload partially succeeded');
            case HotReloadResult.Skipped:
              _log('Hot reload skipped');
          }
        },
      );
      _log('Ready. Watching for file changes...');
      _log('View log: cat .dart_tool/nocterm_hot_reload.log');

      _registerWatchers();
    } catch (e, stack) {
      _log('Failed to initialize hot reload: $e');
      _log('Stack trace: $stack');
    }
  }

  /// Register file watchers for all relevant directories.
  /// We manage watchers ourselves instead of using hotreloader's automaticReload
  /// to avoid double-reload issues and to include the example/ directory.
  void _registerWatchers() {
    for (final dir in ['bin', 'lib', 'test', 'example']) {
      if (!Directory(dir).existsSync()) continue;
      final watcher = DirectoryWatcher(dir);
      final sub = watcher.events.listen((event) {
        if (!event.path.endsWith('.dart')) return;
        _onFileChanged(event.path);
      });
      _watchers.add(sub);
    }
  }

  void _onFileChanged(String path) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 200), () {
      if (_reloadInProgress) return;
      _log('Change detected: $path');
      _reloader?.reloadCode();
    });
  }

  /// Perform reassemble after a successful hot reload
  void _performReassembleAfterReload() {
    scheduleMicrotask(() async {
      try {
        await performReassemble();
        _log('Reassemble complete');
      } catch (e, stack) {
        NoctermError.reportError(NoctermErrorDetails(
          exception: e,
          stack: stack,
          library: 'nocterm hot reload',
          context: 'during reassemble',
        ));
      }
    });
  }

  /// Stop hot reload support
  void stopHotReload() {
    _debounceTimer?.cancel();
    for (final sub in _watchers) {
      sub.cancel();
    }
    _watchers.clear();
    _reloader?.stop();
    _reloader = null;
  }

  /// Override shutdown to cleanup hot reload
  void shutdownWithHotReload() {
    stopHotReload();
  }
}
