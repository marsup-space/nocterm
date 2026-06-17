import 'package:nocterm/nocterm.dart';

/// Profiling app to measure where CPU time goes during active rendering.
///
/// Run with: dart run example/profile_rendering.dart
/// In another terminal: nocterm logs
///
/// This enables detailed profiling that measures time spent in:
/// - Buffer allocation
/// - Build phase (widget tree building)
/// - Layout phase
/// - Paint phase (writing to buffer)
/// - Diff render phase (comparing buffers and writing to terminal)
void main() {
  runApp(const ProfilingApp());
}

class ProfilingApp extends StatefulComponent {
  const ProfilingApp({super.key});

  @override
  State<ProfilingApp> createState() => _ProfilingAppState();
}

class _ProfilingAppState extends State<ProfilingApp> {
  int _frameCount = 0;
  SchedulerHandle? _profilingStart;
  SchedulerHandle? _timer;

  @override
  void initState() {
    super.initState();

    _profilingStart = SchedulerBinding.instance.scheduler.once(
      (_) => TerminalBinding.instance.startDetailedProfiling(),
      delay: const Duration(milliseconds: 500),
      owner: this,
      name: 'startProfiling',
    );

    // Trigger rebuilds at ~60fps to simulate active rendering
    _timer = SchedulerBinding.instance.scheduler.schedule(
      (_) => setState(() {
        _frameCount++;
      }),
      owner: this,
      name: 'profileRendering',
      fps: Fps.max,
    );
  }

  @override
  void dispose() {
    _profilingStart?.cancel();
    _timer?.cancel();
    TerminalBinding.instance.stopDetailedProfiling();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    // Build a moderately complex UI similar to vide_cli
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.keyQ) {
          TerminalBinding.instance.requestShutdown();
          return true;
        }
        return false;
      },
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Profiling App',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Frame: $_frameCount'),
              ],
            ),
          ),
          const SizedBox(height: 1),

          // Main content - ListView with many items
          Expanded(
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (context, index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Row(
                    children: [
                      Text(
                        'Item $index',
                        style: TextStyle(
                          color: index % 2 == 0 ? Colors.blue : Colors.green,
                        ),
                      ),
                      const Spacer(),
                      Text('Value: ${(index * _frameCount) % 1000}'),
                    ],
                  ),
                );
              },
            ),
          ),

          // Footer
          Container(
            decoration: BoxDecoration(border: BoxBorder.all()),
            padding: const EdgeInsets.all(1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Press Q to quit'),
                const Text('Watch nocterm logs for profiling data'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
