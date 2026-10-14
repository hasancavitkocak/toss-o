// Türkçe ek ve biçim yardımcıları

String _lastVowel(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
    final c = s[i].toLowerCase();
    if ('aıouâ'.contains(c)) return 'a';
    if ('eiöüíé'.contains(c)) return 'e';
  }
  return 'e';
}

/// Elif'e, Can'a, Yuki'ye
String dative(String n) {
  final endsVowel = 'aeıioöuüíé'.contains(n[n.length - 1].toLowerCase());
  return "$n'${endsVowel ? 'y' : ''}${_lastVowel(n)}";
}

/// Elif'ten, Can'dan, Yuki'den
String ablative(String n) {
  final hard = 'fstkçşhp'.contains(n[n.length - 1].toLowerCase());
  return "$n'${hard ? 't' : 'd'}${_lastVowel(n)}n";
}

String km(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b km';
}

String ago(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'az önce';
  if (d.inHours < 1) return '${d.inMinutes} dk önce';
  if (d.inDays < 1) return '${d.inHours} sa önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return '${t.day}.${t.month}.${t.year}';
}
