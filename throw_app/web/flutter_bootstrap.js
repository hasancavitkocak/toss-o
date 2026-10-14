{{flutter_js}}
{{flutter_build_config}}

// Emoji gibi eksik karakterler için yedek yazı tipleri: yayında nginx bu yer
// tutucuyu kendi /gfonts/ vekilimizle değiştirir, böylece ziyaretçinin IP
// adresi Google'a gitmez. Yerel geliştirmede (nginx yokken) varsayılan kullanılır.
const fontFallback = '__TOSSO_FONT_FALLBACK__';
_flutter.loader.load({
  config: fontFallback.startsWith('/') ? { fontFallbackBaseUrl: fontFallback } : {},
});
