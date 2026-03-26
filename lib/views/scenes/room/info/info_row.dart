import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLink;
  final bool showTopBorder;
  final bool showBottomBorder;

  const InfoRow({
    required this.label,
    required this.value,
    this.isLink = false,
    this.showTopBorder = false,
    this.showBottomBorder = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder
              ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
              : BorderSide.none,
          bottom: showBottomBorder
              ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: ProtonStyles.body1Medium(color: context.colors.textWeak),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: isLink
                  ? () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (context.mounted) {
                        LocalToast.showToast(
                          context,
                          context.local.link_copied_to_clipboard,
                        );
                      }
                    }
                  : null,
              child: Text(
                value,
                style: ProtonStyles.body1Medium(
                  color: isLink
                      ? context.colors.protonBlue
                      : context.colors.textNorm,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
