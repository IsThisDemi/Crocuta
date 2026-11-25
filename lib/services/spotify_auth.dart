import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// L'accesso alla libreria Spotify di chi usa Crocuta.
///
/// Authorization Code con PKCE, senza segreto: Crocuta non ha un server e
/// non ha credenziali sue da distribuire (come la sincronizzazione, che
/// passa dal Drive di ciascuno). Chi importa si crea un'app gratuita su
/// developer.spotify.com e incolla qui il suo Client ID; il segreto di
/// quell'app non serve e non va mai chiesto.

/// Dove Spotify rimanda dopo il consenso.
///
/// Un IP di loopback esplicito: dal 2025 Spotify non accetta piu'
/// `localhost`, e vuole `http` solo per il loopback. Su quella porta non
/// ascolta niente: la pagina di accesso gira in una web view, che vede
/// l'indirizzo prima di caricarlo e prende il codice da li'. Niente server
/// locale, quindi niente permessi di rete in entrata da chiedere al sistema.
const spotifyRedirectUri = 'http://127.0.0.1:8888/callback';

/// Cosa si chiede: i brani piaciuti e i dischi salvati, le playlist
/// (anche private e collaborative), gli artisti seguiti. Solo lettura.
const spotifyScopes = [
  'user-library-read',
  'playlist-read-private',
  'playlist-read-collaborative',
  'user-follow-read',
];

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Il code_verifier di PKCE (RFC 7636 §4.1): 64 caratteri non riservati,
/// da un generatore crittografico.
String pkceVerifier([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 64; i++) _unreserved.codeUnitAt(r.nextInt(66)),
  ]);
}

/// Il code_challenge S256: SHA-256 del verifier in base64url senza `=`.
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Un valore casuale per `state`, contro le risposte che non abbiamo chiesto.
String randomState([Random? random]) => pkceVerifier(random).substring(0, 24);

/// L'indirizzo della pagina di consenso di Spotify.
Uri spotifyAuthorizeUrl({
  required String clientId,
  required String challenge,
  required String state,
  String redirectUri = spotifyRedirectUri,
  List<String> scopes = spotifyScopes,
}) => Uri.https('accounts.spotify.com', '/authorize', {
  'client_id': clientId,
  'response_type': 'code',
  'redirect_uri': redirectUri,
  'code_challenge_method': 'S256',
  'code_challenge': challenge,
  'state': state,
  'scope': scopes.join(' '),
});

/// Com'e' andato il ritorno da Spotify: un codice, o un errore da dire.
class SpotifyRedirect {
  final String? code;
  final String? error;

  const SpotifyRedirect._({this.code, this.error});
}

/// Legge l'indirizzo su cui Spotify ha rimandato.
///
/// Null se non e' il ritorno (la web view passa anche dalle pagine di
/// accesso, di Google, di Apple). Un `state` diverso da quello mandato e'
/// un errore: non e' la risposta alla nostra richiesta.
SpotifyRedirect? parseSpotifyRedirect(
  String url, {
  required String expectedState,
  String redirectUri = spotifyRedirectUri,
}) {
  final uri = Uri.tryParse(url.trim());
  final want = Uri.parse(redirectUri);
  if (uri == null ||
      uri.scheme != want.scheme ||
      uri.host != want.host ||
      uri.port != want.port ||
      uri.path != want.path) {
    return null;
  }
  final q = uri.queryParameters;
  if (q['state'] != expectedState) {
    return const SpotifyRedirect._(
      error: 'The answer from Spotify does not match this login. Try again.',
    );
  }
  if (q['error'] case final e?) {
    return SpotifyRedirect._(
      error: e == 'access_denied'
          ? 'Access was not allowed on Spotify.'
          : 'Spotify answered: $e',
    );
  }
  final code = q['code'];
  if (code == null || code.isEmpty) {
    return const SpotifyRedirect._(error: 'Spotify sent no code.');
  }
  return SpotifyRedirect._(code: code);
}

