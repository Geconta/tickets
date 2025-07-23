import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FiltrosTickets extends StatelessWidget {
  final List<String> tipos;
  final String? tipoSeleccionado;
  final DateTime? fechaSeleccionada;

  final void Function(String?) onTipoCambiado;
  final VoidCallback onLimpiarTipo;

  final void Function(DateTime?) onFechaCambiada;
  final VoidCallback onLimpiarFecha;

  const FiltrosTickets({
    super.key,
    required this.tipos,
    required this.tipoSeleccionado,
    required this.fechaSeleccionada,
    required this.onTipoCambiado,
    required this.onLimpiarTipo,
    required this.onFechaCambiada,
    required this.onLimpiarFecha,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            value: tipoSeleccionado ?? '',
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos los tipos')),
              ...tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))),
            ],
            onChanged: (v) => onTipoCambiado(v == '' ? null : v),
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (tipoSeleccionado != null && tipoSeleccionado!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Quitar filtro de tipo',
            onPressed: onLimpiarTipo,
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today),
          label: Text(fechaSeleccionada == null
              ? 'Filtrar por fecha'
              : DateFormat('yyyy-MM-dd').format(fechaSeleccionada!)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: fechaSeleccionada ?? DateTime.now(),
              firstDate: DateTime(2023),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              onFechaCambiada(picked);
            }
          },
        ),
        if (fechaSeleccionada != null)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Limpiar fecha',
            onPressed: onLimpiarFecha,
          ),
      ],
    );
  }
}
