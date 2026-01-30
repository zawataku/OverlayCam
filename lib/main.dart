import 'package:flutter/material.dart';

import 'package:camera/camera.dart';
import 'camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OverlayCam',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
        useMaterial3: true,
        fontFamily: 'M PLUS Rounded 1c',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          labelLarge: TextStyle(fontWeight: FontWeight.w700),
        ).apply(
          bodyColor: Colors.black87,
          displayColor: Colors.black87,
        ),
      ),
      home: CameraScreen(cameras: cameras),
    );
  }
}
