import 'package:flutter/material.dart';

/// Wraps [child] with a stable Flutter semantics identifier for Appium.
///
/// Appium Flutter driver can locate widgets via accessibility id:
/// `driver.findElement(by=AppiumBy.accessibilityId("meet.prejoin.join"))`
class TestId extends StatelessWidget {
  const TestId({
    required this.id,
    required this.child,
    this.button = false,
    this.textField = false,
    super.key,
  });

  final String id;
  final Widget child;
  final bool button;
  final bool textField;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      container: true,
      button: button,
      textField: textField,
      child: child,
    );
  }
}

/// Applies [TestId] when [id] is non-null and non-empty.
Widget withTestId(
  String? id,
  Widget child, {
  bool button = false,
  bool textField = false,
}) {
  if (id == null || id.isEmpty) {
    return child;
  }
  return TestId(id: id, button: button, textField: textField, child: child);
}
