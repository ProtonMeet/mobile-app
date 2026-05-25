import 'package:flutter/material.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool? _backgroundBlurReady;
  final _protonVideoEffectsPlugin = ProtonVideoEffects.instance;

  @override
  void initState() {
    super.initState();
    initVideoEffectsState();
  }

  Future<void> initVideoEffectsState() async {
    final ready = await _protonVideoEffectsPlugin.isBackgroundBlurReady();

    if (!mounted) return;

    setState(() {
      _backgroundBlurReady = ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(
          child: Text(
            'Background blur ready: ${_backgroundBlurReady ?? 'checking...'}',
          ),
        ),
      ),
    );
  }
}
