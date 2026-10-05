import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  bool _isOnline(List<ConnectivityResult> results) =>
      !results.contains(ConnectivityResult.none);

  Future<bool> checkOnline() async =>
      _isOnline(await _connectivity.checkConnectivity());

  /// Emite true o false, y solo cuando el estado realmente cambia.
  Stream<bool> get onlineStream =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();
}