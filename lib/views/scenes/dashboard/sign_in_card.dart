import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

class SignInCard extends StatelessWidget {
  const SignInCard({
    required this.onDismiss,
    required this.onSignInTap,
    super.key,
  });

  final VoidCallback onDismiss;
  final VoidCallback onSignInTap;

  final Color gradientStartColor = const Color(0xFF4E418E);
  final Color gradientEndColor = const Color(0xFF34296A);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment(0.98, 1.00),
                end: Alignment(0.02, 0.07),
                colors: [gradientStartColor, gradientEndColor],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      onDismiss();
                      onSignInTap();
                    },
                    child: Text(
                      context.local.sign_in_card_title,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.interActionNorm,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.local.sign_in_card_description,
                  style: ProtonStyles.body1Regular(
                    color: Colors.white.withValues(alpha: 0.80),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: CloseButtonV1(
            onPressed: onDismiss,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],
    );
  }
}
