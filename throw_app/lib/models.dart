import 'dart:math' as math;
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

class Person {
  /// [city] il / bölge adı, [place] o ildeki yerleşim (ilçe, kasaba)
  final String id, username, name, city;
  final String? place, country, countryName;

  /// Yüklenmiş profil fotoğrafının API'ye göre yolu; yoksa baş harf
  final String? photo;
  final LatLng at;
  final bool random;
  const Person({
    required this.id,
    required this.username,
    required this.name,
    required this.city,
    required this.at,
    this.place,
    this.country,
    this.countryName,
    this.photo,
    this.random = false,
  });

  /// "Esenyurt, İstanbul" — yerleşim ile il aynıysa sadece il
  String get location =>
      place == null || place == city ? city : '$place, $city';

  /// Üstteki kişi seçicideki "Rastgele" kartı
  static const randomPick = Person(
      id: 'random',
      username: '',
      name: 'Rastgele',
      city: "Türkiye'den biri",
      at: LatLng(0, 0),
      random: true);

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        username: j['username'] as String,
        name: j['displayName'] as String,
        city: j['city'] as String,
        place: j['place'] as String?,
        country: j['country'] as String?,
        countryName: j['countryName'] as String?,
        photo: j['photo'] as String?,
        at: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );

  @override
  bool operator ==(Object other) => other is Person && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Letter {
  final String id, body;
  final Person? from, to;
  final bool isRandom;
  final String? replyTo;
  final int distanceKm;
  final DateTime sentAt;

  /// Uçağın alıcıya varacağı (ya da vardığı) an
  final DateTime deliverAt;
  final DateTime? openedAt;
  const Letter({
    required this.id,
    required this.body,
    this.from,
    this.to,
    required this.isRandom,
    this.replyTo,
    required this.distanceKm,
    required this.sentAt,
    DateTime? deliverAt,
    this.openedAt,
  }) : deliverAt = deliverAt ?? sentAt;

  bool get unread => openedAt == null;

  /// Gönderilen mektup hâlâ havada mı
  bool get inFlight => deliverAt.isAfter(DateTime.now());

  factory Letter.fromJson(Map<String, dynamic> j) => Letter(
        id: j['id'] as String,
        body: j['body'] as String,
        from: j['from'] == null ? null : Person.fromJson(j['from']),
        to: j['to'] == null ? null : Person.fromJson(j['to']),
        isRandom: j['isRandom'] as bool? ?? false,
        replyTo: j['replyTo'] as String?,
        distanceKm: (j['distanceKm'] as num).round(),
        sentAt: DateTime.parse(j['sentAt'] as String).toLocal(),
        deliverAt: j['deliverAt'] == null
            ? null
            : DateTime.parse(j['deliverAt'] as String).toLocal(),
        openedAt: j['openedAt'] == null
            ? null
            : DateTime.parse(j['openedAt'] as String).toLocal(),
      );
}

class Stats {
  final int sent, received, unread, cities, requests;
  const Stats(
      {this.sent = 0,
      this.received = 0,
      this.unread = 0,
      this.cities = 0,
      this.requests = 0});
  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        sent: j['sent'] as int,
        received: j['received'] as int,
        unread: j['unread'] as int,
        cities: j['cities'] as int,
        requests: j['requests'] as int? ?? 0,
      );
}

/// Mektup hakları: günlük ücretsiz hak + satın alınmış (süresiz) haklar
class Credits {
  final int dailyLeft, bonus;
  final DateTime? resetsAt;

  /// Satılan paketler: ürün kimliği -> hak sayısı
  final Map<String, int> products;

  /// Geliştirme sunucusu ödeme yapmadan hak eklemeye izin veriyor mu
  final bool testPurchases;
  const Credits(
      {this.dailyLeft = 1,
      this.bonus = 0,
      this.resetsAt,
      this.products = const {},
      this.testPurchases = false});

  int get total => dailyLeft + bonus;

  factory Credits.fromJson(Map<String, dynamic> j) => Credits(
        dailyLeft: j['dailyLeft'] as int? ?? 0,
        bonus: j['bonus'] as int? ?? 0,
        resetsAt: j['resetsAt'] == null
            ? null
            : DateTime.parse(j['resetsAt'] as String).toLocal(),
        products: {
          for (final p in j['products'] as List? ?? const [])
            (p as Map)['id'] as String: p['credits'] as int
        },
        testPurchases: j['testPurchases'] as bool? ?? false,
      );
}

/// Kendi hesabının özel ayarları: dil ve KVKK onay kayıtları
class Settings {
  final String lang;
  final String? legalVersion, currentLegalVersion;
  const Settings(
      {this.lang = 'tr', this.legalVersion, this.currentLegalVersion});

  /// Yasal metinler güncellendiyse yeniden onay gerekir
  bool get needsLegal =>
      currentLegalVersion != null && legalVersion != currentLegalVersion;

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        lang: j['lang'] as String? ?? 'tr',
        legalVersion: j['legalVersion'] as String?,
        currentLegalVersion: j['currentLegalVersion'] as String?,
      );
}

/// Aramada kişiyle ilişki: arkadaş, bana istek atmış, ben istek atmışım, yok
enum Relation { friend, incoming, outgoing, none }

class FriendRequest {
  final String id;
  final Person user;
  final DateTime createdAt;
  const FriendRequest(this.id, this.user, this.createdAt);
  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
      j['id'] as String,
      Person.fromJson(j['user'] as Map<String, dynamic>),
      DateTime.parse(j['createdAt'] as String).toLocal());
}

class SearchResult {
  final Person user;
  final Relation relation;
  final String? requestId;
  const SearchResult(this.user, this.relation, this.requestId);
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        Person.fromJson(j),
        Relation.values.byName(j['relation'] as String),
        j['requestId'] as String?,
      );
}

/// Kişiye dokununca açılan profil kartının verisi
class UserProfile {
  final Person user;
  final Relation relation;
  final String? requestId;
  final DateTime? friendsSince;
  final int sent, received;
  final bool blocked;
  const UserProfile(
      {required this.user,
      required this.relation,
      this.requestId,
      this.friendsSince,
      this.sent = 0,
      this.received = 0,
      this.blocked = false});
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        user: Person.fromJson(j),
        relation: Relation.values.byName(j['relation'] as String),
        requestId: j['requestId'] as String?,
        friendsSince: j['friendsSince'] == null
            ? null
            : DateTime.parse(j['friendsSince'] as String).toLocal(),
        sent: j['sent'] as int? ?? 0,
        received: j['received'] as int? ?? 0,
        blocked: j['blocked'] as bool? ?? false,
      );
}

/// Ülke ya da il / bölge seçeneği
class GeoOption {
  final String code, name;
  const GeoOption(this.code, this.name);
  factory GeoOption.fromJson(Map<String, dynamic> j) =>
      GeoOption(j['code'] as String, j['name'] as String);
}

// ---------- coğrafya ----------

double _rad(double d) => d * math.pi / 180;

double distanceKm(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLon / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(h));
}

double bearingDeg(LatLng a, LatLng b) {
  final y =
      math.sin(_rad(b.longitude - a.longitude)) * math.cos(_rad(b.latitude));
  final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.cos(_rad(b.longitude - a.longitude));
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
