# p-polaris-tls — прогресс

Задача: HTTPS-сервер в polaris (A-V13, решение владельца 2026-08-02: «тлс
для поляриса до релиза»). Бриф: `nova/scratch38/BRIEF_polaris_tls.md`.

## Сделано

1. `nova.toml` — прямая зависимость `tls` (git+version, форма как у `http`);
   `nova.override.toml` (НЕ закоммичен, `.gitignore` уже покрывает) — путь на
   sibling-чекаут `../nova-tls` для локальной разработки.
2. Серверный TLS-путь (минимальная форма — см. обоснование в самих файлах):
   - `src/net/servernet_tls.nv` (module `polaris.net`, peer `servernet.nv`)
     — `handle_connection_tls` + приватные `write_streaming_tls`/
     `write_stream_chunks_tls`/`read_request_tls`, байт-в-байт зеркало
     `servernet.nv`'s `handle_connection` под `TlsStream`/`TlsError` вместо
     `TcpStream`/`NetError`. Явные `_tls`-имена (не same-name overload) —
     решение осознанное, задокументировано в баннере файла.
   - `src/serve/serve_tls.nv` (module `polaris.serve`, peer `serve.nv`) —
     `handle_connection_router_tls` (тонкая обёртка, зеркало
     `handle_connection_router`) + `serve_tls(addr, tls_cfg, router)` —
     accept-цикл: bind → TLS-handshake на каждом принятом соединении → один
     запрос на соединение (`Connection: close`, БЕЗ `ServerPolicy`
     keep-alive/admission — сознательный scope-cut, обоснование в баннере).
     Accept-цикл — канон flagship (`Err(_) => { running = false }`, не
     back-off-retry `serve()`) — правка по ревью владельца.
3. Пример `examples/12-https/` — `serve_tls` + самоподписанный `localhost`
   серт (скопирован из `nova-tls/src/testdata/`, см. `certs/README.md`),
   один hello-роут. `README.md`/`README.ru.md`. Верхнеуровневые
   `examples/README.md`/`README.ru.md` — таблицы примеров и портов
   дополнены строкой `12-https` (порт 18093).
4. Тест — `src/net/servernet_tls_test.nv`: реальный TLS-хендшейк по loopback
   (два файбера, `Channel` для передачи порта — паттерн `nova-tls`'s own
   `handshake_test.nv`), проверяет `handle_connection_tls` целиком
   (handshake → байт-запрос → расшифрованный HTTP-ответ). НЕ `_slow` —
   хендшейк на loopback укладывается в доли секунды. Полный accept-цикл
   (`serve_tls`) отдельным юнит-тестом не дублируется — покрыт примером
   `12-https` (реальная сборка + `curl -k`, оба прошли).
5. Попутно (по списку `nova/scratch38/polaris-bindstr-sites.md`): все 11
   `.nv`-сайтов + 4 док-сайта (`examples/README.md`/`.ru.md`,
   `docs/overview.md`/`.ru.md`) `TcpListener.bind("...".to_socket_addr()!!)!!`
   → `TcpListener.bind("...")!!`. Попутная чистка новых unused-import
   `SocketAddr` в 11 файлах (10 examples + `doc_samples_test.nv`).
6. `nova.override.toml` (НЕ закоммичены) добавлены во ВСЕ 10 существующих
   `examples/NN-*/` + `12-https` — `tls` резолвится на sibling-чекаут вместо
   git-кэша: официально тегнутый `nova-tls` v0.1.4 ещё содержит СТАРОЕ имя
   `read_to_vec` (не `read_bytes`) — рен­ейм `read_to_vec → read_bytes`
   (владелец, коммит `3003b64`) существует только на нетегнутом HEAD
   `nova-tls`. `nova-http` уже сидит на этом же паттерне (свой
   `nova.override.toml`, `client/transport/real.nv:102` уже зовёт
   `read_bytes`) — не новая, а РАСШИРЕННАЯ на examples уже существующая
   ситуация; без override все 10 examples ломались ТРАНЗИТИВНО через
   `polaris` (весь пакет — одна CU, `nova check`/`test` резолвит ВСЕ
   exported-символы пакета, включая новые TLS-файлы, даже если конкретный
   example TLS не использует).

## Гейты

- `nova check src` (корень, с override) — **PASS: 55 FAIL: 0** (попутно
  пропала и предсуществовавшая до этого окна FAIL на
  `serdejson_repro_test.nv` — E_READONLY_COERCE внутри `nova-http`'s
  `client/mock.nv:108`, была на STALE git-cache коммите `http`; override на
  sibling-чекаут её тоже снял).
- `nova check` на всех 12 examples (`01`…`10`, `12-https`) — все **PASS: 1
  FAIL: 0** индивидуально.
- `nova build --strict-effects examples/12-https/src/main.nv` — **built**
  (34.99s); ЗАПУЩЕН, `curl -sk https://127.0.0.1:18093/` →
  `hello, world -- over HTTPS` — подтверждено вживую, сервер остановлен.
