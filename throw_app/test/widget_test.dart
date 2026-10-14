import 'package:flutter_test/flutter_test.dart';

import 'package:throw_app/engine3d.dart';
import 'package:throw_app/i18n.dart';
import 'package:throw_app/legal_texts.dart';
import 'package:throw_app/models.dart';
import 'package:throw_app/tr.dart';

void main() {
  test('Türkçe ekler ve biçimler', () {
    expect(dative('Elif'), "Elif'e");
    expect(dative('Can'), "Can'a");
    expect(dative('Yuki'), "Yuki'ye");
    expect(dative('Mateo'), "Mateo'ya");
    expect(ablative('Elif'), "Elif'ten");
    expect(ablative('Can'), "Can'dan");
    expect(km(1234.4), '1.234 km');
    final now = DateTime(2026, 1, 1, 12);
    expect(ago(now.subtract(const Duration(minutes: 5)), now), '5 dk önce');
    expect(ago(now.subtract(const Duration(seconds: 20)), now), 'az önce');
  });

  test('düz kağıt kameraya bakar, uçak burnu ileri', () {
    const paper = Pose(V3(0, 0, 4), pitch: -1.5707963);
    final top = paper.apply(const V3(0, 0, 1));
    expect(top.y, closeTo(1, 1e-6));
    expect(top.z, closeTo(4, 1e-6));
    const plane = Pose(V3(0, 0, 4));
    expect(plane.apply(const V3(0, 0, 1)).z, 5);
  });

  test('kağıt katlandıkça buruşur', () {
    const pose = Pose(V3(0, 0, 4), pitch: -1.5707963);
    double roughness(double fold, double crumple) {
      final m = buildMesh(pose, fold, crumple);
      final l = m.tris.map((t) => t.light).toList();
      final mean = l.reduce((a, b) => a + b) / l.length;
      return l.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    }

    expect(buildMesh(pose, 0, 0).tris.length, 4 * 16);
    expect(buildMesh(pose, 1, 0).tris.length, 4 * 16);
    expect(roughness(0, .05), greaterThan(roughness(0, .008)));
  });

  test('API yanıtları modele çevrilir', () {
    final l = Letter.fromJson({
      'id': 'a',
      'body': 'selam',
      'isRandom': true,
      'replyTo': null,
      'distanceKm': 330.4,
      'sentAt': '2026-10-13T10:00:00.000Z',
      'openedAt': null,
      'from': {
        'id': 'u1',
        'username': 'elif',
        'displayName': 'Elif',
        'city': 'İzmir',
        'lat': 38.4,
        'lng': 27.1,
      },
    });
    expect(l.unread, isTrue);
    expect(l.from!.name, 'Elif');
    expect(l.distanceKm, 330);
    expect(distanceKm(l.from!.at, l.from!.at), 0);
  });

  test('kişi kartı ve profil fotoğrafı ayrıştırılır', () {
    final p = UserProfile.fromJson({
      'id': 'u2',
      'username': 'can',
      'displayName': 'Can',
      'city': 'Ankara',
      'lat': 39.9,
      'lng': 32.8,
      'photo': '/users/u2/avatar?v=3',
      'relation': 'incoming',
      'requestId': 'r1',
      'friendsSince': null,
      'sent': 2,
      'received': 5,
      'blocked': false,
    });
    expect(p.relation, Relation.incoming);
    expect(p.requestId, 'r1');
    expect(p.user.photo, '/users/u2/avatar?v=3');
    expect(p.received, 5);
  });

  test('Türkçe / İngilizce metinler ve biçimler', () {
    language.value = Lang.tr;
    expect(txt.writeTo('Can'), "Can'a bir şeyler yaz...");
    expect(txt.planeComing('Elif'), "Elif'ten bir uçak geliyor…");
    expect(txt.km(12345), '12.345 km');
    language.value = Lang.en;
    expect(txt.writeTo('Can'), 'write something to Can...');
    expect(txt.planeComing('Elif'), 'a plane is coming from Elif…');
    expect(txt.km(12345), '12,345 km');
    final now = DateTime(2026, 1, 20, 12);
    expect(txt.ago(now.subtract(const Duration(minutes: 3)), now), '3 min ago');
    expect(txt.ago(DateTime(2025, 10, 4), now), 'Oct 4, 2025');
    language.value = Lang.tr;
  });

  test('KVKK metinleri iki dilde eksiksiz ve sürümlü', () {
    for (final d in LegalDoc.values) {
      for (final m in [legalTextsTr, legalTextsEn]) {
        expect(m[d]!.length, greaterThan(800));
        expect(m[d]!, contains(kLegalVersion));
      }
    }
    expect(legalTextsTr[LegalDoc.notice]!, contains('md. 11'));
  });
}
