import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class ScheduleHandle extends StatelessWidget {
  const ScheduleHandle({
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: Container(
        width: 40,
        height: 4,
        decoration: ShapeDecoration(
          color: context.colors.textNorm.withValues(alpha: 0.24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(200),
          ),
        ),
      ),
    );
  }
}
