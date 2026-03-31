import 'package:cupertino_native/channel/platform_view_modal_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisibilityProbe extends StatefulWidget {
  const _VisibilityProbe({super.key});

  @override
  State<_VisibilityProbe> createState() => _VisibilityProbeState();
}

class _VisibilityProbeState extends State<_VisibilityProbe>
    with CNPlatformViewModalVisibility<_VisibilityProbe> {
  String lastRenderedVisibility = 'visible';

  @override
  MethodChannel? get visibilityChannel => null;

  @override
  Widget build(BuildContext context) {
    trackPlatformViewModalVisibility();
    lastRenderedVisibility = isPlatformViewVisible ? 'visible' : 'hidden';
    return Text(lastRenderedVisibility, textDirection: TextDirection.ltr);
  }
}

void main() {
  testWidgets('updates visibility when a modal route covers the widget', (
    WidgetTester tester,
  ) async {
    final probeKey = GlobalKey<_VisibilityProbeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: [
                  _VisibilityProbe(key: probeKey),
                  TextButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('modal'),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('close'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(probeKey.currentState?.lastRenderedVisibility, 'visible');
    expect(find.text('visible'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(probeKey.currentState?.lastRenderedVisibility, 'hidden');
    expect(find.text('hidden', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(probeKey.currentState?.lastRenderedVisibility, 'visible');
    expect(find.text('visible'), findsOneWidget);
  });
}
