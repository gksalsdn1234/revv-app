import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'theme/colors.dart';
import 'theme/text_styles.dart';
import 'screens/loading_screen.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/jarvis_service.dart';
import 'services/route_service.dart';
import 'services/run_session_service.dart';
import 'services/run_history_service.dart';
import 'services/home_location_service.dart';
import 'services/saved_route_service.dart';
import 'services/obd_service.dart';
import 'services/imu_service.dart';
import 'services/driving_context_service.dart';
import 'services/settings_service.dart';
import 'services/garage_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await SupabaseService().init();

  final history = RunHistoryService();
  await history.load();
  final homeLocation = HomeLocationService();
  await homeLocation.load();
  final savedRoutes = SavedRouteService();
  await savedRoutes.load();
  final settings = SettingsService();
  await settings.load();
  final garage = GarageService();
  await garage.load();

  history.syncWithCloud();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    RevvApp(
      history: history,
      homeLocation: homeLocation,
      savedRoutes: savedRoutes,
      settings: settings,
      garage: garage,
    ),
  );
}

class RevvApp extends StatelessWidget {
  final RunHistoryService history;
  final HomeLocationService homeLocation;
  final SavedRouteService savedRoutes;
  final SettingsService settings;
  final GarageService garage;
  const RevvApp({
    super.key,
    required this.history,
    required this.homeLocation,
    required this.savedRoutes,
    required this.settings,
    required this.garage,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => WeatherService()),
        ChangeNotifierProvider(create: (_) => RouteService()),
        ChangeNotifierProvider(create: (_) => RunSessionService()),
        ChangeNotifierProvider<RunHistoryService>.value(value: history),
        ChangeNotifierProvider<HomeLocationService>.value(value: homeLocation),
        ChangeNotifierProvider<SavedRouteService>.value(value: savedRoutes),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProxyProvider<SettingsService, JarvisService>(
          create: (_) => JarvisService(),
          update: (_, settings, jarvis) {
            jarvis ??= JarvisService();
            jarvis.applySettings(settings);
            return jarvis;
          },
        ),
        ChangeNotifierProvider<GarageService>.value(value: garage),
        ChangeNotifierProvider.value(value: SupabaseService()),
        ChangeNotifierProvider(create: (_) => OBDService()),
        ChangeNotifierProvider(create: (_) => ImuService()),
        ChangeNotifierProxyProvider2<
          LocationService,
          OBDService,
          DrivingContextService
        >(
          create: (_) => DrivingContextService(),
          update: (_, loc, obd, ctx) {
            ctx ??= DrivingContextService();
            ctx.updateFromGPS(loc.currentPosition?.heading, loc.speedKmh);
            ctx.updateFromOBD(obd.data?.rpm, obd.data?.speedKmh);
            return ctx;
          },
        ),
      ],
      child: MaterialApp(
        title: 'REVV',
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
    );
  }
}
