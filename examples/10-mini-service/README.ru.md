# 10 — mini-service

Всё из этого набора примеров вместе: урезанный профиль **RealWorld
(Conduit)** — users/auth (регистрация, логин, JWT) + CRUD статей +
пагинация — плюс middleware `log` и встроенная статическая landing-страница.
Компактнее флагманского примера, но той же формы: настоящая референс-точка
для маленького сервиса.

По мотивам: [RealWorld](https://github.com/gothinkster/realworld) (Conduit)
— спека «Medium-clone API», используемая десятками реализаций фреймворков
как бенчмарк зрелости.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18091
```

```sh
curl http://localhost:18091/health              # ok
curl http://localhost:18091/                    # встроенная landing-страница

TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"username":"nova","password":"x"}' http://localhost:18091/users)
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"username":"nova","password":"x"}' http://localhost:18091/users/login   # тот же токен обратно

curl http://localhost:18091/articles             # []

curl -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' \
  -d '{"title":"Hello World","body":"first post"}' http://localhost:18091/articles   # 401, нет Bearer

curl -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"Hello World","body":"first post"}' http://localhost:18091/articles
# {"slug":"hello-world","title":"Hello World","body":"first post","author":"demo"}

curl http://localhost:18091/articles                 # статья в списке
curl http://localhost:18091/articles/hello-world      # статья по slug
curl 'http://localhost:18091/articles?limit=1&offset=0'   # пагинация
```

## Что здесь намеренное упрощение

Это **демо-профиль**, не полная спека RealWorld: `users` хранит только
имена (без хеширования/проверки пароля — любой пароль «работает», раз
пользователь зарегистрирован, то же упрощение делает `/login` в 05-auth),
у статей нет `favorited`/`tagList`/комментариев, а `author` всегда
`"demo"`, а не реальный `sub` из JWT вызывающего (оставлено как «что
покрутить» — см. ниже). Полный порт RealWorld — явно **отдельный,
после-релизный** кандидат, не задача этого примера.

## Что покрутить

- Прочитай `sub` из JWT вызывающего (`auth.claims_at[...]`, см.
  [`05-auth`](../05-auth/)) и используй его как `Article.author` вместо
  захардкоженного `"demo"`.
- Добавь `PUT`/`DELETE /articles/{slug}` (та же форма цепочки
  `MethodRouter`, что `/articles` уже использует для GET+POST — см.
  [`03-json-api`](../03-json-api/), почему это здесь важно).
- Добавь настоящую проверку пароля (хоть тривиальную) в `/users/login`.

## Связанная документация

- [`docs/handlers-response.ru.md`](../../docs/handlers-response.ru.md), [`docs/auth.ru.md`](../../docs/auth.ru.md), [`docs/middleware.ru.md`](../../docs/middleware.ru.md), [`docs/static-files.ru.md`](../../docs/static-files.ru.md), [`docs/serving.ru.md`](../../docs/serving.ru.md) — каждый кусок, который этот пример собирает воедино

[English](README.md) · зачем пара `main()`/`production_main()` — в [`examples/README.ru.md`](../README.ru.md).
