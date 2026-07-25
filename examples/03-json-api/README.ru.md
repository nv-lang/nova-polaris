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
```

## Что покрутить

- Добавь фильтр `GET /todos?done=true`, читая `req.query_param("done")`.
- Добавь `PATCH /todos/{id}`, обновляющий только поля, присутствующие в
  теле (сегодняшний `PUT` тут безусловно заменяет и `title`, и `done`).

## Что этот пример обходит

- **Сериализация коллекции `Vec[T Serialize]`** — открытый пробел кодогена
  (собственная поддержка коллекций в serde ещё доезжает — см. список «пока
  не реализовано» в [`docs/roadmap.ru.md`](../../docs/roadmap.ru.md)).
  `GET /todos` собирает JSON-массив вручную построчно
  (`todo_json_line`/`todos_json`) вместо прямой сериализации `Vec[Todo]`;
  каждый ОТДЕЛЬНЫЙ `Todo` всё же идёт через настоящий derive `Serialize`
  через `ServerResponse.json` везде на этой странице.
- **Две-и-более независимые регистрации маршрута на одном пути, каждая
  захватывающая одно и то же внешнее mutable-состояние**, падают при
  старте (минимальный репро изолирован в этой волне). Каждый путь на этой
  странице с более чем одним HTTP-методом (`/todos`: GET+POST,
  `/todos/{id}`: GET+PUT+DELETE) поэтому зарегистрирован одной явной цепочкой
  `MethodRouter` (`get(h).post(h2)`), а не отдельными вызовами
  `.get()`/`.post()` — те же хендлеры, просто сцеплены. [`02-routing`](../02-routing/)
  использует обычную поштучную форму везде и не нуждается в таком обходе
  (его хендлеры не делят mutable-состояние между методами одного пути).

Оба заведены владельцу компилятора/рантайма; ни один не говорит ничего про
собственный API роутинга/хендлеров/JSON Polaris, который этот пример
исполняет по-настоящему.

## Связанная документация

- [`docs/handlers-response.ru.md`](../../docs/handlers-response.ru.md) — `Json[T]`, `IntoResponse`, `StatusCode`
- [`docs/errors.ru.md`](../../docs/errors.ru.md) — `HttpError`, blanket `Result[T, HttpError]`
- [`docs/routing.ru.md`](../../docs/routing.ru.md) — `MethodRouter`

[English](README.md) · зачем пара `main()`/`production_main()` — в [`examples/README.ru.md`](../README.ru.md).
