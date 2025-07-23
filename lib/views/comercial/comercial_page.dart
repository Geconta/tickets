import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'formulario_nuevo_ticket.dart';
import 'listado_tickets.dart';
import 'filtros_tickets.dart';
import 'package:tickets_app/services/comercial_export_service.dart';

class ComercialPage extends StatefulWidget {
  const ComercialPage({super.key});

  @override
  State<ComercialPage> createState() => _ComercialPageState();
}

class _ComercialPageState extends State<ComercialPage> {
  final List<String> tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];

  String? filtroTipoTicket;
  DateTime? selectedDate;
  String nombreUsuario = '';
  bool mostrarHistorico = false;

  @override
  void initState() {
    super.initState();
    _cargarNombreUsuario();
  }

  Future<void> _cargarNombreUsuario() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      setState(() {
        nombreUsuario =
            '${data?['name'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
      });
    }
  }

  bool _esDeEsteMes(DateTime fecha) {
    final hoy = DateTime.now();
    return fecha.year == hoy.year && fecha.month == hoy.month;
  }

  Future<void> _eliminarTicket(
      String ticketId, String? fotoFacturaUrl, String? fotoCopiaUrl) async {
    try {
      await FirebaseFirestore.instance
          .collection('tickets')
          .doc(ticketId)
          .delete();

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

  void _exportarPDFTicket(Map<String, dynamic> data) {
    ComercialExportService.exportarPDFTicket(data);
  }

  void _exportarTodosLosTickets(List<Map<String, dynamic>> ticketsData) async {
    await ComercialExportService.exportarTodosLosTicketsPDF(ticketsData);
  }

  Widget _buildListado() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Text('Usuario no autenticado');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('comercialId', isEqualTo: user.uid)
          .orderBy('fechaHora', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets =
            snapshot.data!.docs;

        tickets = tickets.where((d) {
          final fecha = d['fechaHora'].toDate();
          return mostrarHistorico ? !_esDeEsteMes(fecha) : _esDeEsteMes(fecha);
        }).toList();

        if ((filtroTipoTicket ?? '').isNotEmpty) {
          tickets =
              tickets.where((d) => d['tipo'] == filtroTipoTicket).toList();
        }

        if (selectedDate != null) {
          tickets = tickets.where((d) {
            final fecha = d['fechaHora'].toDate();
            return fecha.year == selectedDate!.year &&
                fecha.month == selectedDate!.month &&
                fecha.day == selectedDate!.day;
          }).toList();
        }

        return ListadoTickets(
          tickets: tickets,
          onExportarPDF: _exportarPDFTicket,
          onExportarTodos: _exportarTodosLosTickets,
          onEliminar: _eliminarTicket,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.06),
      appBar: AppBar(
        title: Text(
          nombreUsuario.isEmpty ? 'Usuario' : 'Bienvenido, $nombreUsuario',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Nuevo ticket'),
                                  ),
                                  body: SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: FormularioNuevoTicket(
                                      onSubmit: (tipo, factura, copia, total,
                                          obs, fecha) async {
                                        final user =
                                            FirebaseAuth.instance.currentUser;
                                        final supabase =
                                            Supabase.instance.client;

                                        final nombreFactura =
                                            '${user!.uid}_${DateTime.now().millisecondsSinceEpoch}_factura.jpg';
                                        final nombreCopia =
                                            '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_copia.jpg';

                                        final bytesFactura =
                                            await factura.readAsBytes();
                                        final bytesCopia =
                                            await copia.readAsBytes();

                                        await supabase.storage
                                            .from('ticketsfotos')
                                            .uploadBinary(
                                                nombreFactura, bytesFactura);
                                        await supabase.storage
                                            .from('ticketsfotos')
                                            .uploadBinary(
                                                nombreCopia, bytesCopia);

                                        final ticketsRef = FirebaseFirestore
                                            .instance
                                            .collection('tickets');

                                        final ultimoTicket = await ticketsRef
                                            .orderBy('orden', descending: true)
                                            .limit(1)
                                            .get();

                                        int nuevoOrden = 1;
                                        if (ultimoTicket.docs.isNotEmpty) {
                                          final ultimo =
                                              ultimoTicket.docs.first.data();
                                          nuevoOrden =
                                              (ultimo['orden'] ?? 0) + 1;
                                        }

                                        await ticketsRef.add({
                                          'comercialId': user.uid,
                                          'tipo': tipo,
                                          'fotoFactura': supabase.storage
                                              .from('ticketsfotos')
                                              .getPublicUrl(nombreFactura),
                                          'fotoCopia': supabase.storage
                                              .from('ticketsfotos')
                                              .getPublicUrl(nombreCopia),
                                          'fechaHora': fecha ?? DateTime.now(),
                                          'totalEuros': double.tryParse(
                                              total?.replaceAll(',', '.') ??
                                                  ''),
                                          'observaciones': obs,
                                          'orden': nuevoOrden,
                                        });

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Ticket creado con éxito')));
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Nuevo ticket'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              mostrarHistorico = !mostrarHistorico;
                            });
                          },
                          icon: const Icon(Icons.history),
                          label: Text(mostrarHistorico
                              ? 'Ver mes actual'
                              : 'Ver histórico'),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Filtros',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        FiltrosTickets(
                          tipos: tipos,
                          tipoSeleccionado: filtroTipoTicket,
                          fechaSeleccionada: selectedDate,
                          onTipoCambiado: (tipo) =>
                              setState(() => filtroTipoTicket = tipo),
                          onLimpiarTipo: () =>
                              setState(() => filtroTipoTicket = null),
                          onFechaCambiada: (fecha) =>
                              setState(() => selectedDate = fecha),
                          onLimpiarFecha: () =>
                              setState(() => selectedDate = null),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                    mostrarHistorico
                        ? 'Histórico de tickets'
                        : 'Tickets del mes actual',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildListado(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
