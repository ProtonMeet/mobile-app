import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';

extension SvgGenImageExtension on SvgGenImage {
  Widget svg12({Color? color}) {
    return svg(
      width: 12,
      height: 12,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg16({Color? color}) {
    return svg(
      width: 16,
      height: 16,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg20({Color? color}) {
    return svg(
      width: 20,
      height: 20,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg22({Color? color}) {
    return svg(
      width: 22,
      height: 22,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg24({Color? color}) {
    return svg(
      width: 24,
      height: 24,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg30({Color? color}) {
    return svg(
      width: 30,
      height: 30,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg40({Color? color}) {
    return svg(
      width: 40,
      height: 40,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  Widget svg56() {
    return svg(width: 56, height: 56);
  }

  Widget svg70() {
    return svg(width: 70, height: 70);
  }

  Widget svg72() {
    return svg(width: 72, height: 72);
  }
}
