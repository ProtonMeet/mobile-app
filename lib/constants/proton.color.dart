import 'package:flutter/material.dart';

@immutable
class ProtonColors extends ThemeExtension<ProtonColors> {
  // Base colors
  final Color white;
  final Color clear;
  final Color black;

  // Background colors
  final Color backgroundNorm;
  final Color backgroundSecondary;
  final Color backgroundWelcomePage;
  final Color defaultLoadBackgroundLight;
  final Color defaultLoadBackgroundDark;
  final Color backgroundCard;
  final Color popupBackground;
  final Color controlBarBtnBackground;
  final Color blurBottomSheetBackground;
  final Color backgroundStrong;
  final Color backgroundJoinMeeting;
  final Color backgroundSheetPanel;
  final Color backgroundDark;
  final Color backgroundPopupMenu;
  final Color backgroundSheetAlpha;
  final Color backgroundTimePicker;

  // Text colors
  final Color textNorm;
  final Color iconNorm;
  final Color textDisable;
  final Color textHint;
  final Color textWeak;
  final Color textInverted;
  final Color interActionWeakDisable;
  final Color interActionWeakPressed;

  // Slider colors
  final Color sliderActiveColor;
  final Color sliderInactiveColor;

  // Notification colors
  final Color signalWaning;
  final Color notificationWaningBackground;
  final Color notificationSuccess;
  final Color notificationError;
  final Color notificationErrorBackground;
  final Color notificationNorm;

  // Other colors
  final Color launchBackground;
  final Color expansionShadow;
  final Color loadingShadow;
  final Color inputDoneOverlay;
  final Color circularProgressIndicatorBackGround;
  final Color protonBlue;

  // Drawer colors
  final Color drawerBackground;
  final Color drawerBackgroundHighlight;

  // Drawer wallet/account text colors
  final Color drawerWalletOrange1Text;
  final Color drawerWalletPink1Text;
  final Color drawerWalletPurple1Text;
  final Color drawerWalletBlue1Text;
  final Color drawerWalletGreen1Text;

  // Avatar colors
  final Color avatarPurple1Text;
  final Color avatarPurple1Background;
  final Color avatarGreen1Text;
  final Color avatarGreen1Background;
  final Color avatarBlue2Text;
  final Color avatarBlue2Background;
  final Color avatarBlue1Text;
  final Color avatarBlue1Background;
  final Color avatarRed1Text;
  final Color avatarRed1Background;
  final Color avatarOrange1Text;
  final Color avatarOrange1Background;

  // AppBar colors
  final Color appBorderNorm;

  // New colors.
  final Color interActionWeekMinor1;
  final Color interActionWeekMinor2;
  final Color interActionWeakMinor3;
  final Color controlButtonBackground;
  final Color deviceSelectorDisabledBackground;
  final Color deviceSelectorDisabledCircleAvatarBackground;
  final Color interActionWeak;
  final Color interActionNorm;
  final Color interActionNormMajor1;
  final Color interActionNormMinor3;
  final Color signalDanger;
  final Color signalDangerMajor3;
  final Color borderCard;
  final Color interActionPurpleMinor3;
  final Color interActionPurpleMinor1;
  final Color redInteractionNormMajor1;
  final Color greenInteractionNormMajor1;
  final Color meetingHeaderTextColor;
  final Color meetingHeaderGradientStart;
  final Color meetingHeaderGradientEnd;

