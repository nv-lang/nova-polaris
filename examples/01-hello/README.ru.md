# 01 — hello

Минимально возможный сервер на Polaris: `Router.new()`, один `.get()`, serve.
Десять строк до рабочего HTTP-эндпоинта.

По мотивам: собственный `hello-world` из axum, `app.get('/', ...)` из Express.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18082
```

```sh
curl http://localhost:18082/hello/nova
# hello, nova
curl http://localhost:18082/
# hello, world -- try GET /hello/{name}
```

## Что покрутить

- Добавь второй `{lang}`-сегмент в путь (`/hello/{name}/{lang}`) в
  `build_router()` и прочитай оба через `req.param(...)`.
- Добавь второй маршрут, возвращающий безтельный `StatusCode.OK.into_response()`
  или просто `str` — см. `IntoResponse` в доке ниже.

## Заметка про форму `main()`

`main()` — тот самый канонический вид, которому учат
[`docs/serving.md`](../../docs/serving.ru.md)/
[`docs/overview.md`](../../docs/overview.ru.md#минимальный-сервер): bind, затем
один вызов `serve_router(listener, app, ServerPolicy.new())` — полный
accept-цикл с keep-alive, дедлайнами, лимитами тела и admission control, всё
из `ServerPolicy`. Без обёртки `supervised { spawn { ... } }` вокруг него:
тело `main` само уже исполняется как файбер, так что блокирующий вызов
`serve_router` работает прямо здесь. Та же однофункциональная форма — в
каждом примере набора; общее объяснение — в
[`examples/README.ru.md`](../README.ru.md).

## Связанная документация

- [`docs/overview.ru.md`](../../docs/overview.ru.md) — этот же сервер, разобран
- [`docs/routing.ru.md`](../../docs/routing.ru.md) — `Router`, шаблоны путей
- [`docs/serving.ru.md`](../../docs/serving.ru.md) — `ServerPolicy`, accept-цикл

[English](README.md)
