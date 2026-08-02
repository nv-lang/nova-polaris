# 12 — https

TLS-терминация перед `Router`: та же форма `Router.new()` + один `.get()`,
что в [`01-hello`](../01-hello/), но вместо `serve_router` —
`polaris.serve.serve_tls`: самоподписанный `localhost`-серт, один
hello-роут, всё поверх HTTPS.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18093
```

```sh
curl -k https://localhost:18093/
# hello, world -- over HTTPS
```

`-k`/`--insecure` обязателен — `certs/localhost_cert.pem` самоподписан,
**только для тестов** (см. [`certs/README.md`](certs/README.md)), у curl
нет CA, чтобы его проверить. Обычный (не-TLS) запрос на тот же порт роняет
handshake — соединение закрывается + серверная сторона пишет `warn`-строку
в лог; попробуй `curl http://localhost:18093/` (без `-s` — так видна
собственная ошибка curl про TLS) и посмотри сам.

## Что покрутить

- Наведи `curl`/браузер на `https://localhost:18093/` и посмотри серт —
  `CN=localhost`, самоподписан, живёт 100 лет (не протухнет посреди демо).
- Замени `certs/localhost_cert.pem`/`certs/localhost_key.pem` на свою пару
  (рецепт `openssl` — в `certs/README.md`) и увидь, как тот же сервер
  предъявляет другую личность.
- Добавь второй маршрут так же, как в `01-hello` — `serve_tls` маршрутизирует
  через ТОТ ЖЕ тип `Router`, что и остальные примеры: TLS — забота
  транспортного слоя под ним, не роутинга.

## Почему `main()` этого примера отличается от остальных

Каждый другой пример вызывает `polaris.serve.serve_router(listener, app,
ServerPolicy.new())` (`../README.ru.md#почему-у-каждого-main-одна-и-та-же-форма`)
— полный accept-цикл с keep-alive/`ServerPolicy`. Этот пример вызывает
`polaris.serve.serve_tls(addr, tls_cfg, app)`: TLS-рукопожатие на КАЖДОМ
принятом соединении ДО того, как оно доходит до роутера, но — сознательно,
пока — один запрос на соединение (`Connection: close`), без
admission/keep-alive ручек `ServerPolicy`. Полное обоснование — в
докстроке самого `serve_tls` (`../../src/serve/serve_tls.nv`): расширение
до keep-alive+`ServerPolicy`-паритета с обычным путём — задел на будущее,
здесь не сделано.

## Связанная документация

- [`docs/overview.md`](../../docs/overview.md) — тот же сервер без TLS,
  разобран
- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, accept-цикл,
  который `serve_tls` сознательно пока не использует
- [README nova-tls](https://github.com/nv-lang/nova-tls#readme) —
  `TlsStream`/`ServerConfig`, на которых стоит зависимость этого примера
- `nova/examples/tls/echo_server.nv` — та же зависимость nova-tls голышом
  (без HTTP/`Router` сверху), минимально возможный TLS-сервер

[English](README.md)
