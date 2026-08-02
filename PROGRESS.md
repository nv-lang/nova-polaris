# p-docs-extractors — прогресс

Задача: документация типизированных маршрутов/экстракторов polaris (дыра
Ф.3, владелец 2026-08-02: «описано в документации? примеры есть?» — примера
хватает, доков нет).

## Сделано

1. Новая страница `docs/extractors.md` + `docs/extractors.ru.md` (по
   образцу `docs/routing.md`/`docs/middleware.md`): `FromRequest`-протокол,
   шесть встроенных экстракторов (`PathParam[T]`/`Query[T]`/`Json[T]`/
   `Bytes`/`Text`/`Headers`/`Req`), короткое замыкание первого `Err` →
   `into_response()` (хендлер не зовётся), голый-типовой сахар
   `FromPath`/`FromQuery`/`FromBody`, typed-маршруты (`TypedRoute` +
   `@get_typed`/`@post_typed`/`@put_typed`/`@delete_typed`/`@patch_typed`),
   bare-sugar `@post_typed_h[T]` (единственный член семейства сегодня —
   грепом подтверждено), связь с OpenAPI (`T.reflect()` →
   `Router.introspect()` → `openapi_json`/`openapi_handler`), известная
   церемония `.data()` (одна честная строка, без сроков — №147/`D39-embed`).
2. `docs/routing.md`/`.ru.md` — раздел-указатель «Typed routes» (10 строк,
   один пример `post_typed_h`) со ссылкой на `extractors.md`.
3. Индексы: `docs/README.md`/`.ru.md`, корневой `README.md`/`.ru.md` —
   строка `extractors.md` добавлена после `handlers-response.md`.
4. Попутно (найдена прямая коллизия при добавлении новой страницы, не
   отдельная задача): `docs/handlers-response.md`/`.ru.md`'s раздел
   «Typed extraction: FromRequest» утверждал «сахара нет вовсе» — устарело
   (typed-routes сахар СУЩЕСТВУЕТ под отдельным именем); `docs/roadmap.md`/
   `.ru.md`'s «OpenAPI generation: Not implemented» — ЛОЖНО (реализовано,
   Ф.1-Ф.3). Обе страницы точечно поправлены + ссылки на `extractors.md`
   добавлены — иначе новая страница противоречила бы уже существующим.
5. `src/doc_samples_test.nv` — новая секция `extractors.md` (2 теста):
   bare-sugar bundle (`AddNoteReq`: `FromPath`+`FromQuery`+`FromBody`,
   `post_typed_h`, short-circuit на плохом `{id}`) + `TypedRoute`+
   `@get_typed`+`introspect()`+`openapi_handler` end-to-end. Импорты
   добавлены: `FromRequest, FromPath, FromQuery, FromBody, TypedRoute,
   openapi_handler` (polaris), `Reflect, TypeShape` (std.reflect).
6. Коммит `f3f154d` на `master` (до переименования в `main`), затем
   перебазирован на свежий `main` (влиты `p-polaris-tls`/A-V13 этап 1 и
   `p-06-embeddir` после ответвления) — конфликт только в `PROGRESS.md`
   (scratch-файл предыдущей волны, TLS-контент), разрешён в пользу этой
   волны; `src/doc_samples_test.nv` авто-слился без конфликта.

## Гейты

- `./nova.sh test src --strict-effects` (компилятор
  `d:/Sources/nv-lang/nova/nova-cli/target/release/nova.exe`) — канон
  37/0/19. Финальный чистый прогон (без соседства чужого процесса на
  машине) — **PASS: 37 FAIL: 0 SKIP: 19**, `src/doc_samples_test` PASS
  (176.6s) — новые сниппеты компилируются и проходят. Более ранние прогоны
  этого же окна показали единичные транзиентные FAIL/TIMEOUT на НЕТРОНУТЫХ
  файлах (`server_serve` codegen-fail на файловой блокировке Windows —
  перепригнан изолированно, PASS; `background`/`metrics_test` TIMEOUT под
  нагрузкой) — на машине параллельно шла ДРУГАЯ сессия
  (`nova-p152\...\nova.exe test src`, подтверждено через
  `Get-CimInstance Win32_Process`), не моя правка; финальный прогон это
  подтверждает (чисто).
- `./nova.sh lint src/doc_samples_test.nv` — 8 находок, ВСЕ вне вставленной
  секции (`extractors.md`, строки 301-396) — 0 новых находок от этой волны.

## Дальше

Готово к сдаче — см. отчёт интегратору. После приёмки чекаут возвращён на
`main` (ветка `p-docs-extractors` НЕ удалена).
