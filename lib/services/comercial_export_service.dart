import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';

class ComercialExportService {
  static Future<void> exportarPDFTicket(Map<String, dynamic> data) async {
    try {
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );

      final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));
      final fotoFactura = await _descargarImagen(data['fotoFactura']);
      final fotoCopia = await _descargarImagen(data['fotoCopia']);

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tipo: ${data['tipo'] ?? 'Desconocido'}'),
              pw.Text('Fecha: ${_formatearFecha(data['fechaHora'])}'),
              if (data['establecimiento'] != null)
                pw.Text('Establecimiento: ${data['establecimiento']}'),
              if (data['totalEuros'] != null)
                pw.Text('Total: € ${data['totalEuros']}'),
              if (data['observaciones'] != null)
                pw.Text('Observaciones: ${data['observaciones']}'),
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
    } catch (e) {
      print('Error al exportar ticket a PDF: $e');
    }
  }

  static Future<void> exportarTodosLosTicketsPDF(
      List<Map<String, dynamic>> tickets) async {
    try {
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );

      final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));

      for (final data in tickets) {
        final fotoFactura = await _descargarImagen(data['fotoFactura']);
        final fotoCopia = await _descargarImagen(data['fotoCopia']);

        pdf.addPage(
          pw.Page(
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Tipo: ${data['tipo'] ?? 'Desconocido'}'),
                pw.Text('Fecha: ${_formatearFecha(data['fechaHora'])}'),
                if (data['establecimiento'] != null)
                  pw.Text('Establecimiento: ${data['establecimiento']}'),
                if (data['totalEuros'] != null)
                  pw.Text('Total: € ${data['totalEuros']}'),
                if (data['observaciones'] != null)
                  pw.Text('Observaciones: ${data['observaciones']}'),
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
                pw.Divider(),
              ],
            ),
          ),
        );
      }

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      print('Error al exportar todos los tickets: $e');
    }
  }

  static Future<Uint8List?> _descargarImagen(String? url) async {
    if (url == null) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Fallo al descargar imagen: ${response.statusCode}');
      }
    } catch (e) {
      print('Error al descargar imagen: $e');
    }
    return null;
  }

  static String _formatearFecha(dynamic fechaHora) {
    if (fechaHora == null) return 'Fecha desconocida';
    try {
      final DateTime fecha = (fechaHora is Timestamp)
          ? fechaHora.toDate()
          : (fechaHora is DateTime)
              ? fechaHora
              : DateTime.parse(fechaHora.toString());
      return DateFormat('yyyy-MM-dd HH:mm').format(fecha);
    } catch (e) {
      print('Error al formatear fecha: $e');
      return 'Formato de fecha inválido';
    }
  }
}
