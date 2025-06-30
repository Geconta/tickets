import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  DateTime? selectedDate;
  String? filtroComercialId;
  String? filtroTipoTicket;
  static const int pageSize = 10;
  DocumentSnapshot? lastDoc;
  bool isLoading = false;
  bool hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets = [];
  List<String> comerciales = [];
  final tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];

  @override
  void initState() {
    super.initState();
    _loadComerciales();
    _loadTickets(reset: true);
  }

  Future<void> _loadComerciales() async {
    // Obtiene todos los comerciales únicos de los tickets
    final snapshot =
        await FirebaseFirestore.instance.collection('tickets').get();
    final ids =
        snapshot.docs.map((d) => d['comercialId'] as String).toSet().toList();
    setState(() {
      comerciales = ids;
    });
  }

  Future<void> _loadTickets({bool reset = false}) async {
    if (isLoading) return;
    setState(() => isLoading = true);

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('tickets')
        .orderBy('fechaHora', descending: true);

    if (selectedDate != null) {
      final start =
          DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .where('fechaHora', isGreaterThanOrEqualTo: start)
          .where('fechaHora', isLessThan: end);
    }
    if (filtroComercialId != null && filtroComercialId!.isNotEmpty) {
      query = query.where('comercialId', isEqualTo: filtroComercialId);
    }
    if (filtroTipoTicket != null && filtroTipoTicket!.isNotEmpty) {
      query = query.where('tipo', isEqualTo: filtroTipoTicket);
    }

    if (!reset && lastDoc != null) {
      query = query.startAfterDocument(lastDoc!).limit(pageSize);
    } else {
      query = query.limit(pageSize);
    }

    final snapshot = await query.get();
    if (reset) {
      tickets = [];
      lastDoc = null;
      hasMore = true;
    }
    if (snapshot.docs.isNotEmpty) {
      lastDoc = snapshot.docs.last;
      tickets.addAll(snapshot.docs);
      if (snapshot.docs.length < pageSize) hasMore = false;
    } else {
      hasMore = false;
    }
    setState(() => isLoading = false);
  }

  void _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      await _loadTickets(reset: true);
    }
  }

  void _clearDateFilter() async {
    setState(() {
      selectedDate = null;
    });
    await _loadTickets(reset: true);
  }

  void _onFiltroComercialChanged(String? value) async {
    setState(() {
      filtroComercialId = value;
    });
    await _loadTickets(reset: true);
  }

  void _onFiltroTipoChanged(String? value) async {
    setState(() {
      filtroTipoTicket = value;
    });
    await _loadTickets(reset: true);
  }

  // Exportar todos los tickets filtrados a PDF
  Future<void> _exportarPDFTodos() async {
    final pdf = pw.Document();
    for (final doc in tickets) {
      final data = doc.data();
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo']}'),
              pw.Text('Tipo Doc: ${data['tipoDoc']}'),
              pw.Text('Comercial: ${data['comercialId']}'),
              pw.Text(
                  'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}'),
              pw.SizedBox(height: 10),
              if (data['fotoUrl'] != null)
                pw.Text('Imagen adjunta (no se muestra en PDF por lote)'),
              pw.Divider(),
            ],
          ),
        ),
      );
    }
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // Exportar ticket seleccionado a PDF (con imagen)
  Future<void> _exportarPDFTicket(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    Uint8List? imageBytes;
    if (data['fotoUrl'] != null) {
      try {
        final response = await http.get(Uri.parse(data['fotoUrl']));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        }
      } catch (_) {}
    }
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tipo: ${data['tipo']}'),
            pw.Text('Tipo Doc: ${data['tipoDoc']}'),
            pw.Text('Comercial: ${data['comercialId']}'),
            pw.Text(
                'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}'),
            pw.SizedBox(height: 10),
            if (imageBytes != null)
              pw.Image(pw.MemoryImage(imageBytes), width: 200, height: 200),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // Exportar todos los tickets filtrados a Excel
  Future<void> _exportarExcelTodos() async {
    final excel = Excel.createExcel();
    final sheet = excel['Tickets'];
    sheet.appendRow(['Tipo', 'Tipo Doc', 'Comercial', 'Fecha', 'Foto URL']);
    for (final doc in tickets) {
      final data = doc.data();
      sheet.appendRow([
        data['tipo'] ?? '',
        data['tipoDoc'] ?? '',
        data['comercialId'] ?? '',
        DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate()),
        data['fotoUrl'] ?? '',
      ]);
    }
    final bytes = excel.encode();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tickets.xlsx');
    await file.writeAsBytes(bytes!);

    // Usa share_plus para compartir el archivo Excel
    await Share.shareXFiles([XFile(file.path)], text: 'Tickets exportados');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Panel de Administrador',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.black54),
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                'Bienvenido, Administrador',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Listado de todos los tickets subidos:',
                style: TextStyle(fontSize: 18, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Filtros
              Row(
                children: [
                  // Filtro por comercialId
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: filtroComercialId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos los comerciales'),
                        ),
                        ...comerciales.map((id) => DropdownMenuItem(
                              value: id,
                              child: Text(id),
                            )),
                      ],
                      onChanged: _onFiltroComercialChanged,
                      decoration: const InputDecoration(
                        labelText: 'Comercial',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                      onChanged: _onFiltroTipoChanged,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Filtro por fecha
                  OutlinedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(selectedDate == null
                        ? 'Filtrar por fecha'
                        : DateFormat('yyyy-MM-dd').format(selectedDate!)),
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
              // Botones de exportación
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Exportar todo a PDF'),
                    onPressed: tickets.isEmpty ? null : _exportarPDFTodos,
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Exportar a Excel'),
                    onPressed: tickets.isEmpty ? null : _exportarExcelTodos,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Listado de tickets paginado
              Expanded(
                child: tickets.isEmpty && isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : tickets.isEmpty
                        ? const Center(child: Text('No hay tickets subidos.'))
                        : ListView.separated(
                            itemCount: tickets.length + (hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              if (index == tickets.length) {
                                // Botón para cargar más
                                return Center(
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('Cargar más'),
                                    onPressed:
                                        isLoading ? null : () => _loadTickets(),
                                  ),
                                );
                              }
                              final data = tickets[index].data();
                              return ListTile(
                                leading: const Icon(Icons.receipt_long,
                                    color: Colors.indigo, size: 40),
                                title: Text(
                                    '${data['tipoDoc']} - ${data['tipo']}'),
                                subtitle: Text(
                                  'Comercial: ${data['comercialId']}\n'
                                  'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.picture_as_pdf),
                                      tooltip: 'Exportar este ticket a PDF',
                                      onPressed: () => _exportarPDFTicket(data),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.visibility),
                                      tooltip: 'Ver imagen',
                                      onPressed: data['fotoUrl'] != null
                                          ? () {
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
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
