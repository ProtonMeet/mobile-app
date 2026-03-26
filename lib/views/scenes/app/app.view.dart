import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/locale.provider.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/scenes/app/app.viewmodel.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:provider/provider.dart';

class AppView extends ViewBase<AppViewModel> {
  const AppView(AppViewModel viewModel)
    : super(viewModel, const Key("AppView"));

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(
          create: (context) => viewModel.themeProvider,
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (context) => LocaleProvider(),
        ),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder:
            (
              context,
              ThemeProvider themeProvider,
              LocaleProvider localeProvider,
              child,
            ) {
              return MaterialApp(
                // ignore: avoid_redundant_argument_values
                debugShowCheckedModeBanner: kDebugMode,
                title: "Proton Meet",
                onGenerateTitle: (context) {
                  return S.of(context).app_name;
                },
                localizationsDelegates: const [
                  S.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('en', ''),
                  ...S.supportedLocales,
                ],
                locale: Provider.of<LocaleProvider>(
                  context,
                  listen: false,
                ).locale,

                /// only dark theme since we didn't fine tuned light theme yet
                theme: ThemeData(
                  colorScheme: ThemeData(
                    brightness: Brightness.dark,
                  ).colorScheme.copyWith(primary: context.colors.textNorm),
                  useMaterial3: true,
                  visualDensity: VisualDensity.adaptivePlatformDensity,
                  extensions: [
                    viewModel.darkColorScheme,
                    viewModel.darkSvgImage,
                  ],
                ),
                darkTheme: ThemeData(
                  brightness: Brightness.dark,
                  extensions: [
                    viewModel.darkColorScheme,
                    viewModel.darkSvgImage,
                  ],
                ),
                themeMode: themeProvider.getThemeMode(
                  Provider.of<ThemeProvider>(context, listen: false).themeMode,
                ),
                initialRoute: '/',
                // routes: <String, WidgetBuilder>{
                //   '/': (BuildContext context) => rootView,
                // },
                builder: EasyLoading.init(builder: FToastBuilder()),
                navigatorKey: Coordinator.rootNavigatorKey,
                onGenerateRoute: viewModel.router.onGenerateRoute,
              );
            },
      ),
    );
  }
}
