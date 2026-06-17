import 'package:nocterm/nocterm.dart';

void main() async {
  await runApp(const WidgetReplacementTest());
}

class WidgetReplacementTest extends StatefulComponent {
  const WidgetReplacementTest({super.key});

  @override
  State<WidgetReplacementTest> createState() => _WidgetReplacementTestState();
}

class _WidgetReplacementTestState extends State<WidgetReplacementTest> {
  int phase = 0;

  @override
  void initState() {
    super.initState();

    // Phase 1: Switch to DecoratedBox after 1 second
    SchedulerBinding.instance.scheduler.once(
      (_) {
        setState(() {
          phase = 1;
        });
      },
      delay: Duration(seconds: 1),
      owner: this,
      name: 'widgetReplacementPhase1',
    );

    // Phase 2: Switch back to Text after 2 seconds
    SchedulerBinding.instance.scheduler.once(
      (_) {
        setState(() {
          phase = 2;
        });
      },
      delay: Duration(seconds: 2),
      owner: this,
      name: 'widgetReplacementPhase2',
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.scheduler.cancelOwner(this);
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Phase: $phase'),
          const SizedBox(height: 2),

          // This child changes type during rebuild
          if (phase == 0)
            const Text('Initial Text Widget')
          else if (phase == 1)
            DecoratedBox(
              decoration: BoxDecoration(
                border: BoxBorder.all(color: Colors.green),
                color: Color.fromRGB(0, 64, 0),
              ),
              child: const Text('Decorated Box'),
            )
          else
            const Text('Back to Text Widget'),
        ],
      ),
    );
  }
}
