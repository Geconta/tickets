import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  Future<void> _register() async {
    setState(() => isLoading = true);
    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      final name = nameController.text.trim();
      final lastName = lastNameController.text.trim();

      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'uid': user.uid,
        'email': email,
        'name': name,
        'lastName': lastName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await user.sendEmailVerification();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Verifica tu correo'),
          content: const Text('Te hemos enviado un enlace de verificación.'),
          actions: [
            TextButton(
              onPressed: () async {
                await user.reload();
                final refreshedUser = FirebaseAuth.instance.currentUser;
                if (refreshedUser != null && refreshedUser.emailVerified) {
                  if (mounted) {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/comercial');
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Aún no has verificado el correo')),
                  );
                }
              },
              child: const Text('Ya verifiqué'),
            ),
            TextButton(
              onPressed: () {
                FirebaseAuth.instance.signOut();
                Navigator.popUntil(context, ModalRoute.withName('/login'));
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(Icons.person_add_alt_1_rounded,
                          size: 40, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Registro Comercial',
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea tu cuenta para continuar',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Nombre
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Apellidos
                    TextField(
                      controller: lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Apellidos',
                        prefixIcon: const Icon(Icons.person_2_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Correo
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Contraseña
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Botón
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _register,
                              child: const Text(
                                'Registrar',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