  const ProtonColors({
    required this.white,
    required this.clear,
    required this.black,
    required this.backgroundNorm,
    required this.backgroundSecondary,
    required this.backgroundWelcomePage,
    required this.defaultLoadBackgroundLight,
    required this.defaultLoadBackgroundDark,
    required this.backgroundSheetPanel,
    required this.backgroundCard,
    required this.popupBackground,
    required this.backgroundDark,
    required this.textNorm,
    required this.iconNorm,
    required this.textDisable,
    required this.textHint,
    required this.textWeak,
    required this.textInverted,
    required this.interActionWeakDisable,
    required this.interActionWeakPressed,
    required this.sliderActiveColor,
    required this.sliderInactiveColor,
    required this.signalWaning,
    required this.notificationWaningBackground,
    required this.notificationSuccess,
    required this.notificationError,
    required this.notificationErrorBackground,
    required this.notificationNorm,
    required this.launchBackground,
    required this.expansionShadow,
    required this.loadingShadow,
    required this.inputDoneOverlay,
    required this.circularProgressIndicatorBackGround,
    required this.protonBlue,
    required this.drawerBackground,
    required this.drawerBackgroundHighlight,
    required this.drawerWalletOrange1Text,
    required this.drawerWalletPink1Text,
    required this.drawerWalletPurple1Text,
    required this.drawerWalletBlue1Text,
    required this.drawerWalletGreen1Text,
    required this.avatarOrange1Text,
    required this.avatarOrange1Background,
    required this.avatarRed1Text,
    required this.avatarRed1Background,
    required this.avatarPurple1Text,
    required this.avatarPurple1Background,
    required this.avatarBlue1Text,
    required this.avatarBlue1Background,
    required this.avatarGreen1Text,
    required this.avatarGreen1Background,
    required this.avatarBlue2Text,
    required this.avatarBlue2Background,
    required this.appBorderNorm,
    required this.interActionWeakMinor3,
    required this.controlButtonBackground,
    required this.deviceSelectorDisabledBackground,
    required this.deviceSelectorDisabledCircleAvatarBackground,
    required this.interActionWeak,
    required this.interActionNorm,
    required this.interActionNormMajor1,
    required this.interActionWeekMinor1,
    required this.interActionWeekMinor2,
    required this.interActionNormMinor3,
    required this.signalDanger,
    required this.signalDangerMajor3,
    required this.borderCard,
    required this.controlBarBtnBackground,
    required this.blurBottomSheetBackground,
    required this.backgroundStrong,
    required this.backgroundJoinMeeting,
    required this.interActionPurpleMinor1,
    required this.interActionPurpleMinor3,
    required this.backgroundPopupMenu,
    required this.backgroundSheetAlpha,
    required this.redInteractionNormMajor1,
    required this.meetingHeaderTextColor,
    required this.meetingHeaderGradientStart,
    required this.meetingHeaderGradientEnd,
    required this.backgroundTimePicker,
    required this.greenInteractionNormMajor1,
  });

