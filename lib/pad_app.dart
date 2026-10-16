import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'pad_controller.dart';
import 'pad_settings.dart';
import 'pad_theme.dart';

Future<void> runPadApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // Full screen: more room for the pad, and no status bar to brush against.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final settings = await PadSettings.load();
  runApp(PadApp(settings: settings));
}

class PadApp extends StatefulWidget {
  const PadApp({super.key, required this.settings});

  final PadSettings settings;

  @override
  State<PadApp> createState() => _PadAppState();
}

class _PadAppState extends State<PadApp> {
  // Lives as long as the app, so the connection survives moving between
  // screens.
  late final _controller = PadController(widget.settings);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mouse Pad',
      debugShowCheckedModeBanner: false,
      theme: buildPadTheme(),
      home: HomeScreen(controller: _controller),
    );
  }
}
