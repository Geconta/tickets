import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'views/login_page.dart';
import 'views/comercial_page.dart';
import 'views/admin_page.dart';
import 'views/register_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TicketsApp());
}

class TicketsApp extends StatelessWidget {
  const TicketsApp({super.key});

  Future<String?> getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      return doc.data()?['role'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestor de Tickets',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      // ✅ Usamos `home` como pantalla principal
      home: const LoginPage(),

      // ✅ Rutas adicionales sin la ruta '/'
      routes: {
        '/register': (context) => const RegisterPage(),
        '/comercial': (context) => const ComercialPage(),
        '/admin': (context) => const AdminPage(),
      },
    );
  }
}
