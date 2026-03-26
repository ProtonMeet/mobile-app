import 'package:flutter/cupertino.dart';

bool isWindowsFocused() {
  return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
}

void preventGoPrevPage() {}
