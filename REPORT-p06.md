# Отчёт p-06 — пример 06-static-site → embed_dir мини-сайт «Hello, Nova!»

Модель: big-pickle (opencode/big-pickle) · ветка `p-06-embeddir`

## Коммиты

| Хеш       | Файлы                                 | Суть |
|-----------|---------------------------------------|------|
| `1772302` | `examples/06-static-site/assets/`     | index.html, style.css, logo.png (32x32, python zlib+struct, скрипт удалён) |
| `0087043` | `examples/06-static-site/src/main.nv` | `fn site() -> EmbeddedDir => embed_dir("../assets")` вместо ручного списка EmbeddedEntry; №109-обход и маркер-комментарий сохранены |
| `ce7e16d` | `examples/06-static-site/nova.lock.toml` | tls → v0.1.5 (commit `3003b64`), см. находки |
| `d2e76a5` | `examples/06-static-site/README.md`, `README.ru.md` | обновлены под новую структуру |

## Гейты (вердикты дословно)

### 1. Сборка

```
nova build examples/06-static-site/src/main.nv --strict-effects
built: D:\Sources\nv-lang\nova-polaris-p06\main.exe (49.73s)
```

Предупреждения: три `W_REPLACE_IN_DEPENDENCY` (машино-локальный root `nova.override.toml`, см. находки) + vendor-ное `warning: new_then_cap` из nova-compress. Ошибок нет.

### 2. Запущенный сервер (0.0.0.0:18087), curl по команде из задания

```
curl -s -o NUL -w "%{http_code} %{content_type}\n" http://127.0.0.1:18087/               -> 200 text/html; charset=utf-8
curl -s -o NUL -w "%{http_code} %{content_type}\n" http://127.0.0.1:18087/assets/style.css -> 200 text/css; charset=utf-8
curl -s -o NUL -w "%{http_code} %{content_type}\n" http://127.0.0.1:18087/assets/logo.png  -> 200 image/png
```

Все 200 с верными типами; процесс погашен. Доп. дымовые проверки: `/` отдаёт «Hello, Nova!»-разметку; `If-None-Match` по полученному `ETag` → 304 (0 байт); `Range: bytes=0-4` на style.css → 206 `text/css; charset=utf-8`; `/assets/missing.txt` → 404.

### 3. Линт тронутых .nv

```
nova lint examples/06-static-site/src/main.nv --strict-effects
lint: 1 file(s), 0 finding(s)
```

### 4. Тесты из корня worktree

`nova.sh` в репе нет; вызов с env-оверрайдами (компилятор вне polaris-репы):

```
NOVA_CG_INCLUDE=d:/Sources/nv-lang/nova/compiler-codegen
NOVA_RT_DIR=d:/Sources/nv-lang/nova/compiler-codegen/nova_rt
NOVA_STD_PATH=d:/Sources/nv-lang/nova/std
nova test src --strict-effects
```

```
PASS: 37  FAIL: 0  SKIP: 18 (skipped)
```

Канон `PASS: 37+ FAIL: 0` выполнен (37/0/18).

## Находки

- **MIME png — обход НЕ потребовался.** В `polaris/src/static.nv` таблица уже содержит `"png" → "image/png"` (и `"css" → "text/css; charset=utf-8"`); serve_path отдаёт их сам, как видно из вердикта гейта 2.
- **tls-зависимость поляриса требует `TlsStream.@read_bytes`** (ServerPolicy/TLS-путь из p-polaris-tls). Таги v0.1.3/v0.1.4 (в т.ч. зафиксированный `910e14be`) имеют старое имя `read_to_vec` → при сборке `E7320 no field read_bytes on TlsStream`. Ренейм — только в v0.1.5 (commit `3003b64`, «rename: read_to_vec -> read_bytes», 2026-08-01). `nova update` и `nova update --precise tls@0.1.5` не сработали (осталась `910e14be`) — lock-фикс внесён вручную (`nova.lock.toml`), сборка стала зелёной.
- **`src/serdejson_repro_test` падал с `E_READONLY_COERCE`** на `http@v0.1.1` (`5257f302`) в `client/mock.nv:108`: `mut rs = @routes` алиасил и мутировал receiver (`@routes` ro). Фикс существует только в untagged sibling-чекауте `nova-http` (`9749a7a`, «builder @on — честная clone-копия таблицы»). Снят машино-локальным gitignored `nova.override.toml` в корне worktree (`[replace]` http/compress/tls → `../nova-{http,compress,tls}`) — тот же механизм, что задокументирован в PROGRESS.md для окна p-polaris-tls. Файл в коммиты НЕ входит; из-за него при сборке примера всплывают три `W_REPLACE_IN_DEPENDENCY` (замена поляриса-как-зависимости игнорируется, go-семантика) — на чистый клон без override не влияет.
- **curl `-o NUL` в git-bash** создаёт файл с именем `NUL` (а не null-device); значения 200/типы те же, файл удалён после проверки.
- Побочные артефакты сборок (`main.exe` в корне, корневой `nova.lock.toml`) после верификации удалены; `git status` по нецелевым путям чист.
