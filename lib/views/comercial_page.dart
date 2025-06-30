import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

class ComercialPage extends StatefulWidget {
  const ComercialPage({super.key});

  @override
  State<ComercialPage> createState() => _ComercialPageState();
}

class _ComercialPageState extends State<ComercialPage> {
  String? tipoTicket;
  String? filtroTipoTicket;
  DateTime? selectedDate;
  bool isLoading = false;
  final tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];

  Future<String?> subirImagenASupabase(XFile picked, String userId) async {
    final supabase = Supabase.instance.client;
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final fileBytes = await picked.readAsBytes();

    final response = await supabase.storage.from('ticketsfotos').uploadBinary(
        fileName, fileBytes,
        fileOptions: const FileOptions(upsert: true));

    if (response.isEmpty) {
      return null;
    }

    final url = supabase.storage.from('ticketsfotos').getPublicUrl(fileName);
    return url;
  }

  Future<void> _tomarFotoYSubir(String tipoDoc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || tipoTicket == null) return;
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    setState(() => isLoading = true);
    try {
      final url = await subirImagenASupabase(picked, user.uid);
      if (url != null) {
        await FirebaseFirestore.instance.collection('tickets').add({
          'comercialId': user.uid,
          'tipo': tipoTicket,
          'tipoDoc': tipoDoc,
          'fotoUrl': url,
          'fechaHora': DateTime.now(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Foto subida como $tipoDoc')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error al subir la imagen a Supabase')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Cambia el filtro de fecha para poder limpiar el filtro
  void _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    setState(() {
      selectedDate = picked;
    });
  }

  void _clearDateFilter() {
    setState(() {
      selectedDate = null;
    });
  }

  // Exportar solo un ticket
  Future<void> _exportarPDFTicket(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    Uint8List? imageBytes;

    final fotoUrl = data['fotoUrl'];
    if (fotoUrl != null) {
      try {
        final response = await http.get(Uri.parse(fotoUrl));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        }
      } catch (e) {
        print('Error al descargar imagen: $e');
      }
    }

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tipo: ${data['tipo']}'),
            pw.Text('Tipo Doc: ${data['tipoDoc']}'),
            pw.Text('Fecha: ${formatter.format(data['fechaHora'].toDate())}'),
            if (imageBytes != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  width: 200,
                  height: 200,
                  fit: pw.BoxFit.cover,
                ),
              ),
            pw.Divider(),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> _exportarPDF(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets,
  ) async {
    final pdf = pw.Document();
    final formatter = DateFormat('yyyy-MM-dd HH:mm');

    for (var doc in tickets) {
      final data = doc.data();
      Uint8List? imageBytes;

      final fotoUrl = data['fotoUrl'];
      if (fotoUrl != null) {
        try {
          final response = await http.get(Uri.parse(fotoUrl));
          if (response.statusCode == 200) {
            imageBytes = response.bodyBytes;
          }
        } catch (e) {
          // En caso de error, la imagen no se incluirá
          print('Error al descargar imagen: $e');
        }
      }

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo']}'),
              pw.Text('Tipo Doc: ${data['tipoDoc']}'),
              pw.Text('Fecha: ${formatter.format(data['fechaHora'].toDate())}'),
              if (imageBytes != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  child: pw.Image(
                    pw.MemoryImage(imageBytes),
                    width: 200,
                    height: 200,
                    fit: pw.BoxFit.cover,
                  ),
                ),
              pw.Divider(),
            ],
          ),
        ),
      );
    }

    // Mostrar el PDF generado
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          'Comercial: ${user?.email ?? ''}',
          style: const TextStyle(color: Colors.black87),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.black54),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Formulario de subida
                Text(
                  'Nuevo ticket',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: tipoTicket == null || isLoading
                            ? null
                            : () => _tomarFotoYSubir('Factura simplificada'),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Factura simplificada'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: tipoTicket == null || isLoading
                            ? null
                            : () => _tomarFotoYSubir('Copia para el cliente'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Copia cliente'),
                      ),
                    ),
                  ],
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const Divider(height: 32),

                // Filtros
                Text(
                  'Filtros',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Filtro por tipo
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: filtroTipoTicket,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todos los tipos'),
                          ),
                          ...tipos.map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t),
                              )),
                        ],
                        onChanged: (v) => setState(() => filtroTipoTicket = v),
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (filtroTipoTicket != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => filtroTipoTicket = null),
                        tooltip: 'Quitar filtro',
                      ),
                    const SizedBox(width: 10),
                    // Filtro por fecha
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(selectedDate == null
                            ? 'Filtrar por fecha'
                            : DateFormat('yyyy-MM-dd').format(selectedDate!)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 18, horizontal: 12),
                        ),
                      ),
                    ),
                    if (selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearDateFilter,
                        tooltip: 'Limpiar fecha',
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Listado de tickets
                Text(
                  'Tus tickets subidos:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 400,
                  child: StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('tickets')
                        .where('comercialId', isEqualTo: user?.uid)
                        .orderBy('fechaHora', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var tickets = snapshot.data!.docs;

                      // Filtro por tipo
                      if (filtroTipoTicket != null &&
                          filtroTipoTicket!.isNotEmpty) {
                        tickets = tickets
                            .where((d) => d['tipo'] == filtroTipoTicket)
                            .toList();
                      }

                      // Filtro por fecha
                      if (selectedDate != null) {
                        tickets = tickets.where((d) {
                          final fecha = d['fechaHora'].toDate();
                          return fecha.year == selectedDate!.year &&
                              fecha.month == selectedDate!.month &&
                              fecha.day == selectedDate!.day;
                        }).toList();
                      }

                      if (tickets.isEmpty) {
                        return const Center(child: Text('Sin historial.'));
                      }

                      return Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: tickets.isNotEmpty
                                  ? () => _exportarPDF(tickets)
                                  : null,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Exportar todo'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: tickets.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final data = tickets[index].data();
                                return Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    leading: data['fotoUrl'] != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.network(
                                              data['fotoUrl'],
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(Icons.receipt_long,
                                            color: Colors.indigo, size: 40),
                                    title: Text(
                                      '${data['tipoDoc']} - ${data['tipo']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                        DateFormat('yyyy-MM-dd HH:mm').format(
                                            data['fechaHora'].toDate())),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon:
                                              const Icon(Icons.picture_as_pdf),
                                          tooltip: 'Exportar solo este ticket',
                                          onPressed: () =>
                                              _exportarPDFTicket(data),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.visibility),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => Dialog(
                                                child: InteractiveViewer(
                                                  child: Image.network(
                                                    data['fotoUrl'],
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
