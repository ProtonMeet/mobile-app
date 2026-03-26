import 'package:flutter/material.dart';
import 'package:meet/views/components/custom.loading.dart';

typedef FutureCallback = Future<void> Function();

class ButtonV6 extends StatefulWidget {
  final String text;
  final double width;
  final double height;
  final double radius;
  final Color backgroundColor;
  final Color borderColor;
  final TextStyle textStyle;
  final FutureCallback? onPressed;
  final bool enable;
  final bool? isLoading;
  final Size? maximumSize;
  final Alignment alignment;

  const ButtonV6({
    required this.text,
    required this.width,
    required this.height,
    super.key,
    this.onPressed,
    this.radius = 40.0,
    this.backgroundColor = const Color(0xFF6D4AFF),
    this.borderColor = Colors.transparent,
    this.textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
    ),
    this.enable = true,
    this.isLoading,
    this.maximumSize = Size.infinite,
    this.alignment = Alignment.center,
  });

  @override
  ButtonV6State createState() => ButtonV6State();
}

class ButtonV6State extends State<ButtonV6>
    with SingleTickerProviderStateMixin {
  bool isLoading = false;
  bool enable = true;

  @override
  void initState() {
    super.initState();
    isLoading = widget.isLoading ?? false;
    enable = widget.enable;
  }

  @override
  void didUpdateWidget(ButtonV6 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enable != widget.enable ||
        oldWidget.isLoading != widget.isLoading) {
      setState(() {
        isLoading = widget.isLoading ?? false;
        enable = widget.enable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabledBackgroundColor = widget.backgroundColor.withValues(
      alpha: 0.72,
    );
    final disabledTextColor = (widget.textStyle.color ?? Colors.white)
        .withValues(alpha: 0.82);

    return Align(
      alignment: widget.alignment,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              maximumSize: widget.maximumSize,
              fixedSize: Size(widget.width, widget.height),
              backgroundColor: widget.backgroundColor,
              disabledBackgroundColor: disabledBackgroundColor,
              disabledForegroundColor: disabledTextColor,
              // foreground
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.radius),
                side: BorderSide(color: widget.borderColor),
              ),
              elevation: 0.0,
            ),
            onPressed: enable
                ? () async {
                    if (!enable) return;
                    setState(() {
                      isLoading = true;
                      enable = false;
                    });
                    await widget.onPressed?.call();
                    if (mounted) {
                      setState(() {
                        isLoading = false;
                        enable = widget.enable;
                      });
                    }
                  }
                : null,
            child: Text(
              widget.text,
              style: enable
                  ? widget.textStyle
                  : widget.textStyle.copyWith(color: disabledTextColor),
            ),
          ),
          if (isLoading)
            Positioned(
              right: 20,
              top: widget.height / 2 - 10,
              child: CustomLoading(
                color: Colors.white,
                durationInMilliSeconds: 1400,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
