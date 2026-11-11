import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// Import supabase with a prefix so its AuthState doesn't clash with ours
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'features/auth/presentation/auth_screen.dart';
import 'features/hydration/presentation/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await sb.Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: Nourish360App()));
}

class Nourish360App extends StatelessWidget {
  const Nourish360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nourish360',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      // Use explicit dynamic type or reference the supabase stream cleanly
      home: StreamBuilder(
        stream: sb.Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session =
              snapshot.data?.session ??
              sb.Supabase.instance.client.auth.currentSession;

          if (session != null) {
            return const DashboardScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
