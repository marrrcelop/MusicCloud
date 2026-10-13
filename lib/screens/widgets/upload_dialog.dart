import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../services/library_repository.dart';
import '../../services/upload_tools.dart';

/// Ventana que sube las canciones elegidas y muestra el avance.
class UploadDialog extends StatefulWidget {
  final LibraryRepository repo;
  final Album album;
  final List<UploadItem> items;

  /// Archivos elegidos que no se pudieron preparar (vacíos o no son audio).
  final List<String> notPrepared;

  const UploadDialog({
    super.key,
    required this.repo,
    required this.album,
    required this.items,
    this.notPrepared = const [],
  });

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  int _index = 0;
  int _sent = 0;
  int _total = 0;
  bool _cancelRequested = false;
  UploadReport? _report;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    UploadReport report;
    try {
      report = await widget.repo.uploadSongs(
        widget.album,
        widget.items,
        onProgress: (index, sent, total) {
          if (!mounted) return;
          setState(() {
            _index = index;
            _sent = sent;
            _total = total;
          });
        },
        isCancelled: () => _cancelRequested,
      );
    } catch (e) {
      report = UploadReport(
        uploaded: 0,
        skipped: const [],
        failed: ['Error inesperado: $e'],
        cancelled: false,
      );
    }
    if (!mounted) return;
    setState(() => _report = report);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return PopScope(
      // Mientras sube, "atrás" no cierra la ventana.
      canPop: report != null,
      child: AlertDialog(
        title: Text(
          report == null
              ? 'Subiendo música'
              : (report.cancelled ? 'Subida cancelada' : 'Subida terminada'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: report == null ? _progress(context) : _summary(context, report),
          ),
        ),
        actions: [
          if (report == null)
            TextButton(
              onPressed: _cancelRequested
                  ? null
                  : () => setState(() => _cancelRequested = true),
              child: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, report),
              child: const Text('Cerrar'),
            ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final item = widget.items[_index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Archivo ${_index + 1} de ${widget.items.length}'),
        const SizedBox(height: 4),
        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: _total > 0 ? _sent / _total : null),
        const SizedBox(height: 4),
        Text(
          '${formatBytes(_sent)} de ${formatBytes(_total == 0 ? item.size : _total)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Mantén la app abierta hasta que termine.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _summary(BuildContext context, UploadReport report) {
    final small = Theme.of(context).textTheme.bodySmall;
    final skipped = report.skipped;
    final failed = report.failed;
    final notPrepared = widget.notPrepared;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(report.uploaded == 1
            ? '1 canción subida.'
            : '${report.uploaded} canciones subidas.'),
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Omitidas (el álbum ya tenía un archivo con ese nombre):'),
          for (final name in skipped) Text('• $name', style: small),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('No se pudieron subir:'),
          for (final line in failed) Text('• $line', style: small),
        ],
        if (notPrepared.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('No se reconocieron como audio (o están vacíos):'),
          for (final name in notPrepared) Text('• $name', style: small),
        ],
      ],
    );
  }
}