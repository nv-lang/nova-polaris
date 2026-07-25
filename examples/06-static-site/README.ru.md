# 06 — static-site

Встроенные статические файлы (`EmbeddedDir`, байты запечены прямо в
бинарь), резолв index-файла на корне, `Cache-Control` на каждый ответ и
content-based ETag.

По мотивам: `static-file-server`-пример axum.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18087
```

```sh
curl http://localhost:18087/                       # содержимое index.html
curl -D - http://localhost:18087/assets/style.css   # 200, ETag, Cache-Control, content-type: text/css
curl http://localhost:18087/assets/notes/hello.txt  # вложенный файл
curl -o /dev/null -w '%{http_code}\n' http://localhost:18087/assets/missing.txt   # 404
```

## Что покрутить

- Добавь заголовок `If-None-Match` с полученным `ETag` — придёт `304` без
  тела, см. [`docs/static-files.ru.md`](../../docs/static-files.ru.md).
- Добавь заголовок `Range: bytes=0-4` на `/assets/style.css` — придёт `206`
  с `Content-Range`.
- Замени `EmbeddedDir` на `DirFs` (настоящая директория под эффектом `Fs`,
  полезно для dev live-reload) — см. doc-комментарий модуля в
  [`src/static.nv`](../../src/static.nv).

## Пробел, который этот пример обходит

`polaris.static.static_handler(fs, cfg, param)` — хелпер «готовый Handler
одним вызовом», описанный в `docs/static-files.md` — сейчас упирается в
пробел кодогена для собственного `EmbeddedDir` этого пакета (`nova: out of
memory` уже на первом отданном файле, изолировано в этой волне).
`/assets/{*path}` здесь вызывает `serve_path` напрямую из обычного
замыкания — точно та же форма, что уже использует маршрут `/`, и именно то,
что `static_handler` делает внутри (см. его однострочное тело в
`src/static.nv`) — пробел его не задевает. Заведено выше по стеку.

## Связанная документация

- [`docs/static-files.ru.md`](../../docs/static-files.ru.md) — `EmbeddedDir`, правила ETag/Range/index, безопасность

[English](README.md) · зачем пара `main()`/`production_main()` — в [`examples/README.ru.md`](../README.ru.md).
