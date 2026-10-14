# 1) Flutter web derlemesi
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src
COPY throw_app/pubspec.yaml throw_app/pubspec.lock ./
RUN flutter pub get
COPY throw_app/ ./
# Harita, nginx'teki /map/ vekilinden gelir (ziyaretçi IP'si dışarı gitmez).
# --no-web-resources-cdn: Flutter'ın çizim motoru Google CDN yerine siteden yüklenir.
ARG MAP_STYLE=/map/styles/liberty
RUN flutter build web --release --no-web-resources-cdn     --dart-define=API_URL=/api --dart-define=MAP_STYLE=$MAP_STYLE

# 2) nginx: web uygulamasını sunar, /api isteklerini backend'e iletir
FROM nginx:1.27-alpine
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
