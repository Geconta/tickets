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
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_ml_kit/google_ml_kit.dart';
import 'dart:io';

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
  String? tipoTicketNuevo;
  XFile? imagenFactura;
  XFile? imagenCopia;
  bool isUploading = false;
  final tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];

  String? textoFacturaExtraido;
  String? totalExtraido;
  String? establecimientoExtraido;

  final TextEditingController totalController = TextEditingController();

  Future<void> _eliminarTicket(
      String ticketId, String? fotoFacturaUrl, String? fotoCopiaUrl) async {
    try {
      // Eliminar el documento de Firestore
      await FirebaseFirestore.instance
          .collection('tickets')
          .doc(ticketId)
          .delete();

      // Eliminar ambas imágenes de Supabase si existen
      final supabase = Supabase.instance.client;
      if (fotoFacturaUrl != null) {
        final fileName = fotoFacturaUrl.split('/').last;
        await supabase.storage.from('ticketsfotos').remove([fileName]);
      }
      if (fotoCopiaUrl != null) {
        final fileName = fotoCopiaUrl.split('/').last;
        await supabase.storage.from('ticketsfotos').remove([fileName]);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket eliminado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar el ticket: $e')),
        );
      }
    }
  }

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
        await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked == null) return;

    double? totalEuros;

    if (tipoDoc == 'Factura simplificada') {
      try {
        final inputImage = InputImage.fromFile(File(picked.path));
        final textRecognizer = GoogleMlKit.vision.textRecognizer();
        final recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();

        final allText = recognizedText.text.toLowerCase();
        final lines = allText.split('\n').map((line) => line.trim()).toList();

        // Normalizar texto para eliminar espacios redundantes
        String normalize(String text) =>
            text.replaceAll(RegExp(r'[€\s]'), '').replaceAll(',', '.');

        // Candidatos a total
        final possibleTotals = <double>[];

        final totalPatterns = [
          RegExp(r'(total[^a-zA-Z0-9]?[:\-]?\s*€?\s*([\d,.]+))'),
          RegExp(r'(importe\s*total[^a-zA-Z0-9]?[:\-]?\s*€?\s*([\d,.]+))'),
          RegExp(r'(totalfactura[^a-zA-Z0-9]?[:\-]?\s*€?\s*([\d,.]+))'),
          RegExp(r'(importe[^a-zA-Z0-9]?[:\-]?\s*([\d,.]+))'),
        ];

        for (final line in lines) {
          for (final pattern in totalPatterns) {
            final match = pattern.firstMatch(line);
            if (match != null) {
              final rawValue = match.group(2)?.replaceAll(',', '.');
              final value = double.tryParse(normalize(rawValue ?? ''));
              if (value != null) possibleTotals.add(value);
            }
          }
        }

        // Si no encontró expresiones directas, buscar el número más alto en el texto (posible total)
        if (possibleTotals.isEmpty) {
          final looseNumberPattern = RegExp(r'([\d]+[.,][\d]{2})');
          for (final match in looseNumberPattern.allMatches(allText)) {
            final raw = match.group(1)?.replaceAll(',', '.');
            final value = double.tryParse(normalize(raw ?? ''));
            if (value != null && value > 0) possibleTotals.add(value);
          }
        }

        // Asumimos que el total es el número más alto entre los encontrados
        totalEuros = possibleTotals.isNotEmpty
            ? possibleTotals.reduce((a, b) => a > b ? a : b)
            : null;

        if (totalEuros == null) {
          final controller = TextEditingController();
          final result = await showDialog<double>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('No se detectó el total'),
              content: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Introduce el total (€)'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    final value =
                        double.tryParse(controller.text.replaceAll(',', '.'));
                    Navigator.pop(context, value);
                  },
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
          if (result == null) return;
          totalEuros = result;
        }
      } catch (e) {
        print('❌ Error al escanear OCR: $e');
        return;
      }
    }

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
          if (totalEuros != null) 'totalEuros': totalEuros,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Foto subida como $tipoDoc')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al subir imagen a Supabase')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

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

  Future<void> _exportarPDFTicket(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );

    // Descargar ambas imágenes si existen
    Uint8List? imageFactura;
    Uint8List? imageCopia;

    if (data['fotoFactura'] != null) {
      try {
        final response = await http.get(Uri.parse(data['fotoFactura']));
        if (response.statusCode == 200) {
          imageFactura = response.bodyBytes;
        }
      } catch (e) {
        print('Error al descargar imagen factura: $e');
      }
    }
    if (data['fotoCopia'] != null) {
      try {
        final response = await http.get(Uri.parse(data['fotoCopia']));
        if (response.statusCode == 200) {
          imageCopia = response.bodyBytes;
        }
      } catch (e) {
        print('Error al descargar imagen copia: $e');
      }
    }

    pdf.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(
          base: font,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tipo: ${data['tipo']}'),
            pw.Text('Fecha: ${formatter.format(data['fechaHora'].toDate())}'),
            if (data['establecimiento'] != null)
              pw.Text('Establecimiento: ${data['establecimiento']}'),
            if (data['totalEuros'] != null)
              pw.Text('Total: € ${data['totalEuros']}'),
            if (imageFactura != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Column(children: [
                  pw.Text('Factura simplificada:'),
                  pw.Image(pw.MemoryImage(imageFactura),
                      width: 200, height: 200, fit: pw.BoxFit.cover),
                ]),
              ),
            if (imageCopia != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Column(children: [
                  pw.Text('Copia cliente:'),
                  pw.Image(pw.MemoryImage(imageCopia),
                      width: 200, height: 200, fit: pw.BoxFit.cover),
                ]),
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
      Uint8List? imageFactura;
      Uint8List? imageCopia;

      // Descargar imagen de factura
      if (data['fotoFactura'] != null) {
        try {
          final response = await http.get(Uri.parse(data['fotoFactura']));
          if (response.statusCode == 200) {
            imageFactura = response.bodyBytes;
          }
        } catch (e) {
          print('Error al descargar imagen factura: $e');
        }
      }
      // Descargar imagen de copia
      if (data['fotoCopia'] != null) {
        try {
          final response = await http.get(Uri.parse(data['fotoCopia']));
          if (response.statusCode == 200) {
            imageCopia = response.bodyBytes;
          }
        } catch (e) {
          print('Error al descargar imagen copia: $e');
        }
      }

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo']}'),
              pw.Text('Fecha: ${formatter.format(data['fechaHora'].toDate())}'),
              if (data['establecimiento'] != null)
                pw.Text('Establecimiento: ${data['establecimiento']}'),
              if (data['totalEuros'] != null)
                pw.Text('Total: €${data['totalEuros']}'),
              if (imageFactura != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  child: pw.Column(children: [
                    pw.Text('Factura simplificada:'),
                    pw.Image(pw.MemoryImage(imageFactura),
                        width: 200, height: 200, fit: pw.BoxFit.cover),
                  ]),
                ),
              if (imageCopia != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  child: pw.Column(children: [
                    pw.Text('Copia cliente:'),
                    pw.Image(pw.MemoryImage(imageCopia),
                        width: 200, height: 200, fit: pw.BoxFit.cover),
                  ]),
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

  Future<Map<String, String>> _getUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'name': 'Sin nombre', 'lastName': ''};

    // Obtener datos del usuario desde Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      final data = doc.data();
      return {
        'name': data?['name'] ?? 'Sin nombre',
        'lastName': data?['lastName'] ?? '',
      };
    }

    return {'name': 'Sin nombre', 'lastName': ''};
  }

  Future<String?> extraerTextoFacturaWeb(XFile imagen) async {
    final bytes = await imagen.readAsBytes();
    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final request = http.MultipartRequest('POST', uri)
      ..fields['language'] = 'spa'
      ..fields['isOverlayRequired'] = 'false'
      ..fields['OCREngine'] = '2'
      ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'factura.jpg'));
    request.headers['apikey'] = 'helloworld'; // Para pruebas

    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    final jsonResp = json.decode(respStr);

    if (jsonResp['IsErroredOnProcessing'] == false) {
      final text = jsonResp['ParsedResults'][0]['ParsedText'] as String;
      return text;
    }
    return null;
  }

  Map<String, String?> extraerDatosFactura(String texto) {
    final lines = texto
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ===== 1. Normalizar texto completo para búsqueda de totales =====
    final fullText = lines.join('\n').toLowerCase();

    // ===== 2. Patrones comunes para detectar total =====
    final patronesTotal = [
      RegExp(r'(total[^a-zA-Z0-9]?[:\-]?\s*€?\s*([\d.,]+))',
          caseSensitive: false),
      RegExp(r'(importe\s*total[^a-zA-Z0-9]?[:\-]?\s*([\d.,]+))',
          caseSensitive: false),
      RegExp(r'(totalfactura[^a-zA-Z0-9]?[:\-]?\s*([\d.,]+))',
          caseSensitive: false),
      RegExp(r'(importe[^a-zA-Z0-9]?[:\-]?\s*([\d.,]+))', caseSensitive: false),
    ];

    double? totalEncontrado;
    final posiblesTotales = <double>[];

    for (final patron in patronesTotal) {
      for (final match in patron.allMatches(fullText)) {
        final raw = match.group(2);
        final normalizado =
            raw?.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
        final valor = double.tryParse(normalizado ?? '');
        if (valor != null) posiblesTotales.add(valor);
      }
    }

    // Si no se encuentra usando los patrones, buscar números sueltos
    if (posiblesTotales.isEmpty) {
      final numeroSueltos = RegExp(r'([\d]+[.,][\d]{2})');
      for (final match in numeroSueltos.allMatches(fullText)) {
        final raw = match.group(1);
        final valor = double.tryParse(raw?.replaceAll(',', '.') ?? '');
        if (valor != null && valor > 0) posiblesTotales.add(valor);
      }
    }

    // Suponer que el total es el número más alto detectado
    if (posiblesTotales.isNotEmpty) {
      totalEncontrado = posiblesTotales.reduce((a, b) => a > b ? a : b);
    }

    // ===== 3. Determinar establecimiento (la línea más "típica") =====
    String? establecimiento;
    if (lines.isNotEmpty) {
      // Excluir líneas con solo números o muy cortas
      establecimiento = lines.firstWhere(
        (l) => l.length > 3 && !RegExp(r'^\d+$').hasMatch(l),
        orElse: () => lines.first,
      );
    }

    print('Texto OCR: $texto');
    print('Total extraído: ${totalEncontrado?.toStringAsFixed(2)}');
    print('Establecimiento extraído: $establecimiento');

    return {
      'total': totalEncontrado?.toStringAsFixed(2),
      'establecimiento': establecimiento,
    };
  }

  Widget _buildListadoTickets() {
    return SizedBox(
      height: 400,
      child: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('tickets')
            .where('comercialId',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .orderBy('fechaHora', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var tickets = snapshot.data!.docs;

          // Filtro por tipo
          if ((filtroTipoTicket ?? '').isNotEmpty) {
            tickets =
                tickets.where((d) => d['tipo'] == filtroTipoTicket).toList();
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
                  onPressed: () => _exportarPDF(tickets),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exportar todo'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = tickets[index].data();
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text('${data['tipo']}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}'),
                            if (data['establecimiento'] != null)
                              Text(
                                  'Establecimiento: ${data['establecimiento']}'),
                            if (data['totalEuros'] != null)
                              Text('Total: €${data['totalEuros']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              tooltip: 'Ver imágenes',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (data['fotoFactura'] != null)
                                          Flexible(
                                            child: Image.network(
                                              data['fotoFactura'],
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        if (data['fotoCopia'] != null)
                                          Flexible(
                                            child: Image.network(
                                              data['fotoCopia'],
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf),
                              tooltip: 'Exportar PDF',
                              onPressed: () => _exportarPDFTicket(data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Eliminar',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('¿Eliminar ticket?'),
                                    content: const Text(
                                        '¿Deseas eliminar este ticket?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Eliminar',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _eliminarTicket(
                                    tickets[index].id,
                                    data['fotoFactura'],
                                    data['fotoCopia'],
                                  );
                                }
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
    );
  }

  Widget _buildFormularioNuevoTicket(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: tipoTicketNuevo,
              items: tipos
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => tipoTicketNuevo = v),
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
                    icon: Icon(
                      Icons.camera_alt,
                      color: imagenFactura == null ? Colors.grey : Colors.blue,
                    ),
                    label: Text(imagenFactura == null
                        ? 'Subir Factura simplificada'
                        : 'Factura lista'),
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                          source: ImageSource.camera, imageQuality: 70);
                      if (picked != null) {
                        setState(() => imagenFactura = picked);

                        setState(() => isUploading = true);
                        try {
                          final textoFactura =
                              await extraerTextoFacturaWeb(imagenFactura!)
                                  .timeout(
                            const Duration(seconds: 15),
                            onTimeout: () => null,
                          );
                          String? total;
                          String? establecimiento;
                          if (textoFactura != null) {
                            final datos = extraerDatosFactura(textoFactura);
                            establecimiento = datos['establecimiento'];
                            total = datos['total'];
                          }
                          setState(() {
                            textoFacturaExtraido = textoFactura;
                            totalExtraido = total;
                            establecimientoExtraido = establecimiento;
                            totalController.text = total ?? '';
                          });
                        } finally {
                          setState(() => isUploading = false);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                      Icons.camera_alt,
                      color: imagenCopia == null ? Colors.grey : Colors.blue,
                    ),
                    label: Text(imagenCopia == null
                        ? 'Subir Copia cliente'
                        : 'Copia lista'),
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                          source: ImageSource.camera, imageQuality: 70);
                      if (picked != null) {
                        setState(() => imagenCopia = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: totalController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Total (€)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  totalExtraido = value;
                });
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (tipoTicketNuevo != null &&
                        imagenFactura != null &&
                        imagenCopia != null &&
                        !isUploading)
                    ? Colors
                        .blue[700] // Color más oscuro cuando está habilitado
                    : Colors
                        .grey[400], // Color más claro cuando está deshabilitado

                foregroundColor: (tipoTicketNuevo != null &&
                        imagenFactura != null &&
                        imagenCopia != null &&
                        !isUploading)
                    ? Colors.white // Texto blanco si habilitado
                    : Colors.white70, // Texto más tenue si deshabilitado
              ),
              onPressed: (tipoTicketNuevo != null &&
                      imagenFactura != null &&
                      imagenCopia != null &&
                      !isUploading)
                  ? () async {
                      setState(() => isUploading = true);
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;
                        final supabase = Supabase.instance.client;
                        final fileNameFactura =
                            '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_factura.jpg';
                        final fileNameCopia =
                            '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_copia.jpg';
                        final urlFactura = await supabase.storage
                            .from('ticketsfotos')
                            .uploadBinary(
                              fileNameFactura,
                              await imagenFactura!.readAsBytes(),
                              fileOptions: const FileOptions(upsert: true),
                            );
                        final urlCopia = await supabase.storage
                            .from('ticketsfotos')
                            .uploadBinary(
                              fileNameCopia,
                              await imagenCopia!.readAsBytes(),
                              fileOptions: const FileOptions(upsert: true),
                            );

                        await FirebaseFirestore.instance
                            .collection('tickets')
                            .add({
                          'comercialId': user.uid,
                          'tipo': tipoTicketNuevo,
                          'fechaHora': DateTime.now(),
                          'fotoFactura': supabase.storage
                              .from('ticketsfotos')
                              .getPublicUrl(fileNameFactura),
                          'fotoCopia': supabase.storage
                              .from('ticketsfotos')
                              .getPublicUrl(fileNameCopia),
                          'textoFactura': textoFacturaExtraido,
                          'totalEuros': double.tryParse(
                              totalController.text.replaceAll(',', '.')),
                          'establecimiento': establecimientoExtraido,
                        });

                        setState(() {
                          tipoTicketNuevo = null;
                          imagenFactura = null;
                          imagenCopia = null;
                          textoFacturaExtraido = null;
                          totalExtraido = null;
                          establecimientoExtraido = null;
                          totalController.clear();
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Registro creado')));
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      } finally {
                        setState(() => isUploading = false);
                      }
                    }
                  : null,
              child: isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Crear nuevo registro'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return FutureBuilder<Map<String, String>>(
      future: _getUserInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final name = snapshot.data!['name']!;
        final lastName = snapshot.data!['lastName']!;

        return Scaffold(
          backgroundColor: colorScheme.surfaceVariant.withOpacity(0.05),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            title: Text(
              'Comercial: ${name.isNotEmpty ? '$name $lastName' : 'Sin nombre'}',
              style:
                  textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Nuevo ticket',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),

                        /// Formulario para nuevo ticket
                        _buildFormularioNuevoTicket(context),

                        if (isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),

                        const Divider(height: 40),

                        /// Filtros
                        Text('Filtros',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 260,
                              child: DropdownButtonFormField<String>(
                                value: filtroTipoTicket ?? '',
                                items: [
                                  const DropdownMenuItem(
                                      value: '',
                                      child: Text('Todos los tipos')),
                                  ...tipos.map((t) => DropdownMenuItem(
                                      value: t, child: Text(t))),
                                ],
                                onChanged: (v) =>
                                    setState(() => filtroTipoTicket = v ?? ''),
                                decoration: const InputDecoration(
                                  labelText: 'Tipo',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            if (filtroTipoTicket != null &&
                                filtroTipoTicket!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Quitar filtro',
                                onPressed: () =>
                                    setState(() => filtroTipoTicket = null),
                              ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today),
                              label: Text(selectedDate == null
                                  ? 'Filtrar por fecha'
                                  : DateFormat('yyyy-MM-dd')
                                      .format(selectedDate!)),
                              onPressed: _selectDate,
                            ),
                            if (selectedDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Limpiar fecha',
                                onPressed: _clearDateFilter,
                              ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        /// Listado de tickets
                        Text('Tus tickets subidos:',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),

                        _buildListadoTickets(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
