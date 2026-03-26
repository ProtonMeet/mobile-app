import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/base.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/components/close_button_v1.dart';

class InfoBottomSheet {
  static void show(
    BuildContext context,
    String errorMessage,
    VoidCallback? callback,
  ) {
    HomeModalBottomSheet.show(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: CloseButtonV1(
              onPressed: () {
                callback?.call();
                Navigator.of(context).pop();
              },
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -20),
            child: Column(
              children: [
                Assets.images.icon.icInfoCircle.svg(
                  fit: BoxFit.fill,
                  width: 52,
                  height: 52,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: defaultPadding,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 10,
                          left: 6,
                          right: 6,
                        ),
                        child: Text(
                          errorMessage,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.textNorm,
                            fontSize: 15.0,
                          ),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ButtonV5(
                        onPressed: () async {
                          callback?.call();
                          Navigator.of(context).pop();
                        },
                        backgroundColor: context.colors.protonBlue,
                        text: callback != null
                            ? context.local.report_a_problem
                            : context.local.close,
                        width: context.width,
                        textStyle: ProtonStyles.body1Medium(
                          color: context.colors.textInverted,
                        ),
                        height: 55,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
