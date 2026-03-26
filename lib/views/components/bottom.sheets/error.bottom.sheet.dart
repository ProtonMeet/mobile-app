import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/base.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/components/close_button_v1.dart';

class ErrorBottomSheet {
  static List<String> existingSheets = [];

  static void show(
    BuildContext context,
    String errorMessage,
    VoidCallback? callback,
  ) {
    /// use errorMessage as unique id
    final id = errorMessage;

    /// avoid to display same errorMessage twice
    if (existingSheets.contains(id)) {
      return;
    }

    /// add id to cached list
    existingSheets.add(id);

    HomeModalBottomSheet.show(
      context,
      onFinish: () {
        /// remove id from cached list
        existingSheets.remove(id);
      },
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
                context.images.iconErrorMessage.svg(
                  fit: BoxFit.fill,
                  width: 48,
                  height: 48,
                ),
                const SizedBox(height: defaultPadding),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: defaultPadding,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.local.something_went_wrong,
                        style: ProtonStyles.headline(
                          color: context.colors.textNorm,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          errorMessage,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.notificationError,
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
                        backgroundColor: context.colors.interActionWeakDisable,
                        text: callback != null
                            ? context.local.report_a_problem
                            : context.local.close,
                        width: MediaQuery.of(context).size.width,
                        textStyle: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
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
