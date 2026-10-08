import 'package:flutter/material.dart';
import 'settings_controller.dart';

/// Pone los ajustes al alcance de cualquier pantalla:
///   final settings = SettingsScope.of(context);
/// Quien lo use se redibuja solo cuando cambia un ajuste.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'Falta un SettingsScope en la parte alta del árbol');
    return scope!.notifier!;
  }
}