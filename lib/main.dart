import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/colors.dart';
import 'theme/text_styles.dart';
import 'screens/lean_app_shell_screen.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/route_service.dart';
import 'services/run_session_service.dart';
import 'services/driven_routes_service.dart';
import 'services/run_history_service.dart';
import 'services/imu_service.dart';
import 'services/settings_service.dart';
import 'services/supabase_service.dart';
import 'services/crash_reporting.dart';
import 'services/crew_channel_service.dart';
import 'services/exploration_service.dart';
import 'services/supabase_exploration_cloud_client.dart';
import 'services/route_auto_record_service.dart';
import 'labs/walkie/walkie_ptt_controller.dart';

Future<void> main() => runWithCrashReporting(_startApp);

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppBootstrap(load: _loadApp));
}

Future<Widget> _loadApp() async {
  await SupabaseService().init();

  final settings = SettingsService();
  await settings.load();
  final exploration = ExplorationService(
    cloud: SupabaseExplorationCloudClient(),
    cloudSyncEnabled: () => settings.cloudRunStorageEnabled,
  );
  await exploration.load();
  await exploration.bindCloudIdentity(SupabaseService().uid);
  unawaited(exploration.syncWithCloud());
  final history = RunHistoryService(exploration: exploration);
  await history.load();

  history.syncWithCloud();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  return RevvApp(
    history: history,
    settings: settings,
    exploration: exploration,
  );
}

/// Renders immediately, retaining a recoverable UI if local initialization fails.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.load});
  final Future<Widget> Function() load;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<Widget> _loading = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) return snapshot.data!;
      final locale =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final failed = snapshot.hasError;
      final message = locale == 'ko'
          ? (failed ? '앱을 준비하지 못했어요. 다시 시도해 주세요.' : 'REVV 준비 중')
          : locale == 'fr'
          ? (failed
                ? 'Préparation impossible. Réessayez.'
                : 'Préparation de REVV')
          : (failed
                ? 'Could not prepare the app. Try again.'
                : 'Preparing REVV');
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!failed) const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(message, textAlign: TextAlign.center),
                    if (failed)
                      FilledButton(
                        onPressed: () {
                          final next = widget.load();
                          setState(() {
                            _loading = next;
                          });
                        },
                        child: Text(
                          locale == 'ko'
                              ? '다시 시도'
                              : locale == 'fr'
                              ? 'Réessayer'
                              : 'Retry',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class RevvApp extends StatelessWidget {
  final RunHistoryService history;
  final SettingsService settings;
  final ExplorationService exploration;
  const RevvApp({
    super.key,
    required this.history,
    required this.settings,
    required this.exploration,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => WeatherService()),
        ChangeNotifierProvider(create: (_) => RouteService()),
        ChangeNotifierProvider(create: (_) => RunSessionService()),
        ChangeNotifierProvider(
          create: (context) {
            final sessions = context.read<RunSessionService>();
            return RouteAutoRecordService(
              routes: context.read<RouteService>(),
              sessions: sessions,
              location: context.read<LocationService>(),
              onCompleted: (session) async {
                try {
                  await history.saveSession(session);
                  await sessions.clearRecovery(runId: session.runId);
                } catch (_) {
                  // The final per-drive recovery snapshot remains available.
                }
              },
            )..attach();
          },
        ),
        ChangeNotifierProvider<RunHistoryService>.value(value: history),
        ChangeNotifierProvider<ExplorationService>.value(value: exploration),
        // 정복 지도: runs를 파생한 "달린 루트" 뷰 (별도 저장 없음)
        ChangeNotifierProvider(
          create: (_) => DrivenRoutesService(history: history),
        ),
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
          supportedLocales: const [Locale('ko'), Locale('en'), Locale('fr')],
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
          home: const LeanAppShellScreen(),
        ),
      ),
    );
  }
}
