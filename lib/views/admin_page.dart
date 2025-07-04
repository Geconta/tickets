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
import 'dart:html' as html;

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  DateTime? selectedDate;
  DateTime? selectedMonth;
  int? selectedYear;
  String? filtroComercialId;
  String? filtroTipoTicket;
  static const int pageSize = 10;
  DocumentSnapshot? lastDoc;
  bool isLoading = false;
  bool hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets = [];
  Map<String, String> comercialesMap = {};
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
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final comercialesList = snapshot.docs;
    final Map<String, String> comercialNames = {};

    for (var doc in comercialesList) {
      final data = doc.data();
      comercialNames[doc.id] = '${data['name']} ${data['lastName']}';
    }

    setState(() {
      comercialesMap = comercialNames;
    });
  } // Obtener datos del usuario desde Firestore

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
    } else if (selectedMonth != null) {
      final start = DateTime(selectedMonth!.year, selectedMonth!.month, 1);
      final end = DateTime(selectedMonth!.year, selectedMonth!.month + 1, 1);
      query = query
          .where('fechaHora', isGreaterThanOrEqualTo: start)
          .where('fechaHora', isLessThan: end);
    } else if (selectedYear != null) {
      final start = DateTime(selectedYear!, 1, 1);
      final end = DateTime(selectedYear! + 1, 1, 1);
      query = query
          .where('fechaHora', isGreaterThanOrEqualTo: start)
          .where('fechaHora', isLessThan: end);
    }
    if (filtroComercialId != null && filtroComercialId!.isNotEmpty) {
      query = query.where('comercialId', isEqualTo: filtroComercialId);
    }
    if (filtroTipoTicket != null && filtroTipoTicket != '') {
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
    try {
      if (tickets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay tickets para exportar')),
        );
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel['Tickets'];

      // Encabezado principal
      sheet.appendRow(['Liquidación de gastos de viaje y representación visa']);
      sheet.appendRow(['GECONTA medidores de fluidos SL']);

      // Nombre del comercial (si hay filtro, lo muestra; si no, vacío)
      String comercialName = '';
      if (filtroComercialId != null &&
          comercialesMap[filtroComercialId] != null) {
        comercialName = comercialesMap[filtroComercialId]!;
      }
      sheet.appendRow([comercialName]);

      // Mes (si hay filtro de fecha, muestra el mes, si no, vacío)
      String mes = '';
      if (selectedDate != null) {
        mes = DateFormat('MMMM yyyy', 'es_ES').format(selectedDate!);
      }
      sheet.appendRow([mes]);

      // Fila vacía para separar
      sheet.appendRow([]);

      // Encabezados de la tabla
      sheet.appendRow([
        'Fecha',
        'Viaje/Cliente',
        'Transporte',
        'Manutención',
        'Alojamiento',
        'Varios',
        'Total'
      ]);

      // Rellenar la tabla
      for (final doc in tickets) {
        final data = doc.data();
        final fecha =
            DateFormat('yyyy-MM-dd').format(data['fechaHora'].toDate());
        final tipo = data['tipo'] ?? '';
        final tipoDoc = data['tipoDoc'] ?? '';
        final viajeCliente = tipoDoc; // Puedes ajustar si tienes otro campo
        String transporte = '';
        String manutencion = '';
        String alojamiento = '';
        String varios = '';

        // Marca la columna según el tipo
        switch (tipo) {
          case 'Transporte':
            transporte = 'X';
            break;
          case 'Manutención':
            manutencion = 'X';
            break;
          case 'Alojamiento':
            alojamiento = 'X';
            break;
          case 'Varios':
          case 'Gastos de representación':
            varios = 'X';
            break;
        }

        sheet.appendRow([
          fecha,
          viajeCliente,
          transporte,
          manutencion,
          alojamiento,
          varios,
          '', // Total (vacío)
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: No se pudo generar el archivo Excel')),
        );
        return;
      }

      // --- SOLO PARA WEB ---
      final blob = html.Blob([bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'tickets.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
      // ---------------------
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exportando Excel: $e')),
      );
      print('Error exportando Excel: $e');
    }
  }

  // Exportar ticket seleccionado a Excel
  Future<void> _exportarExcelTicket(Map<String, dynamic> data) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Ticket'];

      // Añadir encabezados de la hoja Excel
      sheet.appendRow(['Tipo', 'Tipo Doc', 'Comercial', 'Fecha']);

      // Añadir los datos del ticket sin la imagen
      sheet.appendRow([
        data['tipo'] ?? '',
        data['tipoDoc'] ?? '',
        comercialesMap[data['comercialId']] ?? 'Desconocido',
        DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate()),
      ]);

      // Generar el archivo Excel
      final bytes = excel.encode();
      if (bytes == null) {
        print('Error: No se pudo generar el archivo Excel');
        return;
      }

      // Guardar el archivo Excel en el directorio temporal
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/ticket_${data['tipoDoc']}_${DateFormat('yyyyMMdd_HHmm').format(data['fechaHora'].toDate())}.xlsx');
      await file.writeAsBytes(bytes);
      print('Archivo guardado en: ${file.path}');

      // Compartir el archivo Excel
      await Share.shareXFiles([XFile(file.path)], text: 'Ticket exportado');
    } catch (e) {
      print('Error exportando Excel: $e');
    }
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
                        ...comercialesMap.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
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
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(selectedDate != null
                          ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                          : selectedMonth != null
                              ? DateFormat('MMMM yyyy', 'es_ES')
                                  .format(selectedMonth!)
                              : selectedYear != null
                                  ? selectedYear.toString()
                                  : 'Filtrar por fecha'),
                      onPressed: () async {
                        // Mostrar menú para elegir tipo de filtro
                        final tipo = await showModalBottomSheet<String>(
                          context: context,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('Por día'),
                                onTap: () => Navigator.pop(context, 'dia'),
                              ),
                              ListTile(
                                title: const Text('Por mes'),
                                onTap: () => Navigator.pop(context, 'mes'),
                              ),
                              ListTile(
                                title: const Text('Por año'),
                                onTap: () => Navigator.pop(context, 'anio'),
                              ),
                            ],
                          ),
                        );
                        if (tipo == 'dia') {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2023),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                              selectedMonth = null;
                              selectedYear = null;
                            });
                            await _loadTickets(reset: true);
                          }
                        } else if (tipo == 'mes') {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                selectedMonth ?? DateTime(now.year, now.month),
                            firstDate: DateTime(2023),
                            lastDate: now,
                            selectableDayPredicate: (date) => date.day == 1,
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = null;
                              selectedMonth =
                                  DateTime(picked.year, picked.month);
                              selectedYear = null;
                            });
                            await _loadTickets(reset: true);
                          }
                        } else if (tipo == 'anio') {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(selectedYear ?? now.year),
                            firstDate: DateTime(2023),
                            lastDate: now,
                            selectableDayPredicate: (date) =>
                                date.month == 1 && date.day == 1,
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = null;
                              selectedMonth = null;
                              selectedYear = picked.year;
                            });
                            await _loadTickets(reset: true);
                          }
                        }
                      },
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
              // Botones de exportación global
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
                    label: const Text('Exportar todo a Excel'),
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
                              final comercialName =
                                  comercialesMap[data['comercialId']] ??
                                      'Desconocido';
                              return ListTile(
                                leading: const Icon(Icons.receipt_long,
                                    color: Colors.indigo, size: 40),
                                title: Text(
                                    '${data['tipoDoc']} - ${data['tipo']}'),
                                subtitle: Text(
                                  'Comercial: $comercialName\n'
                                  'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Exportar este ticket a PDF
                                    IconButton(
                                      icon: const Icon(Icons.picture_as_pdf),
                                      tooltip: 'Exportar este ticket a PDF',
                                      onPressed: () => _exportarPDFTicket(data),
                                    ),
                                    // Ver imagen
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
                                    // Exportar a Excel para esta fila
                                    IconButton(
                                      icon: const Icon(Icons.table_chart),
                                      tooltip: 'Exportar este ticket a Excel',
                                      onPressed: () =>
                                          _exportarExcelTicket(data),
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