/// I token di accesso. Durano un'ora; il refresh token li rinnova senza
/// ripassare dalla pagina di consenso.
class SpotifyTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String scope;

  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.scope = '',
  });

  /// Scaduto, o sul punto di esserlo: un minuto di margine, perche' una
  /// pagina di una playlist lunga puo' partire valida e arrivare scaduta.
  bool isExpired(DateTime now) =>
      !now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  /// Dalla risposta dell'endpoint dei token. Rinnovando, Spotify puo' non
  /// mandare un refresh token nuovo: allora resta quello di prima.
  factory SpotifyTokens.fromResponse(
    Map<String, dynamic> j, {
    required DateTime now,
    String? previousRefresh,
  }) {
    final access = j['access_token'] as String?;
    final refresh = (j['refresh_token'] as String?) ?? previousRefresh;
    if (access == null || refresh == null) {
      throw const SpotifyAuthException('Spotify sent an incomplete answer.');
    }
    return SpotifyTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: now.add(
        Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600),
      ),
      scope: (j['scope'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expires': expiresAt.millisecondsSinceEpoch,
    'scope': scope,
  };

  factory SpotifyTokens.fromJson(Map<String, dynamic> j) => SpotifyTokens(
    accessToken: j['access'] as String,
    refreshToken: j['refresh'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(j['expires'] as int),
    scope: (j['scope'] as String?) ?? '',
  );
}

class SpotifyAuthException implements Exception {
  final String message;

  /// Il refresh token non vale piu' (revocato, app cancellata): serve
  /// ricollegarsi, riprovare non basta.
  final bool needsLogin;

  const SpotifyAuthException(this.message, {this.needsLogin = false});

  @override
  String toString() => message;
}

/// Le due chiamate all'endpoint dei token, senza segreto.
class SpotifyAuth {
  final http.Client client;
  final String clientId;
  final DateTime Function() now;

  SpotifyAuth({
    required this.client,
    required this.clientId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  static final _tokenUrl = Uri.https('accounts.spotify.com', '/api/token');

  Future<SpotifyTokens> exchangeCode(
    String code,
    String verifier, {
    String redirectUri = spotifyRedirectUri,
  }) => _post({
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': redirectUri,
    'client_id': clientId,
    'code_verifier': verifier,
  });

  Future<SpotifyTokens> refresh(SpotifyTokens old) => _post({
    'grant_type': 'refresh_token',
    'refresh_token': old.refreshToken,
    'client_id': clientId,
  }, previousRefresh: old.refreshToken);

  Future<SpotifyTokens> _post(
    Map<String, String> body, {
    String? previousRefresh,
  }) async {
    final resp = await client.post(
      _tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }
    if (resp.statusCode != 200) {
      final err = json['error'] as String?;
      final desc = json['error_description'] as String?;
      // invalid_grant: codice o refresh token non piu' validi.
      // invalid_client: Client ID sbagliato o app cancellata.
      throw SpotifyAuthException(switch (err) {
        'invalid_client' =>
          'Spotify does not know this Client ID. Check it on '
              'developer.spotify.com.',
        'invalid_grant' => 'The Spotify login expired. Connect again.',
        _ => 'Spotify login failed (${desc ?? err ?? resp.statusCode}).',
      }, needsLogin: err == 'invalid_grant' || err == 'invalid_client');
    }
    return SpotifyTokens.fromResponse(
      json,
      now: now(),
      previousRefresh: previousRefresh,
    );
  }
}

/// I token di una sessione, rinnovati quando scadono.
///
/// Un rinnovo alla volta: due richieste parallele che trovano il token
/// scaduto devono aspettare lo stesso rinnovo, non farne due — il secondo
/// potrebbe usare un refresh token che il primo ha appena sostituito.
class SpotifySession {
  final SpotifyAuth auth;
  final Future<void> Function(SpotifyTokens tokens) onTokens;
  SpotifyTokens _tokens;
  Future<SpotifyTokens>? _refreshing;

  SpotifySession({
    required this.auth,
    required SpotifyTokens tokens,
    required this.onTokens,
  }) : _tokens = tokens;

  SpotifyTokens get tokens => _tokens;

  /// Un token valido. Con [force] si rinnova comunque: per un 401 arrivato
  /// con un token che per l'orologio era ancora buono.
  Future<String> accessToken({bool force = false}) async {
    if (!force && !_tokens.isExpired(auth.now())) return _tokens.accessToken;
    final pending = _refreshing ??= _refresh();
    try {
      return (await pending).accessToken;
    } finally {
      if (identical(_refreshing, pending)) _refreshing = null;
    }
  }

  Future<SpotifyTokens> _refresh() async {
    final fresh = await auth.refresh(_tokens);
    _tokens = fresh;
    await onTokens(fresh);
    return fresh;
  }
}
