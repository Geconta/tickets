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
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    double? totalEuros;
    if (tipoDoc == 'Factura simplificada') {
      // Pide el total al usuario
      final controller = TextEditingController();
      final result = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Introduce el total en euros'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Total (€)'),
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
      if (result == null) return; // Cancelado
      totalEuros = result;
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
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tipo: ${data['tipo']}'),
            pw.Text('Fecha: ${formatter.format(data['fechaHora'].toDate())}'),
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
    // Busca el total (ej: Total: 23,45 o TOTAL 23.45)
    final totalRegex = RegExp(r'total[:\s]*([\d\.,]+)', caseSensitive: false);
    final totalMatch = totalRegex.firstMatch(texto);
    String? total = totalMatch?.group(1)?.replaceAll(',', '.');

    // Busca el nombre del establecimiento (primera línea no vacía)
    final lines = texto
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    String? establecimiento = lines.isNotEmpty ? lines.first : null;

    return {
      'total': total,
      'establecimiento': establecimiento,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _getUserInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final name = snapshot.data!['name']!;
        final lastName = snapshot.data!['lastName']!;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            title: Text(
              'Comercial: ${name.isNotEmpty ? '$name $lastName' : 'Sin nombre'}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                    // Título principal
                    Text(
                      'Nuevo ticket',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),

                    // NUEVO: Formulario de agregar registro (justo debajo del título)
                    Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: tipoTicketNuevo,
                              items: tipos
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => tipoTicketNuevo = v),
                              decoration: const InputDecoration(
                                  labelText: 'Tipo de ticket',
                                  border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: Icon(
                                      Icons.camera_alt,
                                      color: imagenFactura == null
                                          ? Colors.grey
                                          : Colors.blue,
                                    ),
                                    label: Text(imagenFactura == null
                                        ? 'Subir Factura simplificada'
                                        : 'Factura lista'),
                                    onPressed: () async {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 70);
                                      if (picked != null) {
                                        setState(() => imagenFactura = picked);

                                        // Extraer texto de la imagen
                                        setState(() => isUploading = true);
                                        try {
                                          final textoFactura =
                                              await extraerTextoFacturaWeb(
                                                      imagenFactura!)
                                                  .timeout(
                                            const Duration(seconds: 15),
                                            onTimeout: () => null,
                                          );
                                          String? total;
                                          String? establecimiento;
                                          if (textoFactura != null) {
                                            final datos = extraerDatosFactura(
                                                textoFactura);
                                            total = datos['total'];
                                            establecimiento =
                                                datos['establecimiento'];
                                          }
                                          setState(() {
                                            textoFacturaExtraido = textoFactura;
                                            totalExtraido = total;
                                            establecimientoExtraido =
                                                establecimiento;
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
                                      Icons.camera_alt_outlined,
                                      color: imagenCopia == null
                                          ? Colors.grey
                                          : Colors.blue,
                                    ),
                                    label: Text(imagenCopia == null
                                        ? 'Subir Copia cliente'
                                        : 'Copia lista'),
                                    onPressed: () async {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 70);
                                      if (picked != null) {
                                        setState(() => imagenCopia = picked);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: (tipoTicketNuevo != null &&
                                      imagenFactura != null &&
                                      imagenCopia != null &&
                                      !isUploading)
                                  ? () async {
                                      setState(() => isUploading = true);
                                      try {
                                        final user =
                                            FirebaseAuth.instance.currentUser;
                                        if (user == null) return;
                                        final supabase =
                                            Supabase.instance.client;
                                        final fileNameFactura =
                                            '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_factura.jpg';
                                        final fileNameCopia =
                                            '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_copia.jpg';
                                        final urlFactura = await supabase
                                            .storage
                                            .from('ticketsfotos')
                                            .uploadBinary(
                                                fileNameFactura,
                                                await imagenFactura!
                                                    .readAsBytes(),
                                                fileOptions: const FileOptions(
                                                    upsert: true));
                                        final urlCopia = await supabase.storage
                                            .from('ticketsfotos')
                                            .uploadBinary(
                                                fileNameCopia,
                                                await imagenCopia!
                                                    .readAsBytes(),
                                                fileOptions: const FileOptions(
                                                    upsert: true));

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
                                              totalExtraido ?? ''),
                                          'establecimiento':
                                              establecimientoExtraido,
                                        });
                                        setState(() {
                                          tipoTicketNuevo = null;
                                          imagenFactura = null;
                                          imagenCopia = null;
                                          textoFacturaExtraido = null;
                                          totalExtraido = null;
                                          establecimientoExtraido = null;
                                        });
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content:
                                                    Text('Registro creado')));
                                      } catch (e) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text('Error: $e')));
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
                            value: filtroTipoTicket ?? '',
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Todos los tipos'),
                              ),
                              ...tipos.map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  )),
                            ],
                            onChanged: (v) =>
                                setState(() => filtroTipoTicket = v ?? ''),
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
                                : DateFormat('yyyy-MM-dd')
                                    .format(selectedDate!)),
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
                            .where('comercialId',
                                isEqualTo:
                                    FirebaseAuth.instance.currentUser?.uid)
                            .orderBy('fechaHora', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          var tickets = snapshot.data!.docs;

                          // Filtro por tipo
                          if ((filtroTipoTicket ?? '').isNotEmpty) {
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
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: ListTile(
                                        title: Text('${data['tipo']}'),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}'),
                                            if (data['establecimiento'] != null)
                                              Text(
                                                  'Establecimiento: ${data['establecimiento']}'),
                                            if (data['textoFactura'] != null)
                                              Text(
                                                'Texto escaneado: ${data['textoFactura']}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            if (data['totalEuros'] != null)
                                              Text(
                                                  'Total: €${data['totalEuros']}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon:
                                                  const Icon(Icons.visibility),
                                              tooltip: 'Ver imágenes',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => Dialog(
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (data[
                                                                'fotoFactura'] !=
                                                            null)
                                                          Flexible(
                                                            child:
                                                                Image.network(
                                                              data[
                                                                  'fotoFactura'],
                                                              fit: BoxFit
                                                                  .contain,
                                                            ),
                                                          ),
                                                        if (data['fotoCopia'] !=
                                                            null)
                                                          Flexible(
                                                            child:
                                                                Image.network(
                                                              data['fotoCopia'],
                                                              fit: BoxFit
                                                                  .contain,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.picture_as_pdf),
                                              tooltip: 'Exportar PDF',
                                              onPressed: () =>
                                                  _exportarPDFTicket(data),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Colors.red),
                                              tooltip: 'Eliminar',
                                              onPressed: () async {
                                                final confirm =
                                                    await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                    title: const Text(
                                                        '¿Eliminar ticket?'),
                                                    content: const Text(
                                                        '¿Estás seguro de que deseas eliminar este ticket?'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, false),
                                                        child: const Text(
                                                            'Cancelar'),
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child: const Text(
                                                            'Eliminar',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .red)),
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
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
