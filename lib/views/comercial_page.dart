import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ComercialPage extends StatefulWidget {
  const ComercialPage({super.key});

  @override
  State<ComercialPage> createState() => _ComercialPageState();
}

class _ComercialPageState extends State<ComercialPage> {
  String? tipoTicket;
  final tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];
  bool isLoading = false;

  Future<void> _tomarFotoYSubir(String tipoDoc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || tipoTicket == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked == null) return;

    setState(() => isLoading = true);
    final fileName =
        '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$tipoDoc.jpg';
    final ref = FirebaseStorage.instance.ref().child('tickets/$fileName');
    await ref.putData(await picked.readAsBytes());
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection('tickets').add({
      'comercialId': user.uid,
      'tipo': tipoTicket,
      'tipoDoc': tipoDoc,
      'fotoUrl': url,
      'fechaHora': DateTime.now(),
    });

    setState(() => isLoading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Foto subida como $tipoDoc')));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F8FFF),
        title: Text('Comercialvvvvvv: ${user?.email ?? ''}'),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4F8FFF), Color(0xFF235390)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
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
                  DropdownButtonFormField<String>(
                    value: tipoTicket,
                    items: tipos
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => tipoTicket = v),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de ticket',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: tipoTicket == null || isLoading
                            ? null
                            : () => _tomarFotoYSubir('Factura simplificada'),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Factura simplificada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: tipoTicket == null || isLoading
                            ? null
                            : () => _tomarFotoYSubir('Copia para el cliente'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Copia para el cliente'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Tus tickets subidos:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height: 300,
                    child: StreamBuilder(
                      stream: FirebaseFirestore.instance
                          .collection('tickets')
                          .where('comercialId', isEqualTo: user?.uid)
                          .orderBy('fechaHora', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const CircularProgressIndicator();
                        final tickets = snapshot.data!.docs;
                        if (tickets.isEmpty) {
                          return const Center(child: Text('Sin historial.'));
                        }
                        return ListView(
                          children: tickets.map((doc) {
                            final data = doc.data();
                            return ListTile(
                              leading: data['fotoUrl'] != null
                                  ? Image.network(
                                      data['fotoUrl'],
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(
                                      Icons.receipt_long,
                                      color: Colors.indigo,
                                    ),
                              title: Text(
                                '${data['tipoDoc']} - ${data['tipo']}',
                              ),
                              subtitle: Text(
                                data['fechaHora'].toDate().toString(),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
