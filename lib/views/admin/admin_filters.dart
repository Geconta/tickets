import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminFilters extends StatelessWidget {
  final Map<String, String> comercialesMap;
  final String? filtroComercialId;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final void Function(String?) onComercialChanged;
  final VoidCallback onSeleccionarRangoFechas;
  final VoidCallback onLimpiarRango;

  const AdminFilters({
    super.key,
    required this.comercialesMap,
    required this.filtroComercialId,
    required this.fechaInicio,
    required this.fechaFin,
    required this.onComercialChanged,
    required this.onSeleccionarRangoFechas,
    required this.onLimpiarRango,
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
            value: filtroComercialId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos los usuarios')),
              ...comercialesMap.entries.map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  )),
            ],
            onChanged: onComercialChanged,
          ),
        ),
        SizedBox(
          width: 300,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(
              (fechaInicio != null && fechaFin != null)
                  ? 'Del ${DateFormat('yyyy-MM-dd').format(fechaInicio!)} al ${DateFormat('yyyy-MM-dd').format(fechaFin!)}'
                  : 'Filtrar por rango de fechas',
            ),
            onPressed: onSeleccionarRangoFechas,
          ),
        ),
        if (fechaInicio != null && fechaFin != null)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: onLimpiarRango,
            tooltip: 'Limpiar rango',
          ),
      ],
    );
  }
}
