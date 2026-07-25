# 04 — middleware

Свой `middleware(fn(req, next))`, композиция `@then`, порядок layers (первый
`.layer()` — самый внешний), взаимодействие `nest` + `.layer()`, и две
батарейки (`log`, `ratelimit`).

По мотивам: tower-middleware showcase из axum, цепочка middleware Express.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18085
```

```sh
curl -D - http://localhost:18085/x | grep -i x-order
# x-order: A,B                      -- .layer(A); .layer(B) -> порядок запроса A -> B -> handler

curl -D - http://localhost:18085/composed/y | grep -i x-order
# x-order: A,B,C,D                  -- вложенный роутер: A,B родителя оборачивают СНАРУЖИ собственный C.then(D) под-роутера

curl -o /dev/null -w '%{http_code}\n' http://localhost:18085/rl/limited   # 200 (burst 1/2)
curl -o /dev/null -w '%{http_code}\n' http://localhost:18085/rl/limited   # 200 (burst 2/2)
curl -D - http://localhost:18085/rl/limited | grep -iE 'HTTP|retry-after'
# HTTP/1.1 429 Too Many Requests
# retry-after: 1
```

Каждый запрос также печатает одну строку `log` в stdout (метод, путь,
статус, размер тела, длительность).

## Что покрутить

- Добавь третий `.layer()` и посмотри, как растёт заголовок `x-order`.
- Замени `tag_layer("A").then(tag_layer("B"))` на два отдельных вызова
  `.layer()` — тот же итоговый порядок, см.
  [`docs/middleware.ru.md`](../../docs/middleware.ru.md#then-композиция-двух-middleware).
- Добавь свой middleware, который обрывает цепочку (возвращает ответ, не
  вызывая `next` вообще) — например, проверку API-ключа.

## Связанная документация

- [`docs/middleware.ru.md`](../../docs/middleware.ru.md) — канон-форма `middleware(...)`, `@then`, `nest`+`.layer()`
- [`docs/batteries.ru.md`](../../docs/batteries.ru.md) — `log`, `ratelimit`, плюс `cors`/`compress`

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
