import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library.dart';
import '../models/library_view.dart';

/// Guarda lo que el usuario eligió para ver la biblioteca: búsqueda, filtros y orden.
/// El orden se recuerda entre sesiones; la búsqueda y los filtros, no.
class LibraryViewController extends ChangeNotifier {
  static const _kOrder = 'sort_order';
  static const _kAscending = 'sort_ascending';

  String _search = '';
  String? _artist;
  String? _genre;
  int? _year;
  SortOrder _order = SortOrder.title;
  bool _ascending = true;

  Object? _viewKey;
  LibraryView? _view;
  Library? _optionsLibrary;
  FilterOptions? _options;

  String get search => _search;
  String? get artist => _artist;
  String? get genre => _genre;
  int? get year => _year;
  SortOrder get order => _order;
  bool get ascending => _ascending;

  bool get hasSearch => _search.trim().isNotEmpty;
  bool get hasFilters => filterCount > 0;
  int get filterCount =>
      (_artist != null ? 1 : 0) + (_genre != null ? 1 : 0) + (_year != null ? 1 : 0);

  /// Lee el orden guardado.
  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _order = SortOrder.fromName(prefs.getString(_kOrder));
    _ascending = prefs.getBool(_kAscending) ?? _order.defaultAscending;
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOrder, _order.name);
    await prefs.setBool(_kAscending, _ascending);
  }

  void setSearch(String value) {
    if (value == _search) return;
    _search = value;
    notifyListeners();
  }

  void setArtist(String? value) {
    _artist = value;
    notifyListeners();
  }

  void setGenre(String? value) {
    _genre = value;
    notifyListeners();
  }

  void setYear(int? value) {
    _year = value;
    notifyListeners();
  }

  Future<void> setOrder(SortOrder order) async {
    if (order == _order) return;
    _order = order;
    _ascending = order.defaultAscending;
    notifyListeners();
    await _savePrefs();
  }

  Future<void> setAscending(bool value) async {
    if (value == _ascending) return;
    _ascending = value;
    notifyListeners();
    await _savePrefs();
  }

  void clearFilters() {
    _artist = null;
    _genre = null;
    _year = null;
    notifyListeners();
  }

  /// Quita la búsqueda y los filtros (el orden se conserva).
  void clearAll() {
    _search = '';
    _artist = null;
    _genre = null;
    _year = null;
    notifyListeners();
  }

  /// La biblioteca con la búsqueda, los filtros y el orden aplicados.
  /// Solo se recalcula si algo cambió.
  LibraryView viewOf(Library library) {
    final key = (library, _search, _artist, _genre, _year, _order, _ascending);
    final cached = _view;
    if (cached != null && _viewKey == key) return cached;

    final built = LibraryView.build(
      library,
      search: _search,
      artist: _artist,
      genre: _genre,
      year: _year,
      order: _order,
      ascending: _ascending,
    );
    _view = built;
    _viewKey = key;
    return built;
  }

  /// Valores disponibles para filtrar.
  FilterOptions optionsOf(Library library) {
    if (!identical(_optionsLibrary, library) || _options == null) {
      _options = FilterOptions.of(library);
      _optionsLibrary = library;
    }
    return _options!;
  }
}