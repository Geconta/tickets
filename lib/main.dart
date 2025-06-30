import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'views/login_page.dart';
import 'views/comercial_page.dart';
import 'views/admin_page.dart';
import 'views/register_page.dart';

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
      debugShowCheckedModeBanner: false,
      title: 'Gestor de Tickets',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const LoginPage(),
      routes: {
        '/register': (context) => const RegisterPage(),
        '/comercial': (context) => const ComercialPage(),
        '/admin': (context) => const AdminPage(),
      },
    );
  }
}
