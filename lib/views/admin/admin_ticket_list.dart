import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tickets_app/services/admin_export_service.dart';

class AdminTicketList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets;
  final Map<String, String> comercialesMap;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final void Function(Map<String, dynamic> data) onVerImagen;

  const AdminTicketList({
    super.key,
    required this.tickets,
    required this.comercialesMap,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    required this.onVerImagen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (tickets.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tickets.isEmpty) {
      return const Center(child: Text('No hay tickets subidos.'));
    }

    return ListView.separated(
      itemCount: tickets.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == tickets.length) {
          return Center(
            child: TextButton.icon(
              icon: const Icon(Icons.expand_more),
              label: const Text('Cargar más'),
              onPressed: isLoading ? null : onLoadMore,
            ),
          );
        }

        final ticket = tickets[index];
        final data = ticket.data();
        final comercialName =
            comercialesMap[data['comercialId']] ?? 'Desconocido';

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Título
                Row(
                  children: [
                    const Icon(Icons.receipt_long,
                        size: 28, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${data['tipoDoc'] ?? 'Documento'} - ${data['tipo'] ?? 'Tipo'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf),
                          tooltip: 'Exportar a PDF',
                          onPressed: () async {
                            await AdminExportService.exportarPDFTicket(
                                ticket, comercialesMap);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          tooltip: 'Ver imagen',
                          onPressed: (data['fotoFactura'] != null ||
                                  data['fotoCopia'] != null)
                              ? () => onVerImagen(data)
                              : null,
                        ),
                      ],
                    )
                  ],
                ),

                const SizedBox(height: 8),

                /// Detalles
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    _TicketDetail(label: 'Comercial', value: comercialName),
                    _TicketDetail(
                      label: 'Fecha',
                      value: DateFormat('yyyy-MM-dd HH:mm')
                          .format(data['fechaHora'].toDate()),
                    ),
                    if (data['establecimiento'] != null)
                      _TicketDetail(
                          label: 'Establecimiento',
                          value: data['establecimiento']),
                    if (data['totalEuros'] != null)
                      _TicketDetail(
                        label: 'Total',
                        value: '€${data['totalEuros']}',
                        isBold: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TicketDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _TicketDetail({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        style: const TextStyle(color: Colors.grey),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: Colors.black,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
