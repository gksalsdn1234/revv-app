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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final history = RunHistoryService();
  await history.load();
  final homeLocation = HomeLocationService();
  await homeLocation.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(RevvApp(history: history, homeLocation: homeLocation));
}

class RevvApp extends StatelessWidget {
  final RunHistoryService history;
  final HomeLocationService homeLocation;
  const RevvApp({super.key, required this.history, required this.homeLocation});

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
