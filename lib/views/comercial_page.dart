import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class ComercialPage extends StatefulWidget {
  const ComercialPage({super.key});

  @override
  State<ComercialPage> createState() => _ComercialPageState();
}

class _ComercialPageState extends State<ComercialPage> {
  String? scannedData;
  late MobileScannerController cameraController;
  bool isTorchOn = false;
  bool showScanner = false; // <-- Nuevo estado

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
  }

  Future<Position> _obtenerUbicacion() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) throw Exception('GPS desactivado');
    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception('Permiso denegado');
      }
    }
    if (permiso == LocationPermission.deniedForever) {
      throw Exception('Permiso denegado permanentemente');
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _guardarTicket(String codigoQR) async {
    try {
      final pos = await _obtenerUbicacion();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Usuario no autenticado");

      await firestore.FirebaseFirestore.instance.collection('tickets').add({
        'comercialId': user.uid,
        'contenido': codigoQR,
        'fechaHora': DateTime.now(),
        'geolocalizacion': firestore.GeoPoint(pos.latitude, pos.longitude),
        'estado': 'Entregado',
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✅ Ticket guardado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Error: ${e.toString()}')));
      }
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F8FFF),
        title: Text('Comercial: ${user?.email ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            showScanner = true;
          });
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Agregar nuevo ticket'),
        backgroundColor: const Color(0xFF4F8FFF),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4F8FFF), Color(0xFF235390)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: showScanner
            ? Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Escanea el ticket',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 300,
                        height: 300,
                        child: MobileScanner(
                          controller: cameraController,
                          onDetect: (capture) {
                            final code = capture.barcodes.first.rawValue;
                            if (code != null && code != scannedData) {
                              setState(() {
                                scannedData = code;
                                showScanner = false; // Oculta el escáner
                              });
                              _guardarTicket(code);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            showScanner = false;
                          });
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: Colors.indigo[700]),
                        const SizedBox(width: 8),
                        const Text('Rol: Comercial',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: StreamBuilder(
                      stream: firestore.FirebaseFirestore.instance
                          .collection('tickets')
                          .where('comercialId', isEqualTo: user?.uid)
                          .orderBy('fechaHora', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final tickets = snapshot.data!.docs;
                        if (tickets.isEmpty) {
                          return const Center(child: Text('Sin historial.'));
                        }
                        return ListView(
                          children: tickets.map((doc) {
                            final data = doc.data();
                            return ListTile(
                              leading: const Icon(Icons.history, color: Colors.indigo),
                              title: Text(data['contenido']),
                              subtitle: Text(data['fechaHora'].toDate().toString()),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
