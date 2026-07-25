# 02 — routing

Шаблоны путей `{name}`/`{*rest}`, `MethodRouter` (`get(h).post(h2)` на одном
пути), `nest`, глобальный 404 против per-route 405 и конфликт маршрутов,
пойманный как типизированный `Err` при старте, а не паника.

По мотивам: `routes-and-handlers-close-together` из axum, роутинг chi.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18083
```

```sh
curl http://localhost:18083/users/42                # user 42
curl http://localhost:18083/files/a/b/c             # path=a/b/c  (catch-all {*rest})
curl http://localhost:18083/widgets                 # list           (MethodRouter GET)
curl -X POST http://localhost:18083/widgets         # created        (MethodRouter POST)
curl -X DELETE http://localhost:18083/widgets       # 405 + Allow: GET, POST
curl http://localhost:18083/api/widgets/9           # widget 9       (nested под /api)
curl -X DELETE http://localhost:18083/api/guarded   # custom 405: guarded
curl http://localhost:18083/missing                 # custom 404: nothing here
```

В логе старта также печатается результат повторной регистрации `/widgets` —
типизированный `Err`, никогда не крэш.

## Что покрутить

- Добавь третий catch-all `{*deep}` под другим префиксом и посмотри на
  правило структурного приоритета (литерал > `{name}` > `{*name}`) — оно
  выбирает верный маршрут независимо от порядка регистрации.
- Зарегистрируй один путь дважды с ДВУМЯ разными именами `{name}`
  (`{id}` против `{slug}`) — тоже конфликт, ловится так же.

## Связанная документация

- [`docs/routing.ru.md`](../../docs/routing.ru.md) — вся страница, из которой пример
- [`docs/handlers-response.ru.md`](../../docs/handlers-response.ru.md) — `Handler`, `req.param`

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