  @override
  ProtonColors copyWith({
    Color? white,
    Color? clear,
    Color? black,
    Color? backgroundNorm,
    Color? backgroundSecondary,
    Color? backgroundWelcomePage,
    Color? defaultLoadBackgroundLight,
    Color? defaultLoadBackgroundDark,
    Color? backgroundSheetPanel,
    Color? backgroundCard,
    Color? popupBackground,
    Color? controlBarBtnBackground,
    Color? backgroundDark,
    Color? textNorm,
    Color? iconNorm,
    Color? textDisable,
    Color? textHint,
    Color? textWeak,
    Color? textInverted,
    Color? interActionWeakDisable,
    Color? interActionWeakPressed,
    Color? sliderActiveColor,
    Color? sliderInactiveColor,
    Color? notificationWaning,
    Color? notificationWaningBackground,
    Color? notificationSuccess,
    Color? notificationError,
    Color? notificationErrorBackground,
    Color? notificationNorm,
    Color? launchBackground,
    Color? expansionShadow,
    Color? loadingShadow,
    Color? inputDoneOverlay,
    Color? circularProgressIndicatorBackGround,
    Color? protonBlue,
    Color? drawerBackground,
    Color? drawerBackgroundHighlight,
    Color? drawerWalletOrange1Text,
    Color? drawerWalletPink1Text,
    Color? drawerWalletPurple1Text,
    Color? drawerWalletBlue1Text,
    Color? drawerWalletGreen1Text,
    Color? avatarOrange1Text,
    Color? avatarOrange1Background,
    Color? avatarRed1Text,
    Color? avatarRed1Background,
    Color? avatarPurple1Text,
    Color? avatarPurple1Background,
    Color? avatarBlue1Text,
    Color? avatarBlue1Background,
    Color? avatarGreen1Text,
    Color? avatarGreen1Background,
    Color? avatarBlue2Text,
    Color? avatarBlue2Background,
    Color? appBorderNorm,
    Color? avatarGreenText,
    Color? avatarPurpleText,
    Color? avatarPinkText,
    Color? avatarBlueText,
    Color? avatarRedText,
    Color? avatarOrangeText,
    Color? interActionWeakMinor3,
    Color? interActionWeekMinor2,
    Color? interActionNormMajor1,
    Color? interactionWeekMinor1,
    Color? controlButtonBackground,
    Color? controlButtonCircleAvatarBackground,
    Color? deviceSelectorDisabledBackground,
    Color? deviceSelectorDisabledCircleAvatarBackground,
    Color? interActionNorm,
    Color? interActionWeak,
    Color? interActionNormMinor3,
    Color? signalDanger,
    Color? signalDangerMajor3,
    Color? borderCard,
    Color? blurBottomSheetBackground,
    Color? backgroundStrong,
    Color? backgroundJoinMeeting,
    Color? interActionPurpleMinor3,
    Color? interActionPurpleMinor1,
    Color? backgroundPopupMenu,
    Color? backgroundSheetAlpha,
    Color? backgroundAccountSwitcherSection,
    Color? borderAccountSwitcherSection,
    Color? redInteractionNormMajor1,
    Color? meetingHeaderTextColor,
    Color? meetingHeaderGradientStart,
    Color? meetingHeaderGradientEnd,
    Color? backgroundTimePicker,
    Color? greenInteractionNormMajor1,
  }) {
    return ProtonColors(
      white: white ?? this.white,
      clear: clear ?? this.clear,
      black: black ?? this.black,
      backgroundNorm: backgroundNorm ?? this.backgroundNorm,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      backgroundWelcomePage:
          backgroundWelcomePage ?? this.backgroundWelcomePage,
      defaultLoadBackgroundLight:
          defaultLoadBackgroundLight ?? this.defaultLoadBackgroundLight,
      defaultLoadBackgroundDark:
          defaultLoadBackgroundDark ?? this.defaultLoadBackgroundDark,
      backgroundSheetPanel: backgroundSheetPanel ?? this.backgroundSheetPanel,
      backgroundCard: backgroundCard ?? this.backgroundCard,
      popupBackground: popupBackground ?? this.popupBackground,
      controlBarBtnBackground:
          controlBarBtnBackground ?? this.controlBarBtnBackground,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      textNorm: textNorm ?? this.textNorm,
      iconNorm: iconNorm ?? this.iconNorm,
      textDisable: textDisable ?? this.textDisable,
      textHint: textHint ?? this.textHint,
      textWeak: textWeak ?? this.textWeak,
      textInverted: textInverted ?? this.textInverted,
      interActionWeakDisable:
          interActionWeakDisable ?? this.interActionWeakDisable,
      interActionWeakPressed:
          interActionWeakPressed ?? this.interActionWeakPressed,
      sliderActiveColor: sliderActiveColor ?? this.sliderActiveColor,
      sliderInactiveColor: sliderInactiveColor ?? this.sliderInactiveColor,
      signalWaning: notificationWaning ?? signalWaning,
      notificationWaningBackground:
          notificationWaningBackground ?? this.notificationWaningBackground,
      notificationSuccess: notificationSuccess ?? this.notificationSuccess,
      notificationError: notificationError ?? this.notificationError,
      notificationErrorBackground:
          notificationErrorBackground ?? this.notificationErrorBackground,
      notificationNorm: notificationNorm ?? this.notificationNorm,
      launchBackground: launchBackground ?? this.launchBackground,
      expansionShadow: expansionShadow ?? this.expansionShadow,
      loadingShadow: loadingShadow ?? this.loadingShadow,
      inputDoneOverlay: inputDoneOverlay ?? this.inputDoneOverlay,
      circularProgressIndicatorBackGround:
          circularProgressIndicatorBackGround ??
          this.circularProgressIndicatorBackGround,
      protonBlue: protonBlue ?? this.protonBlue,
      drawerBackground: drawerBackground ?? this.drawerBackground,
      drawerBackgroundHighlight:
          drawerBackgroundHighlight ?? this.drawerBackgroundHighlight,
      drawerWalletOrange1Text:
          drawerWalletOrange1Text ?? this.drawerWalletOrange1Text,
      drawerWalletPink1Text:
          drawerWalletPink1Text ?? this.drawerWalletPink1Text,
      drawerWalletPurple1Text:
          drawerWalletPurple1Text ?? this.drawerWalletPurple1Text,
      drawerWalletBlue1Text:
          drawerWalletBlue1Text ?? this.drawerWalletBlue1Text,
      drawerWalletGreen1Text:
          drawerWalletGreen1Text ?? this.drawerWalletGreen1Text,
      avatarOrange1Text: avatarOrange1Text ?? this.avatarOrange1Text,
      avatarOrange1Background:
          avatarOrange1Background ?? this.avatarOrange1Background,
      avatarRed1Text: avatarRed1Text ?? this.avatarRed1Text,
      avatarRed1Background: avatarRed1Background ?? this.avatarRed1Background,
      avatarPurple1Text: avatarPurple1Text ?? this.avatarPurple1Text,
      avatarPurple1Background:
          avatarPurple1Background ?? this.avatarPurple1Background,
      avatarBlue1Text: avatarBlue1Text ?? this.avatarBlue1Text,
      avatarBlue1Background:
          avatarBlue1Background ?? this.avatarBlue1Background,
      avatarGreen1Text: avatarGreen1Text ?? this.avatarGreen1Text,
      avatarGreen1Background:
          avatarGreen1Background ?? this.avatarGreen1Background,
      avatarBlue2Text: avatarBlue2Text ?? this.avatarBlue2Text,
      avatarBlue2Background:
          avatarBlue2Background ?? this.avatarBlue2Background,
      appBorderNorm: appBorderNorm ?? this.appBorderNorm,
      interActionNormMajor1:
          interActionNormMajor1 ?? this.interActionNormMajor1,
      interActionWeekMinor1: interactionWeekMinor1 ?? interActionWeekMinor1,
      interActionWeekMinor2:
          interActionWeekMinor2 ?? this.interActionWeekMinor2,
      interActionWeakMinor3:
          interActionWeakMinor3 ?? this.interActionWeakMinor3,
      controlButtonBackground:
          controlButtonBackground ?? this.controlButtonBackground,
      deviceSelectorDisabledBackground:
          deviceSelectorDisabledBackground ??
          this.deviceSelectorDisabledBackground,
      deviceSelectorDisabledCircleAvatarBackground:
          deviceSelectorDisabledCircleAvatarBackground ??
          this.deviceSelectorDisabledCircleAvatarBackground,
      interActionWeak: interActionWeak ?? this.interActionWeak,
      interActionNorm: interActionNorm ?? this.interActionNorm,
      interActionNormMinor3:
          interActionNormMinor3 ?? this.interActionNormMinor3,
      signalDanger: signalDanger ?? this.signalDanger,
      signalDangerMajor3: signalDangerMajor3 ?? this.signalDangerMajor3,
      borderCard: borderCard ?? this.borderCard,
      blurBottomSheetBackground:
          blurBottomSheetBackground ?? this.blurBottomSheetBackground,
      backgroundStrong: backgroundStrong ?? this.backgroundStrong,
      backgroundJoinMeeting:
          backgroundJoinMeeting ?? this.backgroundJoinMeeting,
      interActionPurpleMinor3:
          interActionPurpleMinor3 ?? this.interActionPurpleMinor3,
      interActionPurpleMinor1:
          interActionPurpleMinor1 ?? this.interActionPurpleMinor1,
      backgroundPopupMenu: backgroundPopupMenu ?? this.backgroundPopupMenu,
      backgroundSheetAlpha: backgroundSheetAlpha ?? this.backgroundSheetAlpha,
      redInteractionNormMajor1:
          redInteractionNormMajor1 ?? this.redInteractionNormMajor1,
      meetingHeaderTextColor:
          meetingHeaderTextColor ?? this.meetingHeaderTextColor,
      meetingHeaderGradientStart:
          meetingHeaderGradientStart ?? this.meetingHeaderGradientStart,
      meetingHeaderGradientEnd:
          meetingHeaderGradientEnd ?? this.meetingHeaderGradientEnd,
      backgroundTimePicker: backgroundTimePicker ?? this.backgroundTimePicker,
      greenInteractionNormMajor1:
          greenInteractionNormMajor1 ?? this.greenInteractionNormMajor1,
    );
  }

