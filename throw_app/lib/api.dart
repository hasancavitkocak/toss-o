import 'dart:convert';
import 'dart:typed_data';
import 'i18n.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Session {
  final String token;
  final Person user;
  const Session(this.token, this.user);
}

/// toss-o backend istemcisi.
/// Adres: --dart-define=API_URL=... ; verilmezse web'de aynı sunucunun
/// /api yolu, mobilde http://localhost:8080/api (adb reverse ile).
class Api {
  Api({String? base}) : base = base ?? defaultBase() {
    root = this.base;
  }
  final String base;

  /// Profil fotoğrafı gibi göreli adresler için son kullanılan API kökü
  static String root = defaultBase();
  String? token;

  /// Son alınan hesap ayarları (dil, KVKK onayları)
  Settings settings = const Settings();
  final _client = http.Client();

  static String defaultBase() {
    const env = String.fromEnvironment('API_URL');
    if (env.isNotEmpty) {
      return env.startsWith('/') && kIsWeb ? '${Uri.base.origin}$env' : env;
    }
    return kIsWeb ? '${Uri.base.origin}/api' : 'http://localhost:8080/api';
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$base$path'));
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    req.headers['accept-language'] = txt.code;
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.StreamedResponse res;
    final String text;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 12));
      text = await res.stream.bytesToString();
    } catch (_) {
      throw ApiException(txt.serverUnreachable);
    }
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final msg = data is Map ? data['error'] as String? : null;
      throw ApiException(msg ?? txt.unexpectedError, res.statusCode);
    }
    return data;
  }

  Session _session(dynamic j) {
    token = j['token'] as String;
    _settings(j);
    return Session(token!, Person.fromJson(j['user']));
  }

  Future<Session> login(String username, String password) async =>
      _session(await _send(
          'POST', '/auth/login', {'username': username, 'password': password}));

  Future<Session> register(
          {required String username,
          required String password,
          required String displayName,
          required String country,
          required String region,
          required String lang,
          required bool acceptTerms,
          required bool acceptNotice}) async =>
      _session(await _send('POST', '/auth/register', {
        'username': username,
        'password': password,
        'displayName': displayName,
        'country': country,
        'region': region,
        'lang': lang,
        'acceptTerms': acceptTerms,
        'acceptNotice': acceptNotice,
      }));

  void _settings(dynamic j) {
    if (j is Map && j['settings'] is Map) {
      settings = Settings.fromJson(j['settings'] as Map<String, dynamic>);
    }
  }

  /// İsim, dil ya da güncel yasal metin onayı
  Future<Person> updateMe(
      {String? displayName, String? lang, bool acceptLegal = false}) async {
    final j = await _send('PATCH', '/me', {
      if (displayName != null) 'displayName': displayName,
      if (lang != null) 'lang': lang,
      if (acceptLegal) 'acceptLegal': true,
    });
    _settings(j);
    return Person.fromJson(j['user'] as Map<String, dynamic>);
  }

  /// İl değiştir: sunucu yeni ilde rastgele bir nokta seçer
  Future<Person> updateLocation(String country, String region) async =>
      Person.fromJson(await _send(
          'PUT', '/me/location', {'country': country, 'region': region}));

  Future<Person> updateName(String displayName) =>
      updateMe(displayName: displayName);

  Future<void> changePassword(String current, String next) =>
      _send('PUT', '/me/password', {'current': current, 'next': next});

  /// Hesabı ve tüm verilerini kalıcı olarak siler
  Future<void> deleteAccount(String password) =>
      _send('DELETE', '/me', {'password': password});

  /// Profil fotoğrafı yükle (JPG / PNG / WEBP)
  Future<Person> uploadPhoto(Uint8List bytes) async => Person.fromJson(
      await _send('PUT', '/me/avatar', {'image': base64Encode(bytes)}));

  Future<Person> deletePhoto() async =>
      Person.fromJson(await _send('DELETE', '/me/avatar'));

  /// Bir kişinin profil kartı (ilişki ve aradaki mektup sayıları)
  Future<UserProfile> user(String id) async =>
      UserProfile.fromJson(await _send('GET', '/users/$id'));

  Future<void> unfriend(String id) => _send('DELETE', '/friends/$id');

  Future<void> block(String id) => _send('POST', '/users/$id/block');

  Future<void> unblock(String id) => _send('DELETE', '/users/$id/block');

  Future<List<Person>> blocks() async => [
        for (final p in await _send('GET', '/blocks') as List)
          Person.fromJson(p as Map<String, dynamic>)
      ];

  Future<(Person, Stats)> me() async {
    final j = await _send('GET', '/me');
    _settings(j);
    return (Person.fromJson(j['user']), Stats.fromJson(j['stats']));
  }

  Future<List<GeoOption>> countries() async => [
        for (final c in await _send('GET', '/geo/countries') as List)
          GeoOption.fromJson(c as Map<String, dynamic>)
      ];

  Future<List<GeoOption>> regions(String country) async => [
        for (final c
            in await _send('GET', '/geo/countries/$country/regions') as List)
          GeoOption.fromJson(c as Map<String, dynamic>)
      ];

  Future<List<Person>> friends() async => [
        for (final p in await _send('GET', '/friends') as List)
          Person.fromJson(p as Map<String, dynamic>)
      ];

  Future<List<SearchResult>> search(String q) async => [
        for (final p in await _send(
            'GET', '/users/search?q=${Uri.encodeQueryComponent(q)}') as List)
          SearchResult.fromJson(p as Map<String, dynamic>)
      ];

  Future<({List<FriendRequest> incoming, List<FriendRequest> outgoing})>
      requests() async {
    final j = await _send('GET', '/friends/requests');
    List<FriendRequest> list(String k) => [
          for (final r in j[k] as List)
            FriendRequest.fromJson(r as Map<String, dynamic>)
        ];
    return (incoming: list('incoming'), outgoing: list('outgoing'));
  }

  /// Arkadaşlık isteği gönder. Karşı taraf da istek atmışsa doğrudan
  /// arkadaş olunur: dönen değer 'accepted', yoksa 'pending'.
  Future<String> sendRequest(String username) async => (await _send(
      'POST', '/friends/requests', {'username': username}))['status'] as String;

  Future<Person> acceptRequest(String id) async =>
      Person.fromJson(await _send('POST', '/friends/requests/$id/accept'));

  Future<void> declineRequest(String id) =>
      _send('POST', '/friends/requests/$id/decline');

  Future<void> cancelRequest(String id) =>
      _send('DELETE', '/friends/requests/$id');

  /// [to] kişi id'si ya da 'random'
  Future<Letter> send(
          {required String to, required String body, String? replyTo}) async =>
      Letter.fromJson(await _send('POST', '/letters', {
        'to': to,
        'body': body,
        if (replyTo != null) 'replyTo': replyTo,
      }));

  Future<List<Letter>> inbox() async => [
        for (final l in await _send('GET', '/letters/inbox') as List)
          Letter.fromJson(l as Map<String, dynamic>)
      ];

  Future<List<Letter>> sent() async => [
        for (final l in await _send('GET', '/letters/sent') as List)
          Letter.fromJson(l as Map<String, dynamic>)
      ];

  Future<void> open(String letterId) =>
      _send('POST', '/letters/$letterId/open');
}
