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

`main()` сама крутит цикл `TcpListener.accept()` через низкоуровневый
`handle_connection_router` (один запрос на соединение, без keep-alive)
внутри блока `supervised { spawn { ... } }` — accept прямо на
bootstrap-файбере паркуется невалидно (`nova_sched_park: invalid
scope/slot`), так что циклу accept всегда нужен свой спавненный файбер.
`production_main()` (компилируется, не вызывается) показывает
*канонический* вид из [`docs/serving.md`](../../docs/serving.md) —
`serve_router` + `ServerPolicy` (keep-alive, дедлайны, admission control),
который на этом снимке тулчейна не линкуется
(`undefined symbol: nova_fn_hook`, локализовано до hook'а recover-500,
а не до чего-либо в этом примере или в коде роутинга/хендлеров Polaris).
Та же двухфункциональная форма — в каждом примере набора; общее объяснение —
в [`examples/README.ru.md`](../README.ru.md).

## Связанная документация

- [`docs/overview.ru.md`](../../docs/overview.ru.md) — этот же сервер, разобран
- [`docs/routing.ru.md`](../../docs/routing.ru.md) — `Router`, шаблоны путей
- [`docs/serving.ru.md`](../../docs/serving.ru.md) — `ServerPolicy`, accept-цикл

[English](README.md)
