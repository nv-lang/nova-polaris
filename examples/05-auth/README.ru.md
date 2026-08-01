# 05 — auth

Экстракторы Basic + Bearer/JWT, приватная зона под `require_jwt`, отделённая
от публичной через `nest` + `.use()`, эндпоинт `/login`, чеканящий
настоящий HS256-токен (`std.crypto.jwt.Jwt.encode_hs256` — сам Polaris
только ВЕРИФИЦИРУЕТ JWT, у него нет своего login-потока), и session-cookie
через `session`.

По мотивам: `jwt`-пример axum, туториал FastAPI OAuth2/security.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18086
```

```sh
curl http://localhost:18086/public                                   # public
curl -u alice:s3cret http://localhost:18086/basic                    # welcome, alice
curl -H 'Authorization: Bearer abc123' http://localhost:18086/bearer # token=abc123

curl -o /dev/null -w '%{http_code}\n' http://localhost:18086/private/me   # 401, нет токена

TOKEN=$(curl -s http://localhost:18086/login/nova-user)
curl -H "Authorization: Bearer $TOKEN" http://localhost:18086/private/me  # sub=nova-user

curl -c /tmp/jar -s http://localhost:18086/session/whoami   # session=sess-4000000000, Set-Cookie
curl -b /tmp/jar -s http://localhost:18086/session/whoami   # тот же id, без нового Set-Cookie
```

## Что покрутить

- Замени фиксированные часы `demo_now()` на настоящие и посмотри, что
  токены, отчеканенные до старта процесса, всё равно верифицируются (пока
  не истёк `exp`) — см. заметку в `main.nv` про то, почему часы — обычная
  замыкание, а не эффект `Time`.
- Добавь второй claim (`role`) в `mint_token`/`AuthClaims` и ветвись по нему
  внутри `/private/me`.
- Навесь `require_jwt` на ВЕРХНИЙ уровень вместо nest `/private` — посмотри,
  что станет с `/public` (подсказка: `.use()` оборачивает только маршруты,
  зарегистрированные ПОСЛЕ вызова — [`docs/middleware.ru.md`](../../docs/middleware.ru.md)).

## Связанная документация

- [`docs/auth.ru.md`](../../docs/auth.ru.md) — `Bearer`/`BasicAuth`/`JwtAuth`/`CookieJar`/сессии целиком
- [`docs/middleware.ru.md`](../../docs/middleware.ru.md) — взаимодействие `nest` + `.use()`

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
