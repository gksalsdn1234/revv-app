import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/colors.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final history = RunHistoryService();
  await history.load();
  final homeLocation = HomeLocationService();
  await homeLocation.load();
  final savedRoutes = SavedRouteService();
  await savedRoutes.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(RevvApp(
    history: history,
    homeLocation: homeLocation,
    savedRoutes: savedRoutes,
  ));
}

class RevvApp extends StatelessWidget {
  final RunHistoryService history;
  final HomeLocationService homeLocation;
  final SavedRouteService savedRoutes;
  const RevvApp({
    super.key,
    required this.history,
    required this.homeLocation,
    required this.savedRoutes,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => WeatherService()),
        ChangeNotifierProvider(create: (_) => JarvisService()),
        ChangeNotifierProvider(create: (_) => RouteService()),
        ChangeNotifierProvider(create: (_) => RunSessionService()),
        ChangeNotifierProvider<RunHistoryService>.value(value: history),
        ChangeNotifierProvider<HomeLocationService>.value(value: homeLocation),
        ChangeNotifierProvider<SavedRouteService>.value(value: savedRoutes),
        ChangeNotifierProvider(create: (_) => OBDService()),
        ChangeNotifierProvider(create: (_) => ImuService()),
        ChangeNotifierProxyProvider2<LocationService, OBDService, DrivingContextService>(
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
            primary: AppColors.red,
            surface: AppColors.panel,
          ),
          splashColor: AppColors.red.withOpacity(0.2),
          highlightColor: Colors.transparent,
        ),
        home: const LoadingScreen(),
      ),
    );
  }
}
