import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class FormularioNuevoTicket extends StatefulWidget {
  final Function(
    String tipoTicket,
    XFile factura,
    XFile copia,
    String? total,
    String? observaciones,
    DateTime? fecha,
  ) onSubmit;

  const FormularioNuevoTicket({super.key, required this.onSubmit});

  @override
  State<FormularioNuevoTicket> createState() => _FormularioNuevoTicketState();
}

class _FormularioNuevoTicketState extends State<FormularioNuevoTicket> {
  final List<String> tipos = [
    'Transporte',
    'Manutención',
    'Alojamiento',
    'Varios',
    'Gastos de representación',
  ];

  String? tipoTicketNuevo;
  XFile? imagenFactura;
  XFile? imagenCopia;
  bool isUploading = false;
  DateTime? fechaTicketManual;

  final TextEditingController totalController = TextEditingController();
  final TextEditingController observacionesController = TextEditingController();

  Future<XFile?> _seleccionarImagen() async {
    final picker = ImagePicker();
    return await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final formWidth = (screenWidth > 600 ? 600 : screenWidth * 0.95) as double;

    return Center(
      child: Container(
        width: formWidth,
        child: SingleChildScrollView(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: tipoTicketNuevo,
                    items: tipos
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => tipoTicketNuevo = v),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de ticket',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botones de imagen en columna
                  Column(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(
                          Icons.camera_alt,
                          color:
                              imagenFactura == null ? Colors.grey : Colors.blue,
                        ),
                        label: Text(imagenFactura == null
                            ? 'Subir Factura simplificada'
                            : 'Factura lista'),
                        onPressed: () async {
                          final picked = await _seleccionarImagen();
                          if (picked != null) {
                            setState(() => imagenFactura = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: Icon(
                          Icons.camera_alt,
                          color:
                              imagenCopia == null ? Colors.grey : Colors.blue,
                        ),
                        label: Text(imagenCopia == null
                            ? 'Subir Copia cliente'
                            : 'Copia lista'),
                        onPressed: () async {
                          final picked = await _seleccionarImagen();
                          if (picked != null) {
                            setState(() => imagenCopia = picked);
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: totalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total (€) (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range),
                          label: Text(fechaTicketManual == null
                              ? 'Seleccionar fecha del ticket (Opcional)'
                              : 'Fecha: ${DateFormat('yyyy-MM-dd').format(fechaTicketManual!)}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => fechaTicketManual = picked);
                            }
                          },
                        ),
                      ),
                      if (fechaTicketManual != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Borrar fecha',
                          onPressed: () =>
                              setState(() => fechaTicketManual = null),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: observacionesController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (tipoTicketNuevo != null &&
                                imagenFactura != null &&
                                imagenCopia != null &&
                                !isUploading)
                            ? Colors.blue[700]
                            : Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: (tipoTicketNuevo != null &&
                              imagenFactura != null &&
                              imagenCopia != null &&
                              !isUploading)
                          ? () {
                              widget.onSubmit(
                                tipoTicketNuevo!,
                                imagenFactura!,
                                imagenCopia!,
                                totalController.text,
                                observacionesController.text,
                                fechaTicketManual,
                              );

                              setState(() {
                                tipoTicketNuevo = null;
                                imagenFactura = null;
                                imagenCopia = null;
                                totalController.clear();
                                observacionesController.clear();
                                fechaTicketManual = null;
                              });
                            }
                          : null,
                      child: isUploading
                          ? const CircularProgressIndicator()
                          : const Text(
                              'Crear nuevo registro',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
