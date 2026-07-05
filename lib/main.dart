import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/colors.dart';
import 'theme/text_styles.dart';
import 'screens/loading_screen.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/route_service.dart';
import 'services/run_session_service.dart';
import 'services/run_history_service.dart';
import 'services/imu_service.dart';
import 'services/settings_service.dart';
import 'services/supabase_service.dart';
import 'services/crash_reporting.dart';
import 'services/crew_channel_service.dart';
import 'labs/walkie/walkie_ptt_controller.dart';

Future<void> main() => runWithCrashReporting(_startApp);

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService().init();

  final history = RunHistoryService();
  await history.load();
  final settings = SettingsService();
  await settings.load();

  history.syncWithCloud();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(RevvApp(history: history, settings: settings));
}

class RevvApp extends StatelessWidget {
  final RunHistoryService history;
  final SettingsService settings;
  const RevvApp({super.key, required this.history, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => WeatherService()),
        ChangeNotifierProvider(create: (_) => RouteService()),
        ChangeNotifierProvider(create: (_) => RunSessionService()),
        ChangeNotifierProvider<RunHistoryService>.value(value: history),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider.value(value: SupabaseService()),
        ChangeNotifierProvider(create: (_) => ImuService()),
        // 크루 워키토키: 랩과 주행화면이 같은 참여 상태·전송 파이프라인을 공유한다.
        // 참여 전엔 네트워크를 열지 않아 프로덕션에서도 무해하게 대기한다.
        ChangeNotifierProvider(create: (_) => CrewChannelService()),
        Provider<WalkiePttController>(
          create: (_) => PttServiceWalkieController.production(),
          dispose: (_, controller) => controller.dispose(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (_, settings, _) => MaterialApp(
          title: 'REVV',
          locale: Locale(settings.appLanguage.code),
          supportedLocales: const [
            Locale('ko'),
            Locale('en'),
            Locale('fr'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.bg,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primaryContainer,
              secondary: AppColors.warning,
              surface: AppColors.panel,
              error: AppColors.danger,
              onPrimary: AppColors.onPrimary,
              onSurface: AppColors.textPrimary,
            ),
            textTheme: TextTheme(
              displayLarge: AppText.display(size: 56),
              headlineMedium: AppText.body(size: 24, weight: FontWeight.w800),
              titleMedium: AppText.body(size: 16, weight: FontWeight.w700),
              bodyMedium: AppText.body(),
              labelMedium: AppText.technicalLabel(),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: AppColors.bg.withValues(alpha: 0.82),
              foregroundColor: AppColors.textPrimary,
              surfaceTintColor: Colors.transparent,
            ),
            cardColor: AppColors.panel2,
            dividerColor: AppColors.outlineVariant,
            splashColor: AppColors.primaryContainer.withValues(alpha: 0.16),
            highlightColor: Colors.transparent,
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: AppColors.surfaceLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.24),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.24),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryContainer),
              ),
            ),
          ),
          home: const LoadingScreen(),
        ),
      ),
    );
  }
}
