import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'dart:html' as html;
import 'package:flutter/services.dart' show rootBundle;

class AdminExportService {
  static Future<void> exportarPDFTicket(
    QueryDocumentSnapshot<Map<String, dynamic>> ticket,
    Map<String, String> comercialesMap,
  ) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));
    final data = ticket.data();
    final comercialId = data['comercialId'];
    final comercialNombre = comercialesMap[comercialId] ?? 'Desconocido';

    final fotoFactura = await _descargarImagen(data['fotoFactura']);
    final fotoCopia = await _descargarImagen(data['fotoCopia']);

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tipo: ${data['tipo']}'),
            pw.Text('Comercial: $comercialNombre'),
            pw.Text(
              'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
            ),
            if (data['establecimiento'] != null)
              pw.Text('Establecimiento: ${data['establecimiento']}'),
            if (data['totalEuros'] != null)
              pw.Text('Total: € ${data['totalEuros']}'),
            if (fotoFactura != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Column(children: [
                  pw.Text('Factura simplificada:'),
                  pw.Image(pw.MemoryImage(fotoFactura),
                      width: 200, height: 200, fit: pw.BoxFit.cover),
                ]),
              ),
            if (fotoCopia != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Column(children: [
                  pw.Text('Copia cliente:'),
                  pw.Image(pw.MemoryImage(fotoCopia),
                      width: 200, height: 200, fit: pw.BoxFit.cover),
                ]),
              ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> exportarPDFTodos(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets,
    Map<String, String> comercialesMap,
  ) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));

    final usuariosSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    final Map<String, Map<String, dynamic>> mapaUsuarios = {
      for (var doc in usuariosSnapshot.docs) doc.id: doc.data()
    };

    for (var doc in tickets) {
      final data = doc.data();
      final comercialId = data['comercialId'];
      final comercial = mapaUsuarios[comercialId];
      final nombre = comercial?['name'] ?? 'Desconocido';
      final apellido = comercial?['lastName'] ?? '';

      final imageFactura = await _descargarImagen(data['fotoFactura']);
      final imageCopia = await _descargarImagen(data['fotoCopia']);

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo']}'),
              pw.Text('Comercial: $nombre $apellido'),
              pw.Text(
                'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
              ),
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
    }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> exportarExcelTodos({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets,
    required Map<String, String> comercialesMap,
    required String? filtroComercialId,
    required DateTime? selectedDate,
    required BuildContext context,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Tickets';

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

    sheet
        .getRangeByName('A1')
        .setText('Liquidación de gastos de viaje y representación visa');
    sheet.getRangeByName('A1').cellStyle = tituloStyle;
    sheet.getRangeByName('A1').columnWidth = 60;

    sheet.getRangeByName('A2').setText('GECONTA medidores de fluidos SL');
    sheet.getRangeByName('A2').cellStyle = subtituloStyle;
    sheet.getRangeByName('A3').setText('');

    if (selectedDate != null) {
      final mes = DateFormat('MMMM yyyy', 'es_ES').format(selectedDate);
      sheet.getRangeByName('A4').setText(mes);
    }

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

    final Map<String, Map<String, double>> resumen = {};
    for (final doc in tickets) {
      final data = doc.data();
      final fecha = DateFormat('yyyy-MM-dd').format(data['fechaHora'].toDate());
      final tipo = data['tipo'] ?? '';
      final total = (data['totalEuros'] is num)
          ? (data['totalEuros'] as num).toDouble()
          : double.tryParse(data['totalEuros']?.toString() ?? '') ?? 0.0;

      resumen.putIfAbsent(fecha, () => {});
      resumen[fecha]![tipo] = (resumen[fecha]![tipo] ?? 0) + total;
    }

    int row = 6;
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

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final nombreComercial = filtroComercialId != null
        ? comercialesMap[filtroComercialId!] ?? 'Comercial'
        : 'Todos';
    final nombreArchivo = 'Gastos_${nombreComercial.replaceAll(' ', '_')}.xlsx';

    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', nombreArchivo)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static Future<Uint8List?> _descargarImagen(String? url) async {
    if (url == null) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      print('Error al descargar imagen: $e');
    }
    return null;
  }
}
