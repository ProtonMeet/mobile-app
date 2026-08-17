import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/test_id.dart';

class RememberCheckbox extends StatelessWidget {
  const RememberCheckbox({
    required this.value,
    required this.onChanged,
    this.height = 20,
    this.testId,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double height;
  final String? testId;

  @override
  Widget build(BuildContext context) {
    return withTestId(
      testId,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () {
            onChanged(!value);
          },
          child: Row(
            children: [
              SizedBox(
                width: height,
                height: height,
                child: Checkbox(
                  value: value,
                  onChanged: (newValue) {
                    if (newValue != null) {
                      onChanged(newValue);
                    }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.local.remember_display_name_on_device,
                  style: ProtonStyles.bodySmallSemibold(
                    color: context.colors.textWeak,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      button: true,
    );
  }
}
