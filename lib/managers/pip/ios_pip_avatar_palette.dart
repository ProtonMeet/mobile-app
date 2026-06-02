/// Avatar tile colors for iOS PiP (dark theme, same order as room participant tiles).
class IosPipAvatarPalette {
  const IosPipAvatarPalette._();

  static const _backgrounds = <int>[
    0xFF413969, // purple
    0xFF2B3E40, // green
    0xFF332F62, // blue (interaction-norm)
    0xFF094A62, // blue
    0xFF3D2A3D, // red
    0xFF523A2E, // orange
  ];

  static const _profileText = <int>[
    0xFFC6BBFF, // purple
    0xFF9EEA9F, // green
    0xFFABABF8, // blue (interaction-norm)
    0xFF7BDCFF, // blue
    0xFFFF8A8A, // red
    0xFFFFB35F, // orange
  ];

  static int backgroundArgb(int colorIndex) =>
      _backgrounds[colorIndex % _backgrounds.length];

  static int profileTextArgb(int colorIndex) =>
      _profileText[colorIndex % _profileText.length];
}
