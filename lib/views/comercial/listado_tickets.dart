import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tickets_app/services/comercial_export_service.dart';

class ListadoTickets extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets;
  final void Function(List<Map<String, dynamic>> ticketsData) onExportarTodos;
  final void Function(Map<String, dynamic> data) onExportarPDF;
  final void Function(String id, String? urlFactura, String? urlCopia)
      onEliminar;

  const ListadoTickets({
    super.key,
    required this.tickets,
    required this.onExportarPDF,
    required this.onExportarTodos,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const Center(child: Text('Sin historial.'));
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              final datos = tickets.map((doc) {
                final data = doc.data();
                data['id'] = doc.id;
                return data;
              }).toList();
              onExportarTodos(datos);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Exportar todo'),
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tickets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = tickets[index];
            final data = doc.data();
            data['id'] = doc.id;

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text('${data['tipo']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data['fechaHora'] is Timestamp)
                      Text(
                        'Fecha: ${DateFormat('yyyy-MM-dd HH:mm').format(data['fechaHora'].toDate())}',
                      ),
                    if (data['establecimiento'] != null)
                      Text('Establecimiento: ${data['establecimiento']}'),
                    if (data['totalEuros'] != null)
                      Text(
                        'Total: €${data['totalEuros']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    Text(
                      'Observaciones: ${data['observaciones']?.toString().isNotEmpty == true ? data['observaciones'] : 'Sin observaciones'}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      tooltip: 'Ver imágenes',
                      onPressed: () {
                        final fotoFactura = data['fotoFactura'];
                        final fotoCopia = data['fotoCopia'];

                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Imágenes del ticket'),
                              content: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    if (fotoFactura != null)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Factura:'),
                                          const SizedBox(height: 5),
                                          Image.network(fotoFactura),
                                          const SizedBox(height: 10),
                                        ],
                                      ),
                                    if (fotoCopia != null)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Copia:'),
                                          const SizedBox(height: 5),
                                          Image.network(fotoCopia),
                                        ],
                                      ),
                                    if (fotoFactura == null &&
                                        fotoCopia == null)
                                      const Text('Sin imágenes disponibles.'),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf),
                      tooltip: 'Exportar PDF',
                      onPressed: () => onExportarPDF(data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Eliminar',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('¿Eliminar ticket?'),
                            content:
                                const Text('¿Deseas eliminar este ticket?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          onEliminar(
                              doc.id, data['fotoFactura'], data['fotoCopia']);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
