import 'package:flutter/material.dart';

class OffsetFloatingActionButtonLocation extends FloatingActionButtonLocation {
  final FloatingActionButtonLocation base;
  final Offset offset;

  OffsetFloatingActionButtonLocation(this.base, this.offset);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final baseOffset = base.getOffset(scaffoldGeometry);
    return baseOffset + offset;
  }
}