- `nova lint` на новых/тронутых файлах (`serve_tls.nv`, `servernet_tls.nv`,
  `servernet_tls_test.nv`, `doc_samples_test.nv`) — **9 findings**, из них
  8 в `doc_samples_test.nv` ПРЕДСУЩЕСТВУЮЩИЕ (не мои — правка там всего 2
  строки, см. `git diff`), 1 — baseline-паритетный swallow-match в
  `servernet_tls.nv` (идентичный паттерн уже есть непрочитанным в
  `servernet.nv:82`, прокомментирован). Собственные новые файлы
  (`serve_tls.nv`, `servernet_tls_test.nv`) — **0 findings**.
- `nova.sh test src --strict-effects` (канон 37/0/19) — **ЗАБЛОКИРОВАН**
  окружением: фактический прогон дал **PASS: 0 FAIL: 37 SKIP: 18** — см.
  «Блокер» ниже. Все 37 FAIL — `CC-FAIL: undefined symbol:
  BrotliDefaultAllocFunc/BrotliDefaultFreeFunc`, включая файлы вообще не
  связанные с TLS (`background_test`, `multipart_test`, `openapi`,
  `response`, `wire`, `ws_upgrade`, …) — mega-CU роняется целиком на
  линковке, а не на конкретных TLS-тестах; отдельный PASS/FAIL счёт для
  нового TLS-кода этим прогоном получить невозможно в принципе (никакой
  тест не долинковался вообще).

## Блокер (не мой мандат — компилятор, СТОП-репорт)

`nova test src` (полный, `--strict-effects`) массово падает `CC-FAIL` на
линковке (`undefined symbol: BrotliDefaultAllocFunc/BrotliDefaultFreeFunc`)
— воспроизводится на файлах, НИКАК не связанных с TLS (`background_test`,
`multipart_test`, `openapi`, `response`, …), подтверждено ДО и НЕЗАВИСИМО
от кода этого окна. Корень — конкурентная сборка vendor-FFI (brotli у
`compress` + mbedTLS у `tls` ОДНОВРЕМЕННО в одном `nova test`-прогоне,
`jobs=16`) архивирует НЕ те объекты не под те имена (`brotlidec.lib` в
`nova-compress/native/brotli/lib/` после такой сборки байт-в-байт совпадает
по размеру с `mbedtls.lib`/`mbedx509.lib`/`mbedcrypto.lib` — т.е. в файл с
именем brotli архивируется чужой контент; `nm` не находит
`BrotliDefaultAllocFunc` внутри). Изолированный прогон (`nova-tls` тест сам
по себе / `nova-compress` тест сам по себе) — оба ЧИСТО PASS, каждый
собирает СВОЙ vendor-lib корректно. Идентичная порча (те же
байт-в-байт-одинаковые `.lib`) уже сидела в `nova-tls/native/lib/` с
21-22.07 — то есть окружение уже было заражено ДО этого окна.

Ближайший затрекан­ный дефект: **№152 / `[M-vendor-ffi-build-race-in-git-dep-cache]`**
(`docs/plans/221.1-bug-sweep.md`, 🔴 P2, «компилятор-очередь», найден
интегратором при приёмке A-V7 2026-07-30) — та же категория (конкурентная
vendor-FFI сборка на холодном кэше, `test_runner.rs`
`build_missing_vendor_ffi_libs`, родственник `[M-218-rt-archive-parallel-
jobs-race]`, чей mutex-фикс на этот путь не распространили). Симптом там
описан как `C1083 Permission denied` (self-heals на втором прогоне);
здесь — молчаливое архивирование НЕ ТЕХ объектов под чужим именем
(undefined symbol, НЕ self-heal — воспроизведено трижды подряд, включая
после ручной очистки кэша и раздельного прогрева). Возможно тот же корень,
возможно смежный вариант — интегратору виднее; фикс — компилятор
(`compiler-codegen/src/test_runner.rs`), вне мандата этого окна
(`nova`-репу не трогаю).

Что ЭТО НЕ блокирует: `nova check` (весь пакет + все examples) —
чисто (см. выше); `nova build` + реальный запуск `12-https` — работает
(видимо, `nova build` линкует по reachability конкретного бинаря и не тянет
неиспользуемый `compress`, тогда как `nova test src` линкует КАЖДЫЙ
test/main-таргет пакета как отдельный юнит — и тянет ВСЕ FFI-зависимости
пакета целиком на каждый). Свежий код этого окна (`servernet_tls.nv`,
`serve_tls.nv`, `servernet_tls_test.nv`) прошёл ВСЁ, что не упирается в
этот блокер.

## Дальше

Если интегратор поднимет мутекс-фикс на generic vendor-FFI сборку
(родственный `[M-218-rt-archive-parallel-jobs-race]`'s мьютексу) — перегнать
`nova.sh test src --strict-effects` и доложить реальные PASS/FAIL/SKIP
числа против канона 37/0/19.
