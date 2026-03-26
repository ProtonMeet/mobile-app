import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class MeetingSettingsContent extends StatefulWidget {
  const MeetingSettingsContent({super.key});

  @override
  State<MeetingSettingsContent> createState() => _MeetingSettingsContentState();
}

class _MeetingSettingsContentState extends State<MeetingSettingsContent> {
  // Settings state
  bool _chooseNewHostOnLeave = false;
  bool _lockMeeting = true;
  bool _backgroundBlur = false;
  bool _fixedAspectRatio = false;
  bool _turnOffIncomingVideo = false;
  bool _hideSelfView = false;
  bool _pictureInPictureMode = true;
  bool _noiseCancellation = false;
  bool _turnOffIncomingAudio = false;
  bool _turnOffIncomingVideoDisplay = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Security section
          _buildSectionHeader('Security'),
          _buildToggleItem(
            'Choose new host on leave',
            _chooseNewHostOnLeave,
            (value) => setState(() => _chooseNewHostOnLeave = value),
            isFirst: true,
          ),
          _buildToggleItem(
            'Lock meeting',
            _lockMeeting,
            (value) => setState(() => _lockMeeting = value),
            isLast: true,
          ),

          const SizedBox(height: 16),

          // Video section
          _buildSectionHeader('Video'),
          _buildToggleItem(
            'Background blur',
            _backgroundBlur,
            (value) => setState(() => _backgroundBlur = value),
            isFirst: true,
          ),
          _buildToggleItem(
            'Fixed aspect ratio',
            _fixedAspectRatio,
            (value) => setState(() => _fixedAspectRatio = value),
          ),
          _buildToggleItem(
            'Turn off incoming video',
            _turnOffIncomingVideo,
            (value) => setState(() => _turnOffIncomingVideo = value),
          ),
          _buildToggleItem(
            'Hide self view',
            _hideSelfView,
            (value) => setState(() => _hideSelfView = value),
          ),
          _buildToggleItem(
            'Picture-in-picture mode',
            _pictureInPictureMode,
            (value) => setState(() => _pictureInPictureMode = value),
            isLast: true,
          ),

          const SizedBox(height: 16),

          // Audio section
          _buildSectionHeader('Audio'),
          _buildToggleItem(
            'Noise cancellation',
            _noiseCancellation,
            (value) => setState(() => _noiseCancellation = value),
            isFirst: true,
          ),
          _buildToggleItem(
            'Turn off incoming audio',
            _turnOffIncomingAudio,
            (value) => setState(() => _turnOffIncomingAudio = value),
          ),
          _buildToggleItem(
            'Picture-in-picture mode',
            _pictureInPictureMode,
            (value) => setState(() => _pictureInPictureMode = value),
            isLast: true,
          ),

          const SizedBox(height: 16),

          // Display section
          _buildSectionHeader('Display'),
          _buildToggleItem(
            'Turn off incoming video',
            _turnOffIncomingVideoDisplay,
            (value) => setState(() => _turnOffIncomingVideoDisplay = value),
            isFirst: true,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            title,
            style: ProtonStyles.body2Semibold(color: context.colors.textWeak),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final colors = context.colors;
    final borderRadius = isFirst && isLast
        ? BorderRadius.circular(24)
        : isFirst
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : isLast
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          )
        : BorderRadius.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 76,
        padding: const EdgeInsets.all(24),
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ProtonStyles.body1Medium(
                  color: value ? colors.textNorm : colors.textWeak,
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => onChanged(!value),
              child: _CustomToggleSwitch(value: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomToggleSwitch extends StatelessWidget {
  const _CustomToggleSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 24,
      child: Stack(
        children: [
          // Track
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                color: value
                    ? const Color(0xFFABABF8) // Interaction-norm when on
                    : const Color(0xFF56566D), // Interaction-weak when off
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          // Thumb
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: value ? 20 : 2,
            top: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: const ShapeDecoration(
                color: Color(0xFF191C32), // Background-weak
                shape: OvalBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