  @override
  ProtonColors lerp(ThemeExtension<ProtonColors>? other, double t) {
    if (other is! ProtonColors) {
      return this;
    }
    return ProtonColors(
      white: Color.lerp(white, other.white, t)!,
      clear: Color.lerp(clear, other.clear, t)!,
      black: Color.lerp(black, other.black, t)!,
      backgroundNorm: Color.lerp(backgroundNorm, other.backgroundNorm, t)!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      backgroundWelcomePage: Color.lerp(
        backgroundWelcomePage,
        other.backgroundWelcomePage,
        t,
      )!,
      defaultLoadBackgroundLight: Color.lerp(
        defaultLoadBackgroundLight,
        other.defaultLoadBackgroundLight,
        t,
      )!,
      defaultLoadBackgroundDark: Color.lerp(
        defaultLoadBackgroundDark,
        other.defaultLoadBackgroundDark,
        t,
      )!,
      backgroundSheetPanel: Color.lerp(
        backgroundSheetPanel,
        other.backgroundSheetPanel,
        t,
      )!,
      backgroundCard: Color.lerp(backgroundCard, other.backgroundCard, t)!,
      popupBackground: Color.lerp(popupBackground, other.popupBackground, t)!,
      controlBarBtnBackground: Color.lerp(
        controlBarBtnBackground,
        other.controlBarBtnBackground,
        t,
      )!,
      backgroundDark: Color.lerp(backgroundDark, other.backgroundDark, t)!,
      textNorm: Color.lerp(textNorm, other.textNorm, t)!,
      iconNorm: Color.lerp(iconNorm, other.iconNorm, t)!,
      textDisable: Color.lerp(textDisable, other.textDisable, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      textWeak: Color.lerp(textWeak, other.textWeak, t)!,
      textInverted: Color.lerp(textInverted, other.textInverted, t)!,
      interActionWeakDisable: Color.lerp(
        interActionWeakDisable,
        other.interActionWeakDisable,
        t,
      )!,
      interActionWeakPressed: Color.lerp(
        interActionWeakPressed,
        other.interActionWeakPressed,
        t,
      )!,
      sliderActiveColor: Color.lerp(
        sliderActiveColor,
        other.sliderActiveColor,
        t,
      )!,
      sliderInactiveColor: Color.lerp(
        sliderInactiveColor,
        other.sliderInactiveColor,
        t,
      )!,
      signalWaning: Color.lerp(signalWaning, other.signalWaning, t)!,
      notificationWaningBackground: Color.lerp(
        notificationWaningBackground,
        other.notificationWaningBackground,
        t,
      )!,
      notificationSuccess: Color.lerp(
        notificationSuccess,
        other.notificationSuccess,
        t,
      )!,
      notificationError: Color.lerp(
        notificationError,
        other.notificationError,
        t,
      )!,
      notificationErrorBackground: Color.lerp(
        notificationErrorBackground,
        other.notificationErrorBackground,
        t,
      )!,
      notificationNorm: Color.lerp(
        notificationNorm,
        other.notificationNorm,
        t,
      )!,
      launchBackground: Color.lerp(
        launchBackground,
        other.launchBackground,
        t,
      )!,
      expansionShadow: Color.lerp(expansionShadow, other.expansionShadow, t)!,
      loadingShadow: Color.lerp(loadingShadow, other.loadingShadow, t)!,
      inputDoneOverlay: Color.lerp(
        inputDoneOverlay,
        other.inputDoneOverlay,
        t,
      )!,
      circularProgressIndicatorBackGround: Color.lerp(
        circularProgressIndicatorBackGround,
        other.circularProgressIndicatorBackGround,
        t,
      )!,
      protonBlue: Color.lerp(protonBlue, other.protonBlue, t)!,
      drawerBackground: Color.lerp(
        drawerBackground,
        other.drawerBackground,
        t,
      )!,
      drawerBackgroundHighlight: Color.lerp(
        drawerBackgroundHighlight,
        other.drawerBackgroundHighlight,
        t,
      )!,
      drawerWalletOrange1Text: Color.lerp(
        drawerWalletOrange1Text,
        other.drawerWalletOrange1Text,
        t,
      )!,
      drawerWalletPink1Text: Color.lerp(
        drawerWalletPink1Text,
        other.drawerWalletPink1Text,
        t,
      )!,
      drawerWalletPurple1Text: Color.lerp(
        drawerWalletPurple1Text,
        other.drawerWalletPurple1Text,
        t,
      )!,
      drawerWalletBlue1Text: Color.lerp(
        drawerWalletBlue1Text,
        other.drawerWalletBlue1Text,
        t,
      )!,
      drawerWalletGreen1Text: Color.lerp(
        drawerWalletGreen1Text,
        other.drawerWalletGreen1Text,
        t,
      )!,
      avatarOrange1Text: Color.lerp(
        avatarOrange1Text,
        other.avatarOrange1Text,
        t,
      )!,
      avatarOrange1Background: Color.lerp(
        avatarOrange1Background,
        other.avatarOrange1Background,
        t,
      )!,
      avatarRed1Text: Color.lerp(avatarRed1Text, other.avatarRed1Text, t)!,
      avatarRed1Background: Color.lerp(
        avatarRed1Background,
        other.avatarRed1Background,
        t,
      )!,
      avatarPurple1Text: Color.lerp(
        avatarPurple1Text,
        other.avatarPurple1Text,
        t,
      )!,
      avatarPurple1Background: Color.lerp(
        avatarPurple1Background,
        other.avatarPurple1Background,
        t,
      )!,
      avatarBlue1Text: Color.lerp(avatarBlue1Text, other.avatarBlue1Text, t)!,
      avatarBlue1Background: Color.lerp(
        avatarBlue1Background,
        other.avatarBlue1Background,
        t,
      )!,
      avatarGreen1Text: Color.lerp(
        avatarGreen1Text,
        other.avatarGreen1Text,
        t,
      )!,
      avatarGreen1Background: Color.lerp(
        avatarGreen1Background,
        other.avatarGreen1Background,
        t,
      )!,
      avatarBlue2Text: Color.lerp(avatarBlue2Text, other.avatarBlue2Text, t)!,
      avatarBlue2Background: Color.lerp(
        avatarBlue2Background,
        other.avatarBlue2Background,
        t,
      )!,
      appBorderNorm: Color.lerp(appBorderNorm, other.appBorderNorm, t)!,
      interActionNormMajor1: Color.lerp(
        interActionNormMajor1,
        other.interActionNormMajor1,
        t,
      )!,
      interActionWeekMinor2: Color.lerp(
        interActionWeekMinor2,
        other.interActionWeekMinor2,
        t,
      )!,
      interActionNorm: Color.lerp(interActionNorm, other.interActionNorm, t)!,
      interActionWeakMinor3: Color.lerp(
        interActionWeakMinor3,
        other.interActionWeakMinor3,
        t,
      )!,
      controlButtonBackground: Color.lerp(
        controlButtonBackground,
        other.controlButtonBackground,
        t,
      )!,
      deviceSelectorDisabledBackground: Color.lerp(
        deviceSelectorDisabledBackground,
        other.deviceSelectorDisabledBackground,
        t,
      )!,
      deviceSelectorDisabledCircleAvatarBackground: Color.lerp(
        deviceSelectorDisabledCircleAvatarBackground,
        other.deviceSelectorDisabledCircleAvatarBackground,
        t,
      )!,
      interActionWeak: Color.lerp(interActionWeak, other.interActionWeak, t)!,
      interActionWeekMinor1: Color.lerp(
        interActionWeekMinor1,
        other.interActionWeekMinor1,
        t,
      )!,
      interActionNormMinor3: Color.lerp(
        interActionNormMinor3,
        other.interActionNormMinor3,
        t,
      )!,
      signalDanger: Color.lerp(signalDanger, other.signalDanger, t)!,
      signalDangerMajor3: Color.lerp(
        signalDangerMajor3,
        other.signalDangerMajor3,
        t,
      )!,
      borderCard: Color.lerp(borderCard, other.borderCard, t)!,
      blurBottomSheetBackground: Color.lerp(
        blurBottomSheetBackground,
        other.blurBottomSheetBackground,
        t,
      )!,
      backgroundStrong: Color.lerp(
        backgroundStrong,
        other.backgroundStrong,
        t,
      )!,
      backgroundJoinMeeting: Color.lerp(
        backgroundJoinMeeting,
        other.backgroundJoinMeeting,
        t,
      )!,
      interActionPurpleMinor3: Color.lerp(
        interActionPurpleMinor3,
        other.interActionPurpleMinor3,
        t,
      )!,
      interActionPurpleMinor1: Color.lerp(
        interActionPurpleMinor1,
        other.interActionPurpleMinor1,
        t,
      )!,
      backgroundPopupMenu: Color.lerp(
        backgroundPopupMenu,
        other.backgroundPopupMenu,
        t,
      )!,
      backgroundSheetAlpha: Color.lerp(
        backgroundSheetAlpha,
        other.backgroundSheetAlpha,
        t,
      )!,
      redInteractionNormMajor1: Color.lerp(
        redInteractionNormMajor1,
        other.redInteractionNormMajor1,
        t,
      )!,
      meetingHeaderTextColor: Color.lerp(
        meetingHeaderTextColor,
        other.meetingHeaderTextColor,
        t,
      )!,
      meetingHeaderGradientStart: Color.lerp(
        meetingHeaderGradientStart,
        other.meetingHeaderGradientStart,
        t,
      )!,
      meetingHeaderGradientEnd: Color.lerp(
        meetingHeaderGradientEnd,
        other.meetingHeaderGradientEnd,
        t,
      )!,
      backgroundTimePicker: Color.lerp(
        backgroundTimePicker,
        other.backgroundTimePicker,
        t,
      )!,
      greenInteractionNormMajor1: Color.lerp(
        greenInteractionNormMajor1,
        other.greenInteractionNormMajor1,
        t,
      )!,
    );
  }
}

// Light theme colors
final lightColorsExtension = ProtonColors(
  white: Colors.white,
  clear: Colors.transparent,
  black: const Color(0xFF000000),
  backgroundNorm: const Color(0xFF16161F),
  backgroundSecondary: const Color(0xFFFFFFFF),
  backgroundWelcomePage: const Color(0xFFFEF0E5),
  defaultLoadBackgroundLight: const Color(0xFFFFFFFF),
  defaultLoadBackgroundDark: const Color(0xFF191C32),
  backgroundSheetPanel: const Color(0x001a1a28).withValues(alpha: 0.60),
  backgroundCard: const Color(0xFF232331),
  popupBackground: const Color(0x1A1A28CC),
  backgroundDark: const Color(0xFF16161F),
  textNorm: const Color(0xFF191C32),
  iconNorm: const Color(0xFF191C32),
  textDisable: const Color(0xffCED0DE),
  textHint: const Color(0xFF9395A4),
  textWeak: const Color(0xFF535964),
  textInverted: const Color(0xFFFFFFFF),
  interActionWeakDisable: const Color(0xFFE6E8EC),
  interActionWeakPressed: const Color(0xFFE2E2E2),
  sliderActiveColor: const Color(0xFF8B8DF9),
  sliderInactiveColor: const Color(0xFFCED0DE),
  signalWaning: const Color(0xFFFE9964),
  notificationWaningBackground: const Color(0xFFFFEDE4),
  notificationSuccess: const Color(0xFF5DA662),
  notificationError: const Color(0xFFED4349),
  notificationErrorBackground: const Color(0xFFFFE0E0),
  notificationNorm: const Color(0xFF767DFF),
  launchBackground: const Color(0xff191927),
  expansionShadow: const Color(0xFFE0E2FF),
  loadingShadow: const Color(0x22767DFF),
  inputDoneOverlay: const Color(0xFFD9DDE1),
  circularProgressIndicatorBackGround: const Color.fromARGB(51, 255, 255, 255),
  protonBlue: const Color(0xFF767DFF),
  drawerBackground: const Color(0xFF222247),
  drawerBackgroundHighlight: const Color(0x2AFFFFFF),
  drawerWalletOrange1Text: const Color(0xFFFF8D52),
  drawerWalletPink1Text: const Color(0xFFFF68DE),
  drawerWalletPurple1Text: const Color(0xff9553F9),
  drawerWalletBlue1Text: const Color(0xFF536CFF),
  drawerWalletGreen1Text: const Color(0xFF52CC9C),
  avatarOrange1Text: const Color(0xffFF6464),
  avatarOrange1Background: const Color(0xffffede4),
  avatarRed1Text: const Color(0xffFF8A8A),
  avatarRed1Background: const Color(0xff3D2A3D),
  avatarPurple1Text: const Color(0xff9553F9),
  avatarPurple1Background: const Color(0xffebe7ff),
  avatarBlue2Text: const Color(0xffABABF8),
  avatarBlue2Background: const Color(0xff332F62),
  avatarBlue1Text: const Color(0xff0047AB),
  avatarBlue1Background: const Color(0xffe0f0ff),
  avatarGreen1Text: const Color(0xff9EEA9F),
  avatarGreen1Background: const Color(0xff2B3E40),
  appBorderNorm: const Color(0xFFE6E8EC),
  interActionWeakMinor3: const Color(0xFF1A1A28),
  interActionWeekMinor2: const Color(0xFF27283C),
  controlButtonBackground: const Color(0xFF131314),
  deviceSelectorDisabledBackground: const Color(0xFFED4349),
  deviceSelectorDisabledCircleAvatarBackground: const Color(0xFFFF6666),
  interActionWeak: const Color(0xFF131314),
  interActionNorm: const Color(0xFF968AEF),
  interActionNormMajor1: const Color(0xFFAEA4F3),
  interActionWeekMinor1: const Color(0xFFF1F1F1),
  interActionNormMinor3: const Color(0xFFE6E8EC),
  signalDanger: const Color(0xFFED4349),
  signalDangerMajor3: const Color(0xFFA62F33),
  borderCard: const Color(0xFF2E2F42),
  controlBarBtnBackground: Colors.white.withValues(alpha: 0.08),
  blurBottomSheetBackground: const Color(0x991A1A28),
  backgroundStrong: const Color(0xFF31334A),
  backgroundJoinMeeting: const Color(0xFF222247),
  interActionPurpleMinor3: const Color(0xFF413969),
  interActionPurpleMinor1: const Color(0xFFB9ABFF),
  backgroundPopupMenu: const Color(0x660B0B10),
  backgroundSheetAlpha: const Color(0xFF222247).withValues(alpha: 0.30),
  meetingHeaderTextColor: const Color(0xFFAFAFFF),
  meetingHeaderGradientStart: const Color(0x99AFAFFF),
  meetingHeaderGradientEnd: const Color(0x00AFAFFF),
  backgroundTimePicker: const Color(0xFF4A4478),
  redInteractionNormMajor1: const Color(0xFFFF8A8A),
  greenInteractionNormMajor1: const Color(0xFF9EEA9F),
);
// Dark theme colors
final darkColorsExtension = ProtonColors(
  white: Colors.white,
  clear: Colors.transparent,
  black: const Color(0xFFFFFFFF),
  backgroundNorm: const Color(0xFF16161F),
  backgroundSecondary: const Color(0xFF191C32),
  backgroundWelcomePage: const Color(0xFF151426),
  defaultLoadBackgroundLight: const Color(0xFFFFFFFF),
  defaultLoadBackgroundDark: const Color(0xFF191C32),
  backgroundSheetPanel: const Color(0x001a1a28).withValues(alpha: 0.60),
  backgroundCard: const Color(0xFF232331),
  popupBackground: const Color(0x222247CC),
  backgroundDark: const Color(0xFF16161F),
  textNorm: const Color(0xFFFFFFFF),
  iconNorm: const Color(0xFFFFFFFF),
  textDisable: const Color(0xff646481),
  textHint: const Color(0xFFA6A6B5),
  textWeak: const Color(0xFFBFBFD0),
  textInverted: const Color(0xFF191C32),
  interActionWeakDisable: const Color(0xFF454554),
  interActionWeakPressed: const Color(0xFFE2E2E2),
  sliderActiveColor: const Color(0xFF8B8DF9),
  sliderInactiveColor: const Color(0xFF1A1814),
  signalWaning: const Color(0xFFFF9761),
  notificationWaningBackground: const Color(0xFF29180F),
  notificationSuccess: const Color(0xFF88F189),
  notificationError: const Color(0xFFFB7878),
  notificationErrorBackground: const Color(0xFF3D2A3D),
  notificationNorm: const Color(0xFF9494FF),
  launchBackground: const Color(0xFFE6E6D8),
  expansionShadow: const Color(0xFF5B5BA3),
  loadingShadow: const Color(0x229494FF),
  inputDoneOverlay: const Color(0xFFD9DDE1),
  circularProgressIndicatorBackGround: const Color.fromARGB(51, 255, 255, 255),
  protonBlue: const Color(0xFFABABF8),
  drawerBackground: const Color(0xFF222247),
  drawerBackgroundHighlight: const Color(0x2AFFFFFF),
  drawerWalletOrange1Text: const Color(0xFFFF8D52),
  drawerWalletPink1Text: const Color(0xFFFF68DE),
  drawerWalletPurple1Text: const Color(0xff9553F9),
  drawerWalletBlue1Text: const Color(0xFF536CFF),
  drawerWalletGreen1Text: const Color(0xFF52CC9C),
  avatarOrange1Text: const Color(0xFFFFB35F),
  avatarOrange1Background: const Color(0xFF523A2E),
  avatarRed1Text: const Color(0xffFF8A8A),
  avatarRed1Background: const Color(0xff3D2A3D),
  avatarPurple1Text: const Color(0xFFC6BBFF),
  avatarPurple1Background: const Color(0xFF413969),
  avatarBlue1Text: const Color(0xFF7BDCFF),
  avatarBlue1Background: const Color(0xFF094A62),
  avatarBlue2Text: const Color(0xffABABF8),
  avatarBlue2Background: const Color(0xff332F62),
  avatarGreen1Text: const Color(0xff9EEA9F),
  avatarGreen1Background: const Color(0xff2B3E40),
  appBorderNorm: const Color(0xFF31334A),
  interActionWeakMinor3: const Color(0xFF1A1A28),
  interActionWeekMinor2: const Color(0xFF27283C),
  controlButtonBackground: const Color(0xFF323244),
  deviceSelectorDisabledBackground: const Color(0xFFFC4646),
  deviceSelectorDisabledCircleAvatarBackground: const Color(0xFFFC6464),
  interActionWeak: const Color(0xFF56566D),
  interActionNorm: const Color(0xFF968AEF),
  interActionNormMajor1: const Color(0xFFAEA4F3),
  interActionWeekMinor1: const Color(0xFF323244),
  interActionNormMinor3: const Color(0xFF332F62),
  signalDanger: const Color(0xFFFB8686),
  signalDangerMajor3: const Color(0xFFFC4646),
  borderCard: const Color(0xFF2E2F42),
  controlBarBtnBackground: Colors.white.withValues(alpha: 0.08),
  interActionPurpleMinor3: const Color(0xFF413969),
  blurBottomSheetBackground: const Color(0x991A1A28),
  backgroundStrong: const Color(0xFF31334A),
  backgroundJoinMeeting: const Color(0xFF222247),
  interActionPurpleMinor1: const Color(0xFFB9ABFF),
  backgroundPopupMenu: const Color(0x660B0B10),
  backgroundSheetAlpha: const Color(0xFF222247).withValues(alpha: 0.30),
  meetingHeaderTextColor: const Color(0xFFAFAFFF),
  meetingHeaderGradientStart: const Color(0x99AFAFFF),
  meetingHeaderGradientEnd: const Color(0x00AFAFFF),
  backgroundTimePicker: const Color(0xFF4A4478),
  redInteractionNormMajor1: const Color(0xFFFF8A8A),
  greenInteractionNormMajor1: const Color(0xFF9EEA9F),
);
