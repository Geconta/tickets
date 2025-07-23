import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:tickets_app/views/admin/admin_filters.dart ';
import 'package:tickets_app/views/admin/admin_ticket_list.dart';
import 'package:tickets_app/services/admin_export_service.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String? filtroComercialId;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  DateTime? selectedDate;

  final int pageSize = 10;
  DocumentSnapshot? lastDoc;
  bool isLoading = false;
  bool hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets = [];
  Map<String, String> comercialesMap = {};

  @override
  void initState() {
    super.initState();
    _loadComerciales();
    _loadTickets(reset: true);
  }

  Future<void> _loadComerciales() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final Map<String, String> nombres = {
      for (var doc in snapshot.docs) doc.id: '${doc['name']} ${doc['lastName']}'
    };
    setState(() => comercialesMap = nombres);
  }

  Future<void> _loadTickets({bool reset = false}) async {
    setState(() => isLoading = true);

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

      // 👉 Asignar orden mensual
      tickets = _asignarOrdenMensual(tickets);

      if (snapshot.docs.length < pageSize) hasMore = false;
    } else {
      hasMore = false;
    }

    setState(() => isLoading = false);
  }

// 👉 Función auxiliar para asignar el orden mensual
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _asignarOrdenMensual(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets) {
    final Map<String, int> contadorPorMes = {};
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> ordenados = [
      ...tickets
    ];

    // Ordenar por fecha ascendente
    ordenados.sort((a, b) {
      final fechaA = a['fechaHora'].toDate() as DateTime;
      final fechaB = b['fechaHora'].toDate() as DateTime;
      return fechaA.compareTo(fechaB);
    });

    for (var doc in ordenados) {
      final fecha = doc['fechaHora'].toDate() as DateTime;
      final claveMes =
          '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

      contadorPorMes[claveMes] = (contadorPorMes[claveMes] ?? 0) + 1;

      // Añadir campo temporal solo para mostrar
      doc.data()['ordenMensual'] = contadorPorMes[claveMes];
    }

    return ordenados;
  }

  void _onFiltroComercialChanged(String? value) async {
    setState(() => filtroComercialId = value);
    await _loadTickets(reset: true);
  }

  Future<void> _seleccionarRangoFechas(BuildContext context) async {
    DateTime tempInicio = fechaInicio ?? DateTime.now();
    DateTime tempFin = fechaFin ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecciona el rango de fechas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title:
                  Text('Desde: ${DateFormat('yyyy-MM-dd').format(tempInicio)}'),
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
              title: Text('Hasta: ${DateFormat('yyyy-MM-dd').format(tempFin)}'),
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
              });
              Navigator.pop(context);
              _loadTickets(reset: true);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  void _verImagenDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 800,
          height: 600,
          child: Row(
            children: [
              if (data['fotoFactura'] != null)
                Expanded(
                  child:
                      Image.network(data['fotoFactura'], fit: BoxFit.contain),
                ),
              if (data['fotoCopia'] != null)
                Expanded(
                  child: Image.network(data['fotoCopia'], fit: BoxFit.contain),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administrador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Listado de Tickets',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                AdminFilters(
                  comercialesMap: comercialesMap,
                  filtroComercialId: filtroComercialId,
                  fechaInicio: fechaInicio,
                  fechaFin: fechaFin,
                  onComercialChanged: _onFiltroComercialChanged,
                  onSeleccionarRangoFechas: () =>
                      _seleccionarRangoFechas(context),
                  onLimpiarRango: () async {
                    setState(() {
                      fechaInicio = null;
                      fechaFin = null;
                    });
                    await _loadTickets(reset: true);
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Exportar todo a PDF'),
                      onPressed: () async {
                        final snapshot = await FirebaseFirestore.instance
                            .collection('tickets')
                            .get();
                        if (snapshot.docs.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('No hay tickets para exportar')),
                          );
                          return;
                        }
                        await AdminExportService.exportarPDFTodos(
                          snapshot.docs,
                          comercialesMap,
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.table_chart),
                      label: const Text('Exportar todo a Excel'),
                      onPressed: tickets.isEmpty
                          ? null
                          : () async {
                              await AdminExportService.exportarExcelTodos(
                                tickets: tickets,
                                comercialesMap: comercialesMap,
                                filtroComercialId: filtroComercialId,
                                selectedDate: selectedDate,
                                context: context,
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AdminTicketList(
                    tickets: tickets,
                    comercialesMap: comercialesMap,
                    hasMore: hasMore,
                    isLoading: isLoading,
                    onLoadMore: () => _loadTickets(),
                    onVerImagen: _verImagenDialog,
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
