# 06 — static-site

Встроенные статические файлы (`embed_dir("../assets")` — целая папка
запекается в бинарь как `EmbeddedDir`), резолв index-файла на корне,
`Cache-Control` на каждый ответ и content-based ETag.

По мотивам: `static-file-server`-пример axum.

## Раскладка

```
assets/
  index.html   # отдаётся на "/"
  style.css    # отдаётся на "/assets/style.css"
  logo.png     # отдаётся на "/assets/logo.png" (32x32, сгенерирован скриптом
               # на стандартной библиотеке python zlib+struct, закоммичен как настоящий PNG)
src/main.nv    # `fn site() -> EmbeddedDir => embed_dir("../assets")`
```

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18087
```

```sh
curl http://localhost:18087/                       # содержимое index.html
curl -D - http://localhost:18087/assets/style.css   # 200, ETag, Cache-Control, content-type: text/css
curl http://localhost:18087/assets/logo.png         # настоящий 32x32 PNG, content-type: image/png
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
- Положи файл в `assets/` — `embed_dir` подхватит его на следующей сборке,
  ручной список `EmbeddedEntry` поддерживать не нужно.

## Связанная документация

- [`docs/static-files.ru.md`](../../docs/static-files.ru.md) — `EmbeddedDir`, правила ETag/Range/index, безопасность

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
