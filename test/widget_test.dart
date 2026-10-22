import 'package:ai_digital_live/main.dart';
import 'package:ai_digital_live/services/digital_human_engine.dart';
import 'package:ai_digital_live/services/live_room_controller.dart';
import 'package:ai_digital_live/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App brand is 喜乐', (tester) async {
    final appState = AppState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider(
            create: (_) => LiveRoomController(
              llm: appState.llm,
              engine: DigitalHumanEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          home: const ShellPage(),
          theme: ThemeData.dark(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('喜乐'), findsWidgets);
  });
}
