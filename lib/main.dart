import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'views/login_page.dart';
import 'views/comercial/comercial_page.dart';
import 'views/admin/admin_page.dart';
import 'views/register_page.dart';

import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://qugplttfqgjuaeqlxtxd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF1Z3BsdHRmcWdqdWFlcWx4dHhkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEwMjM0NTQsImV4cCI6MjA2NjU5OTQ1NH0.jQcAiyySvF73KVUoMqR8VMrPOJLf32HBwpEZCLHFcP0',
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TicketsApp());
}

class TicketsApp extends StatelessWidget {
  const TicketsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true, // activa el look Material 3
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF6F6F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        textTheme: GoogleFonts.poppinsTextTheme(), // tipografía moderna
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      title: 'Gestor de Tickets',
      home: const LoginPage(),
      routes: {
        '/register': (context) => const RegisterPage(),
        '/comercial': (context) => const ComercialPage(),
        '/admin': (context) => const AdminPage(),
      },
    );
  }
}
