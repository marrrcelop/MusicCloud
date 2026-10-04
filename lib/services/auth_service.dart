import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static const _scopes = ['https://www.googleapis.com/auth/drive.readonly'];

  // Pega aquí el ID de cliente de tipo "Aplicación web"
  static const _serverClientId = '970424544525-e1v130ejth35a5kfe7ujiitdo14m935v.apps.googleusercontent.com';

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _user;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _signIn.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  /// Intenta entrar sin pedir nada al usuario (si ya inició sesión antes).
  Future<bool> trySilentSignIn() async {
    await _init();
    _user = await _signIn.attemptLightweightAuthentication();
    return _user != null;
  }

  /// Abre el selector de cuentas de Google.
  Future<void> signIn() async {
    await _init();
    _user = await _signIn.authenticate(scopeHint: _scopes);
  }

 /// Devuelve las cabeceras con el token que Drive exige en cada petición.
  /// Con forceRefresh descarta el token guardado y pide uno nuevo.
  Future<Map<String, String>?> getHeaders({
    bool interactive = false,
    bool forceRefresh = false,
  }) async {
    final user = _user;
    if (user == null) return null;

    final client = user.authorizationClient;

    if (forceRefresh) {
      final current = await client.authorizationForScopes(_scopes);
      if (current != null) {
        await client.clearAuthorizationToken(accessToken: current.accessToken);
      }
    }

    var headers = await client.authorizationHeaders(_scopes);
    if (headers == null && interactive) {
      await client.authorizeScopes(_scopes);
      headers = await client.authorizationHeaders(_scopes);
    }
    return headers;
  }

  bool get isSignedIn => _user != null;

  Future<void> signOut() async {
    await _signIn.signOut();
    _user = null;
  }
}