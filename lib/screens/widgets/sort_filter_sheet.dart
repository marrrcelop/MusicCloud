import 'package:flutter/material.dart';
import '../../models/library_view.dart';
import '../../services/library_view_controller.dart';

/// Panel inferior con las opciones de orden y los filtros.
class SortFilterSheet extends StatelessWidget {
  final LibraryViewController controller;
  final FilterOptions options;

  const SortFilterSheet({
    super.key,
    required this.controller,
    required this.options,
  });

  static Future<void> show(
    BuildContext context, {
    required LibraryViewController controller,
    required FilterOptions options,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SortFilterSheet(controller: controller, options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListenableBuilder(
        // Los chips se actualizan al instante cuando eliges algo.
        listenable: controller,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Heading('Ordenar por'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final o in SortOrder.values)
                      ChoiceChip(
                        label: Text(o.label),
                        selected: controller.order == o,
                        onSelected: (_) => controller.setOrder(o),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Ascendente'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Descendente'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                  ],
                  selected: {controller.ascending},
                  onSelectionChanged: (s) => controller.setAscending(s.first),
                ),
                if (!options.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  if (options.artists.isNotEmpty)
                    _FilterGroup<String>(
                      title: 'Artista',
                      values: options.artists,
                      selected: controller.artist,
                      onChanged: controller.setArtist,
                      label: (v) => v,
                    ),
                  if (options.genres.isNotEmpty)
                    _FilterGroup<String>(
                      title: 'Género',
                      values: options.genres,
                      selected: controller.genre,
                      onChanged: controller.setGenre,
                      label: (v) => v,
                    ),
                  if (options.years.isNotEmpty)
                    _FilterGroup<int>(
                      title: 'Año',
                      values: options.years,
                      selected: controller.year,
                      onChanged: controller.setYear,
                      label: (v) => '$v',
                    ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    'Para filtrar por artista, género o año, agrega esos datos '
                    'en el album.json de tus carpetas.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (controller.hasFilters) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off),
                    label: const Text('Quitar filtros'),
                    onPressed: controller.clearFilters,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Un grupo de chips: "Todos" y un chip por cada valor disponible.
class _FilterGroup<T> extends StatelessWidget {
  final String title;
  final List<T> values;
  final T? selected;
  final ValueChanged<T?> onChanged;
  final String Function(T) label;

  const _FilterGroup({
    required this.title,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: selected == v,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ],
    );
  }
}