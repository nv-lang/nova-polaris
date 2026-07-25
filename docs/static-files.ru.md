# Отдача статических файлов

[English](static-files.md) | **Русский**

`polaris.static` отдаёт файлы из источника
[`ReadFs`](https://github.com/nv-lang/nova/blob/main/std/src/fs/readfs.nv) —
`EmbeddedDir` (байты, запечённые в бинарник, детерминированно, обычный
production-выбор) или `DirFs` (живое чтение с диска под эффектом `Fs`,
полезно для dev live-reload). Семантика следует `http.FileServer`/
`serveContent` из Go в тонких местах ETag/Range, и `ServeDir` из tower-http
— по общей форме.

Исходник: [`src/static.nv`](../src/static.nv).

---

## Содержание

- [Отдача встроенных ассетов](#отдача-встроенных-ассетов)
- [Что реализовано](#что-реализовано)
- [Безопасность](#безопасность)
- [Связанные документы](#связанные-документы)

---

## Отдача встроенных ассетов

```nova
fn static_fixture() -> EmbeddedDir =>
    EmbeddedDir.new([
        EmbeddedEntry { path: "index.html", data: "<h1>hi</h1>".bytes() },
        EmbeddedEntry { path: "notes/readme.txt", data: "hello world".bytes() },
    ])

test "static-files: serve embedded assets — mime, ETag, index resolution, 404" {
    mut r = Router.new()
    r.get("/assets/{*path}", static_handler(static_fixture(), Static.new(), "path"))!!

    ro txt = route_once(r, get_req("/assets/notes/readme.txt"))
    assert(txt.status_code() == 200)
    assert(hdr(txt, "content-type") == "text/plain; charset=utf-8")
    assert(hdr(txt, "etag") != "")

    ro missing = route_once(r, get_req("/assets/nope.txt"))
    assert(missing.status_code() == 404)

    // empty {*path} can't come through the router (no request maps to it) —
    // call serve_path directly to serve the index file, same as static_handler does.
    mut r2 = Router.new()
    r2.get("/", fn(req ServerRequest) -> ServerResponse =>
        serve_path(static_fixture(), Static.new(), "", req))!!
    ro idx = route_once(r2, get_req("/"))
    assert(hdr(idx, "content-type") == "text/html; charset=utf-8")
}
```

`EmbeddedDir`/`EmbeddedEntry` — типы прелюдии (`embed_dir("dir")` во время
сборки — обычный способ заполнить их из реальной директории — см.
`std/src/prelude/embed.nv`); записи должны быть отсортированы по пути.
`static_handler(fs, cfg, param)` одним вызовом строит готовый `Handler` для
route-catch-all `{*param}`; `serve_path(fs, cfg, path, req)` — низкоуровневая
функция, которую он оборачивает, для ручного подключения статики (например
под `/`, где нет доступного захвата `{*path}`, как показывает случай с
индексом выше).

`Static.new()` по умолчанию — `index.html` для `""`/путей с завершающим `/`
и без заголовка `Cache-Control`; `@index(name)`/`@cache_control(v)`
переопределяют то или другое.

## Что реализовано

Практическое подмножество `serveContent` из Go, адаптированное под `ReadFs`,
который не несёт mtime:

| Возможность | Поведение |
|---|---|
| ETag от содержимого | сильный тег, `"<len-hex>-<crc32-hex>"` — идентичные байты получают идентичный тег на любом хосте, в отличие от mtime-based |
| `If-None-Match` | `304`, поддержаны список/префикс `W/`/`*` (слабое сравнение — нормально для content-ETag) |
| `Range` (одиночный) | `206` с `Content-Range`; `If-Range` защищает от устаревшего валидатора (полный `200` при несовпадении) |
| Неудовлетворимый range | `416` + `Content-Range: bytes */<size>` |
| Битый/multi-range | игнорируется → полный `200` (собственное правило Go) |
| MIME | по расширению, небольшая встроенная таблица (html/css/js/json/svg/картинки/шрифты/wasm/pdf/xml/mp4/…, иначе `application/octet-stream`) |
| Разрешение индекса | `""`/завершающий `/` → `<cfg.index>` |

**Не реализовано**: `If-Modified-Since`/`Last-Modified` (нет mtime для
сравнения — ETag его заменяет), multi-range/multipart-ответы (Go их
отдаёт; редкий случай, отложено), автоматический ответ на `HEAD`
(маршрутизация методов — дело `Router`'а, регистрируйте `HEAD` явно, если
нужно).

## Безопасность

Попытка `..`-побега никогда не доходит до пользовательского кода: `DirFs`
отклоняет её внутри себя (проверка границ внутри абстракции файловой
системы), а `EmbeddedDir` — это map с точными ключами, где ключ,
содержащий `../`, просто не существует — оба случая приходят к обычному
`404`, неотличимому от любого другого отсутствующего пути (никакой утечки
информации о *причине* отказа).

## Связанные документы

**Полный пример:** [`examples/06-static-site`](../examples/06-static-site) — встроенные файлы, index-фолбэк, Cache-Control, реально запущенные.

- [routing.md](routing.ru.md) — шаблон catch-all `{*path}`, который ожидает `static_handler`
- [handlers-response.md](handlers-response.ru.md) — `ServerResponse`, заголовки
- [`src/static.nv`](../src/static.nv), [`src/static_test.nv`](../src/static_test.nv)
