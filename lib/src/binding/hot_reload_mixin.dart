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
  StreamSubscription<WatchEvent>? _exampleWatcher;

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
      stderr.writeln(
          '[HotReload] VM service not enabled. Run with --enable-vm-service to enable hot reload.');
      return;
    }

    try {
      try {
        final info = await Service.getInfo();
        if (info.serverUri != null && info.serverWebSocketUri != null) {
          stderr.writeln(
              '[HotReload] DevTools URL: ${info.serverUri}devtools/?uri=${info.serverWebSocketUri}');
        }
      } catch (e) {
        stderr.writeln('[HotReload] Could not retrieve VM service URL: $e');
      }

      _reloader = await HotReloader.create(
        automaticReload: true,
        debounceInterval: Duration(milliseconds: 100),
        onBeforeReload: (ctx) {
          if (ctx.event case final event?) {
            stderr.writeln('[HotReload] Change detected: ${event.path}');
          }
          return true;
        },
        onAfterReload: (ctx) {
          switch (ctx.result) {
            case HotReloadResult.Failed:
              stderr.writeln('[HotReload] Hot reload FAILED');
            case HotReloadResult.Succeeded:
              stderr.writeln('[HotReload] Hot reload succeeded, reassembling...');
              _performReassembleAfterReload();
            case HotReloadResult.PartiallySucceeded:
              stderr.writeln('[HotReload] Hot reload partially succeeded');
            case HotReloadResult.Skipped:
              stderr.writeln('[HotReload] Hot reload skipped');
          }
        },
      );
      stderr.writeln('[HotReload] Ready. Watching for file changes...');

      // Also watch the example/ directory since hotreloader only watches bin/lib/test
      _watchExampleDirectory();
    } catch (e, stack) {
      stderr.writeln('[HotReload] Failed to initialize hot reload: $e');
      stderr.writeln('[HotReload] Stack trace: $stack');
    }
  }

  /// Watch the example/ directory for changes.
  /// hotreloader only watches bin/, lib/, and test/ by default,
  /// but example files are commonly edited during development.
  void _watchExampleDirectory() {
    final exampleDir = Directory('example');
    if (!exampleDir.existsSync()) return;

    final watcher = DirectoryWatcher('example');
    _exampleWatcher = watcher.events.listen((event) {
      if (!event.path.endsWith('.dart')) return;
      stderr.writeln('[HotReload] Change detected: ${event.path}');
      _reloader?.reloadCode();
    });
  }

  /// Perform reassemble after a successful hot reload
  void _performReassembleAfterReload() {
    scheduleMicrotask(() async {
      try {
        await performReassemble();
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
    _exampleWatcher?.cancel();
    _exampleWatcher = null;
    _reloader?.stop();
    _reloader = null;
  }

  /// Override shutdown to cleanup hot reload
  void shutdownWithHotReload() {
    stopHotReload();
  }
}
