import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'home.dart';
import 'i18n.dart';
import 'login.dart';
import 'models.dart';
import 'widgets.dart';

void main() {
  // Uygulamaya gömülü yazı tiplerinin lisansları (SIL Open Font License)
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Inter', 'Caveat']) {
      yield LicenseEntryWithLineBreaks(
          [f], await rootBundle.loadString('assets/fonts/$f-OFL.txt'));
    }
  });
  // Web'de harita kütüphanesi (MapLibre GL JS) CDN'den değil sitenin
  // kendisinden yüklenir: ziyaretçinin IP adresi üçüncü tarafa gitmez
  if (kIsWeb) {
    MapLibreMap.webLibrarySource = MapLibreJsSource.urls(
      scriptUrl: Uri.base.resolve('maplibre/maplibre-gl.mjs').toString(),
      styleUrl: Uri.base.resolve('maplibre/maplibre-gl.css').toString(),
    );
  }
  runApp(const TossApp());
}

class TossApp extends StatefulWidget {
  const TossApp({super.key});
  @override
  State<TossApp> createState() => _TossAppState();
}

class _TossAppState extends State<TossApp> {
  static const _tokenKey = 'tosso_token';
  final api = Api();
  Person? me;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Kayıtlı oturum varsa sunucudan doğrulayıp devam et
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      api.token = token;
      try {
        final (user, _) = await api.me();
        me = user;
      } on ApiException catch (e) {
        if (e.status == 401) await prefs.remove(_tokenKey);
        api.token = e.status == 401 ? null : token;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _onSession(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, s.token);
    setState(() => me = s.user);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    api.token = null;
    setState(() => me = null);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Lang>(
      valueListenable: language,
      builder: (context, lang, _) => MaterialApp(
            title: 'toss-o',
            locale: Locale(lang.name),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: kNavy, primary: kNavy, secondary: kRed),
              scaffoldBackgroundColor: Colors.white,
            ),
            // Geniş ekranda (tarayıcı) uygulamayı telefon çerçevesinde göster
            builder: (context, child) => LayoutBuilder(builder: (ctx, c) {
              if (c.maxWidth < 600) return child!;
              final h = math.min(c.maxHeight - 32, 900.0);
              final w = h * .47;
              return ColoredBox(
                color: const Color(0xFFE9ECF2),
                child: Center(
                  child: Container(
                    width: w,
                    height: h,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(38),
                        boxShadow: const [
                          BoxShadow(color: Color(0x400E1B33), blurRadius: 40)
                        ]),
                    child: MediaQuery(
                      data: MediaQuery.of(ctx).copyWith(
                          size: Size(w, h),
                          padding: const EdgeInsets.only(top: 18, bottom: 8)),
                      child: child!,
                    ),
                  ),
                ),
              );
            }),
            home: loading
                ? const Scaffold(body: Center(child: Logo(height: 110)))
                : me == null
                    ? LoginScreen(api: api, onSession: _onSession)
                    : HomeScreen(
                        key: ValueKey(me!.id),
                        api: api,
                        me: me!,
                        onLogout: _logout),
          ));
}
