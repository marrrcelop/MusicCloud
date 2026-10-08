import 'dart:io';
import 'package:flutter/material.dart';
import '../settings/app_fonts.dart';
import '../settings/app_themes.dart';
import '../settings/progress_styles.dart';
import '../settings/settings_scope.dart';
import 'widgets/progress_bar_data.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Ejecuta la elección de una imagen y avisa si algo falla.
  Future<void> _pickImage(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      debugPrint('Error al elegir la imagen: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cargar la imagen')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final style = ProgressStyles.byId(settings.progressStyleId);
    final mascotPath = settings.mascotPath;
    final spritePath = settings.spritePath;

    return Scaffold(
      appBar: AppBar(title: const Text('Personalización')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ---------- Tema ----------
          const _SectionTitle('Tema'),
          Wrap(
            spacing: 8,
            children: [
              for (final theme in AppThemes.all)
                ChoiceChip(
                  label: Text(theme.name),
                  selected: theme.id == settings.themeId,
                  onSelected: (_) => settings.setTheme(theme.id),
                ),
            ],
          ),

          // ---------- Fuente ----------
          const _SectionTitle('Fuente'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final font in AppFonts.all)
                ChoiceChip(
                  label: Text(font.name, style: font.previewStyle()),
                  selected: font.id == settings.fontId,
                  onSelected: (_) => settings.setFont(font.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Las fuentes se descargan la primera vez que se usan, '
            'así que necesitan internet en ese momento.',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          // ---------- Barra de progreso ----------
          const _SectionTitle('Barra de progreso'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ProgressStyles.all)
                ChoiceChip(
                  label: Text(s.name),
                  selected: s.id == settings.progressStyleId,
                  onSelected: (_) => settings.setProgressStyle(s.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          IgnorePointer(
            // Vista previa: no se puede arrastrar.
            child: style.build(
              context,
              ProgressBarData(
                fraction: 0.6,
                enabled: true,
                spritePath: spritePath,
                onChanged: (_) {},
                onChangeEnd: (_) {},
              ),
            ),
          ),
          if (style.usesSprite) ...[
            const SizedBox(height: 8),
            Text(
              'Imagen en la punta de la barra (opcional). Usa un PNG o GIF, '
              'mejor con fondo transparente. Con un gato animado queda el '
              'estilo "nyan".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.image),
                  label: Text(
                    spritePath == null ? 'Elegir imagen' : 'Cambiar imagen',
                  ),
                  onPressed: () => _pickImage(context, settings.pickSprite),
                ),
                if (spritePath != null)
                  TextButton(
                    onPressed: settings.clearSprite,
                    child: const Text('Quitar'),
                  ),
              ],
            ),
          ],

          // ---------- Mascota ----------
          const _SectionTitle('Mascota'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar mascota'),
            subtitle: const Text(
              'Aparece abajo a la derecha, encima del reproductor. Es opcional.',
            ),
            value: settings.mascotEnabled && mascotPath != null,
            onChanged: mascotPath == null ? null : settings.setMascotEnabled,
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.pets),
                label: Text(
                  mascotPath == null
                      ? 'Elegir imagen (PNG o GIF)'
                      : 'Cambiar imagen',
                ),
                onPressed: () => _pickImage(context, settings.pickMascot),
              ),
              if (mascotPath != null)
                TextButton(
                  onPressed: settings.clearMascot,
                  child: const Text('Quitar'),
                ),
            ],
          ),
          if (mascotPath != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Tamaño'),
                Expanded(
                  child: Slider(
                    value: settings.mascotSize.clamp(48.0, 200.0).toDouble(),
                    min: 48,
                    max: 200,
                    divisions: 19,
                    label: '${settings.mascotSize.round()}',
                    onChanged: settings.setMascotSize,
                  ),
                ),
              ],
            ),
            Center(
              child: Image.file(
                File(mascotPath),
                height: 80,
                errorBuilder: (_, __, ___) => const Text('No se pudo mostrar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}