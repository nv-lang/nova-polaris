# 03 — json-api

REST CRUD над списком todo в памяти: типизированный `Json[T]` на входе,
`ServerResponse.json`/blanket `Serialize` на выходе, `#impl(Serialize +
Deserialize)` на доменном типе, `HttpError`/`StatusCode` для веток
not-found/bad-input.

По мотивам: `todos`-пример axum, CRUD над items из туториала FastAPI.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18084
```

```sh
curl http://localhost:18084/todos
# []
curl -X POST -H 'Content-Type: application/json' -d '{"title":"buy milk"}' http://localhost:18084/todos
# {"title":"buy milk","done":false,"id":1}
curl http://localhost:18084/todos
# [{"id":1,"title":"buy milk","done":false}]
curl http://localhost:18084/todos/1
# {"title":"buy milk","done":false,"id":1}
curl -X PUT -H 'Content-Type: application/json' -d '{"title":"buy milk","done":true}' http://localhost:18084/todos/1
# {"title":"buy milk","done":true,"id":1}
curl -X DELETE http://localhost:18084/todos/1     # 204
curl http://localhost:18084/todos/99              # 404, структурированное тело HttpError JSON
curl -X POST -H 'Content-Type: application/json' -d '{"text":"call back"}' 'http://localhost:18084/todos/1/note?pinned=true'
# noted id=1 pinned=true text=call back
curl http://localhost:18084/openapi.json
# {"openapi":"3.0.3", ...} — полный документ см. openapi.golden.json
```

`POST /todos/{id}/note` — форма **bare-сахара** из плана 222.3 (№140 закрыт
2026-07-31): ОДИН record (`AddNoteReq`, `src/main.nv`), поля которого — три
ГОЛЫХ типа, каждый со СВОИМ источником — `TodoIdParam`=path,
`NoteQuery`=query, `NoteBody`=body — склеенных рукописным
`#impl(FromRequest)`, который читает поля по очереди и короткозамыкается на
первом `Err` (см. `AddNoteReq.from_request`). Регистрация — через
`Router.@post_typed_h` (generic-хендлер `fn(T) -> ServerResponse` + один
type-param `T FromRequest`): адаптер извлечения и запись `T.reflect()` в
шэйпы маршрута делает сам сахар — ни рукописного адаптер-замыкания, ни
hand-built `req_shape`.

## Что покрутить

- Добавь фильтр `GET /todos?done=true`, читая `req.query_param("done")`.
- Добавь `PATCH /todos/{id}`, обновляющий только поля, присутствующие в
  теле (сегодняшний `PUT` тут безусловно заменяет и `title`, и `done`).

## Что этот пример обходит

- **Две-и-более независимые регистрации маршрута на одном пути, каждая
  захватывающая одно и то же внешнее mutable-состояние**, падают при
  старте (минимальный репро изолирован в этой волне). Каждый путь на этой
  странице с более чем одним HTTP-методом (`/todos`: GET+POST,
  `/todos/{id}`: GET+PUT+DELETE) поэтому зарегистрирован одной явной цепочкой
  `MethodRouter` (`get(h).post(h2)`), а не отдельными вызовами
  `.get()`/`.post()` — те же хендлеры, просто сцеплены. [`02-routing`](../02-routing/)
  использует обычную поштучную форму везде и не нуждается в таком обходе
  (его хендлеры не делят mutable-состояние между методами одного пути).

Заведено владельцу компилятора/рантайма; не говорит ничего про собственный
API роутинга/хендлеров/JSON Polaris, который этот пример исполняет
по-настоящему. (Сериализация коллекции — `GET /todos`, возвращающий
`Vec[Todo]` напрямую через `ServerResponse.json` — раньше требовала здесь
обхода ручной сборкой JSON из-за открытой дыры кодогена, nova/221.1 №111;
дыра закрыта, так что теперь каждый эндпоинт на этой странице идёт через
настоящий derive `Serialize` единообразно — и отдельный `Todo`, и `Vec[Todo]`
одинаково.)

## Связанная документация

- [`docs/handlers-response.ru.md`](../../docs/handlers-response.ru.md) — `Json[T]`, `IntoResponse`, `StatusCode`
- [`docs/errors.ru.md`](../../docs/errors.ru.md) — `HttpError`, blanket `Result[T, HttpError]`
- [`docs/routing.ru.md`](../../docs/routing.ru.md) — `MethodRouter`

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
