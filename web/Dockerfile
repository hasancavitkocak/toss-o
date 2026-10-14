# 1) Flutter web derlemesi
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src
COPY throw_app/pubspec.yaml throw_app/pubspec.lock ./
RUN flutter pub get
COPY throw_app/ ./
RUN flutter build web --release --dart-define=API_URL=/api

# 2) nginx: web uygulamasını sunar, /api isteklerini backend'e iletir
FROM nginx:1.27-alpine
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
