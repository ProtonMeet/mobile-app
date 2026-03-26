import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class TextFieldText extends StatefulWidget {
  final double width;
  final double? height;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final bool multiLine;
  final bool showSuffixIcon;
  final bool showEnabledBorder;
  final bool digitOnly;
  final VoidCallback? suffixIconOnPressed;
  final Icon suffixIcon;
  final Color color;
  final bool showMailTag;
  final double borderRadius;
  final Widget? prefixIcon;
  final EdgeInsets? scrollPadding;
  final bool readOnly;

  const TextFieldText({
    required this.width,
    super.key,
    this.height,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.borderRadius = 8.0,
    this.multiLine = false,
    this.suffixIconOnPressed,
    this.showSuffixIcon = true,
    this.suffixIcon = const Icon(Icons.text_fields),
    this.color = Colors.transparent,
    this.showEnabledBorder = true,
    this.digitOnly = false,
    this.scrollPadding,
    this.showMailTag = false,
    this.readOnly = false,
  });

  @override
  TextFieldTextState createState() => TextFieldTextState();
}

class TextFieldTextState extends State<TextFieldText> {
  final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*\.?\d*$'),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Center(
        child:
            (widget.controller!.text.endsWith("@proton.me") &&
                widget.showMailTag)
            ? Container(
                alignment: Alignment.centerLeft,
                child: buildTagWidget(widget.controller!.text),
              )
            : TextField(
                readOnly: widget.readOnly,
                textAlignVertical: TextAlignVertical.center,
                style: ProtonStyles.captionMedium(
                  color: context.colors.textNorm,
                ),
                maxLines: widget.multiLine ? null : 1,
                minLines: widget.multiLine ? 5 : 1,
                controller: widget.controller,
                scrollPadding: widget.scrollPadding ?? const EdgeInsets.all(20),
                focusNode: widget.focusNode,
                keyboardType: widget.digitOnly
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : widget.multiLine
                    ? TextInputType.multiline
                    : TextInputType.text,
                inputFormatters: widget.digitOnly ? [_decimalFormatter] : [],
                decoration: InputDecoration(
                  prefixIcon: widget.prefixIcon,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: widget.hintText,
                  labelText: widget.labelText,
                  labelStyle: ProtonStyles.body2Regular(
                    color: context.colors.textWeak,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    borderSide: BorderSide(
                      color: widget.showEnabledBorder
                          ? Colors.transparent
                          : widget.color,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    borderSide: BorderSide(color: context.colors.protonBlue),
                  ),
                  suffixIcon: widget.showSuffixIcon
                      ? IconButton(
                          icon: widget.suffixIcon,
                          onPressed: widget.suffixIconOnPressed ?? () {},
                        )
                      : null,
                ),
              ),
      ),
    );
  }

  Widget buildTagWidget(String tag) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Chip(
        backgroundColor: context.colors.backgroundNorm,
        label: Text(
          tag,
          style: ProtonStyles.body2Medium(color: context.colors.protonBlue),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          side: BorderSide(color: context.colors.backgroundNorm),
        ),
        onDeleted: () {
          setState(() {
            widget.controller!.text = "";
          });
        },
      ),
    );
  }
}
