import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import 'dart:convert';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:flutter/services.dart' show rootBundle;

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  DateTime? selectedDate;
  DateTime? selectedMonth;
  int? selectedYear;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  String? filtroComercialId; // null para "Todos los comerciales"
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
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('tickets')
        .orderBy('fechaHora', descending: true);

    if (fechaInicio != null && fechaFin != null) {
      final start =
          DateTime(fechaInicio!.year, fechaInicio!.month, fechaInicio!.day);
      final end = DateTime(fechaFin!.year, fechaFin!.month, fechaFin!.day + 1);
      query = query
          .where('fechaHora', isGreaterThanOrEqualTo: start)
          .where('fechaHora', isLessThan: end);
    } else if (selectedDate != null) {
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
    print('Tickets encontrados: ${snapshot.docs.length}');
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

  // Exportar todos los tickets filtrados a PDF
  Future<void> _exportarPDFTodos(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets) async {
    final pdf = pw.Document();
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );

    // Cargar todos los usuarios de una vez
    final usuariosSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    final Map<String, Map<String, dynamic>> mapaUsuarios = {
      for (var doc in usuariosSnapshot.docs) doc.id: doc.data()
    };

    for (var doc in tickets) {
      final data = doc.data();

      // Buscar comercial
      final comercialId = data['comercialId'];
      final comercial = mapaUsuarios[comercialId];
      final nombre = comercial?['name'] ?? 'Desconocido';
      final apellido = comercial?['lastName'] ?? '';

      // Descargar imágenes en paralelo
      final futures = <Future<Uint8List?>>[];

      if (data['fotoFactura'] != null) {
        futures.add(_descargarImagen(data['fotoFactura']));
      } else {
        futures.add(Future.value(null));
      }

      if (data['fotoCopia'] != null) {
        futures.add(_descargarImagen(data['fotoCopia']));
      } else {
        futures.add(Future.value(null));
      }

      final results = await Future.wait(futures);
      final imageFactura = results[0];
      final imageCopia = results[1];

      // Crear la página PDF
      pdf.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(base: font),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo']}'),
              pw.Text('Comercial: $nombre $apellido'),
              pw.Text(
                  'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}'),
              if (data['establecimiento'] != null)
                pw.Text('Establecimiento: ${data['establecimiento']}'),
              if (data['totalEuros'] != null)
                pw.Text('Total: € ${data['totalEuros']}'),
              pw.SizedBox(height: 10),
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

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<Uint8List?> _descargarImagen(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Error al descargar imagen: ${response.statusCode}');
      }
    } catch (e) {
      print('Error al descargar imagen: $e');
    }
    return null;
  }

  // Exportar un ticket específico a PDF
  Future<void> _exportarPDFTicket(
    QueryDocumentSnapshot<Map<String, dynamic>> ticket,
  ) async {
    final pdf = pw.Document();
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final data = ticket.data();

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
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );

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
    // Mostrar el PDF generado
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

      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Tickets';

      // ==== Estilos ====
      final tituloStyle = workbook.styles.add('tituloStyle');
      tituloStyle.fontSize = 16;
      tituloStyle.bold = true;
      tituloStyle.fontColor = '#FFFFFF';
      tituloStyle.backColor = '#4472C4';
      tituloStyle.hAlign = xlsio.HAlignType.center;

      final subtituloStyle = workbook.styles.add('subtituloStyle');
      subtituloStyle.fontSize = 12;
      subtituloStyle.bold = true;

      final encabezadoTablaStyle = workbook.styles.add('encabezadoTabla');
      encabezadoTablaStyle.bold = true;
      encabezadoTablaStyle.backColor = '#D9E1F2';
      encabezadoTablaStyle.hAlign = xlsio.HAlignType.center;

      // ==== Título y subtítulo ====
      sheet
          .getRangeByName('A1')
          .setText('Liquidación de gastos de viaje y representación visa');
      sheet.getRangeByName('A1').cellStyle = tituloStyle;
      sheet.getRangeByName('A1').columnWidth = 60;

      sheet.getRangeByName('A2').setText('GECONTA medidores de fluidos SL');
      sheet.getRangeByName('A2').cellStyle = subtituloStyle;

      // ==== Mes (si hay) ====
      String mes = '';
      if (selectedDate != null) {
        mes = DateFormat('MMMM yyyy', 'es_ES').format(selectedDate!);
        sheet.getRangeByName('A3').setText(mes);
      }

      // ==== Fila vacía de separación ====
      sheet.getRangeByName('A4').setText('');

      // ==== Encabezados de tabla ====
      final headers = [
        'Fecha',
        'Transporte',
        'Manutención',
        'Alojamiento',
        'Varios',
        'Total'
      ];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(5, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle = encabezadoTablaStyle;
        sheet.autoFitColumn(i + 1);
      }

      // ==== Agrupar tickets ====
      final Map<String, Map<String, double>> resumen = {};

      for (final doc in tickets) {
        final data = doc.data();
        final fecha =
            DateFormat('yyyy-MM-dd').format(data['fechaHora'].toDate());
        final tipo = data['tipo'] ?? '';
        final total = (data['totalEuros'] is num)
            ? (data['totalEuros'] as num).toDouble()
            : double.tryParse(data['totalEuros']?.toString() ?? '') ?? 0.0;

        resumen.putIfAbsent(fecha, () => {});
        resumen[fecha]![tipo] = (resumen[fecha]![tipo] ?? 0) + total;
      }

      // ==== Escribir filas ====
      int row = 6; // Comienza debajo de los encabezados

      for (final fecha in resumen.keys) {
        final tipos = resumen[fecha]!;

        final variosTotal =
            (tipos['Varios'] ?? 0) + (tipos['Gastos de representación'] ?? 0);
        final totalDia = tipos.values.fold<double>(0, (a, b) => a + b);

        sheet.getRangeByIndex(row, 1).setText(fecha);
        sheet.getRangeByIndex(row, 2).setNumber(tipos['Transporte'] ?? 0);
        sheet.getRangeByIndex(row, 3).setNumber(tipos['Manutención'] ?? 0);
        sheet.getRangeByIndex(row, 4).setNumber(tipos['Alojamiento'] ?? 0);
        sheet
            .getRangeByIndex(row, 5)
            .setNumber(variosTotal > 0 ? variosTotal : 0);
        sheet.getRangeByIndex(row, 6).setNumber(totalDia);

        row++;
      }

      // ==== Guardar y descargar ====
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final blob = html.Blob([Uint8List.fromList(bytes)],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'gastos.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exportando Excel: $e')),
      );
      print('Error exportando Excel: $e');
    }
  }

  Future<void> _exportarExcelTicketWeb(Map<String, dynamic> data) async {
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

      // Descargar el archivo Excel en web
      final blob = html.Blob([bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'ticket.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('Error exportando Excel: $e');
    }
  }

  Future<double?> extraerTotalDeImagenWeb(XFile imagen) async {
    final bytes = await imagen.readAsBytes();
    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final request = http.MultipartRequest('POST', uri)
      ..fields['language'] = 'spa'
      ..fields['isOverlayRequired'] = 'false'
      ..fields['OCREngine'] = '2'
      ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'ticket.jpg'));

    // Puedes usar tu propia API key gratuita de OCR.space, o usar 'helloworld' para pruebas limitadas
    request.headers['apikey'] = 'helloworld';

    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    final jsonResp = json.decode(respStr);

    if (jsonResp['IsErroredOnProcessing'] == false) {
      final text = jsonResp['ParsedResults'][0]['ParsedText'] as String;
      // Busca el total with regex
      final regex = RegExp(r'total[:\s]*([\d\.,]+)', caseSensitive: false);
      final match = regex.firstMatch(text);
      if (match != null) {
        final value = match.group(1)?.replaceAll(',', '.');
        return double.tryParse(value ?? '');
      }
    }
    return null;
  }

  Future<void> _seleccionarRangoFechas(BuildContext context) async {
    DateTime tempInicio = fechaInicio ?? DateTime.now();
    DateTime tempFin = fechaFin ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecciona el rango de fechas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                    'Desde: ${DateFormat('yyyy-MM-dd').format(tempInicio)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: tempInicio,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    tempInicio = picked;
                    if (tempFin.isBefore(tempInicio)) tempFin = tempInicio;
                    (context as Element).markNeedsBuild();
                  }
                },
              ),
              ListTile(
                title:
                    Text('Hasta: ${DateFormat('yyyy-MM-dd').format(tempFin)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: tempFin,
                    firstDate: tempInicio,
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    tempFin = picked;
                    (context as Element).markNeedsBuild();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  fechaInicio = tempInicio;
                  fechaFin = tempFin;
                  selectedDate = null;
                  selectedMonth = null;
                  selectedYear = null;
                });
                Navigator.pop(context);
                _loadTickets(reset: true);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
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
              const SizedBox(height: 10),
              const Text(
                'Listado de todos los tickets subidos:',
                style: TextStyle(fontSize: 18, color: Colors.black54),
                textAlign: TextAlign.left,
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
                  // Filtro por fecha
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        (fechaInicio != null && fechaFin != null)
                            ? 'Del ${DateFormat('yyyy-MM-dd').format(fechaInicio!)} al ${DateFormat('yyyy-MM-dd').format(fechaFin!)}'
                            : 'Filtrar por rango de fechas',
                      ),
                      onPressed: () => _seleccionarRangoFechas(context),
                    ),
                  ),
                  if (fechaInicio != null && fechaFin != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () async {
                        setState(() {
                          fechaInicio = null;
                          fechaFin = null;
                        });
                        await _loadTickets(reset: true);
                      },
                      tooltip: 'Limpiar rango',
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
                    onPressed: () async {
                      try {
                        final snapshot = await FirebaseFirestore.instance
                            .collection('tickets')
                            .get();

                        if (snapshot.docs.isEmpty) {
                          print('⚠️ No hay tickets para exportar.');
                          return;
                        }

                        await _exportarPDFTodos(snapshot.docs);
                      } catch (e, st) {
                        print('❌ Error al exportar PDF: $e');
                        print(st);
                      }
                    },
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
                              final ticket = tickets[index];
                              final data = ticket.data();
                              final comercialName =
                                  comercialesMap[data['comercialId']] ??
                                      'Desconocido';
                              return ListTile(
                                leading: const Icon(Icons.receipt_long,
                                    color: Colors.indigo, size: 40),
                                title: Text(
                                  (data['tipoDoc'] != null &&
                                          data['tipoDoc'].toString().isNotEmpty)
                                      ? '${data['tipoDoc']} - ${data['tipo']}'
                                      : '${data['tipo']}',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Comercial: $comercialName\n'
                                      'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
                                    ),
                                    if (data['establecimiento'] != null)
                                      Text(
                                          'Establecimiento: ${data['establecimiento']}'),
                                    if (data['totalEuros'] != null)
                                      Text(
                                        'Total: €${data['totalEuros']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.picture_as_pdf),
                                      tooltip: 'Exportar este ticket a PDF',
                                      onPressed: () =>
                                          _exportarPDFTicket(ticket),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.visibility),
                                      tooltip: 'Ver imagen',
                                      onPressed: (data['fotoFactura'] != null ||
                                              data['fotoCopia'] != null)
                                          ? () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => Dialog(
                                                  child: SizedBox(
                                                    width: 800,
                                                    height: 600,
                                                    child: InteractiveViewer(
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          if (data[
                                                                  'fotoFactura'] !=
                                                              null)
                                                            Expanded(
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        8.0),
                                                                child: Image
                                                                    .network(
                                                                  data[
                                                                      'fotoFactura'],
                                                                  fit: BoxFit
                                                                      .contain,
                                                                ),
                                                              ),
                                                            ),
                                                          if (data[
                                                                  'fotoCopia'] !=
                                                              null)
                                                            Expanded(
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        8.0),
                                                                child: Image
                                                                    .network(
                                                                  data[
                                                                      'fotoCopia'],
                                                                  fit: BoxFit
                                                                      .contain,
                                                                ),
                                                              ),
                                                            ),
                                                          if (data['fotoFactura'] ==
                                                                  null &&
                                                              data['fotoCopia'] ==
                                                                  null)
                                                            const Padding(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(24),
                                                              child: Text(
                                                                  'Sin imagen'),
                                                            ),
                                                        ],
                                                      ),
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
