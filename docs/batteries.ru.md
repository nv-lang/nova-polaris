# Батарейки: cors, compress, log, ratelimit

[English](batteries.md) | **Русский**

Четыре готовые реализации [`Middleware`](middleware.ru.md), каждая — свой
модуль, каждая — fluent-конфиг, заканчивающийся `@middleware()` (или
одноимённой свободной функцией — `cors(cfg)`, `compression(cfg)`,
`logger(cfg)`, `ratelimit(cfg)`), которую передают в `Router.@layer`.

| Батарейка | Модуль | Семантика |
|---|---|---|
| [cors](#cors) | `polaris.middleware.cors` | tower-http `CorsLayer` |
| [compress](#compress) | `polaris.middleware.compress` | tower-http `CompressionLayer` (только gzip) |
| [log](#log) | `polaris.middleware.log` | chi `Logger` + `RequestID` + `RealIP`, слитые в один |
| [ratelimit](#ratelimit) | `polaris.middleware.ratelimit` | chi `Throttle` / `tower::limit`, поверх `TokenBucket` из `std` |

Исходник: [`src/middleware/cors.nv`](../src/middleware/cors.nv),
[`compress.nv`](../src/middleware/compress.nv), [`log.nv`](../src/middleware/log.nv),
[`ratelimit.nv`](../src/middleware/ratelimit.nv).

---

## cors

```nova
test "batteries: cors — preflight answered 204, simple request decorated" {
    mut c = Cors.new()
    c.allow_origin("https://app.example")
    mut r = Router.new()
    r.layer(cors(c))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!

    ro simple = route_once(r, get_req_h("/x", "Origin", "https://app.example"))
    assert(simple.status_code() == 200)
    assert(hdr(simple, "Access-Control-Allow-Origin") == "https://app.example")

    ro preflight_raw = "OPTIONS /x HTTP/1.1\r\nHost: n\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: GET\r\n\r\n".bytes()
    ro preflight = route_once(r, preflight_raw)
    assert(preflight.status_code() == 204)
}
```

`Cors.new()` стартует строго (ничего не разрешено); `Cors.permissive()`
разрешает любой origin/метод/заголовок без credentials (форма
tower-http'шного `permissive()`). Методы-билдеры: `@allow_origin(origin)`
(повторяемо), `@allow_any_origin()`, `@allow_method(m)`/`@allow_any_methods()`,
`@allow_header(name)`/`@allow_any_headers()`, `@expose_header(name)`,
`@credentials(bool)`, `@max_age(secs)`.

Preflight-запросы `OPTIONS` (с `Access-Control-Request-Method`) отвечаются
**полностью самим middleware** — `204`, `next` не вызывается вовсе,
собственный `405`-fallback обёрнутого route'а никогда не показывается.
`Access-Control-Allow-Origin: *` вместе с `credentials(true)` запрещено
спецификацией, и `@middleware()` на такой конфигурации **паникует** — как
и tower-http, на том основании, что такая комбинация всегда является багом
вызывающего кода (D325), а не живым сетевым вводом.

## compress

```nova
test "batteries: compress — gzip only above min_size and when the client accepts it" {
    mut r = Router.new()
    r.layer(compression(Compression.new()))
    consume sb = StringBuilder.new()
    mut i = 0
    while i < 100 { sb.append("the quick brown fox jumps over the lazy dog; "); i += 1 }
    ro big = sb.into_str()
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, big))!!

    ro accepted = route_once(r, get_req_h("/x", "Accept-Encoding", "gzip"))
    assert(hdr(accepted, "Content-Encoding") == "gzip")
    ro declined = route_once(r, get_req("/x"))
    assert(hdr(declined, "Content-Encoding") == "")
}
```

`Compression.new()` по умолчанию — минимальный размер 1024 байта и дефолтный
уровень gzip (`@min_size(n)`/`@level(l)` для настройки). Пропускается
автоматически — никогда не баг наложить его везде — когда: ответ уже
стримится (chunk-продюсер выигрывает провод), тело меньше `min_size`, ответ
уже несёт `Content-Encoding`, content-type не в allowlist для сжатия
(`text/*` + json/xml/javascript-подобные подтипы), либо клиентский
`Accept-Encoding` не допускает gzip. `Vary: accept-encoding` добавляется
всегда, когда ответ *мог бы* быть согласуемым, даже если конкретно этот
ответ остался identity — чтобы разделяемый кэш никогда не отдал gzip-тело
клиенту, который не умеет его раскодировать. Brotli не предлагается —
пакет `compress`, лежащий в основе, поставляет только декодер, без
энкодера, поэтому согласование `br` намеренно отсутствует, пока энкодер
не появится.

## log

```nova
test "batteries: log — one line per request, X-Request-Id propagated" {
    mut lines []str = []
    ro cfg = AccessLog.new()
    with Time = th.fixed_ms(0), Log = capture_log(lines) {
        mut r = Router.new()
        r.layer(logger(cfg))
        r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
        ro resp = route_once(r, get_req("/x"))
        assert(hdr(resp, "x-request-id") == "req-1")
        assert(lines.len() == 1)
        assert(lines[0] == "[req-1] GET /x -> 200 2B in 0ms")
    }
}
```

Одна строка на запрос: метод, путь, статус, размер тела ответа, wall-clock
длительность. `AccessLog.new()` по умолчанию — request-id **включён**,
real-ip **выключен**; строки идут через ambient
[эффект `Log`](serving.ru.md#эффект-log) — по умолчанию в stdout,
перенаправляемо в тестах через `with Log = capture_log(lines) { ... }`
(тест выше перехватывает их в `Vec[str]` — скрейпинг stdout не нужен и в
ваших собственных тестах). `X-Request-Id` берётся из входящего заголовка,
если он присутствует и безопасен, иначе генерируется из счётчика
конкретного конфига (`req-1`, `req-2`, …) и эхом возвращается в ответе.
`@real_ip(true)` добавляет в строку первый хоп `X-Forwarded-For` — по
умолчанию **выключено**, тот же предупреждающий комментарий, что у
chi'шного `RealIP`: этот заголовок контролируется клиентом, доверяйте ему
только за прокси, который его перезаписывает.

`@middleware()` несёт эффект-ряд `Time` (он измеряет wall-clock
длительность вокруг обёрнутого хендлера) — тесты фиксируют часы через
`with Time = th.fixed_ms(...)` (`std.testing.handlers`) для
детерминированного вывода, как показано выше. `Log` в этом ряду НЕТ:
строка запроса эмитится сырым опом `Log.info(...)` (не проверяется под
`--strict-effects`, см. [serving.md](serving.ru.md#эффект-log)), поэтому
он свободно комбинируется в одном `with Time = ..., Log = ... { ... }`.

## ratelimit

```nova
test "batteries: ratelimit — burst within capacity passes, then 429 + Retry-After" {
    with Time = th.fixed_ms(0) {
        mut r = Router.new()
        r.layer(ratelimit(RateLimit.new(1, 1.0)))
        r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
        assert(route_once(r, get_req("/x")).status_code() == 200)
        ro second = route_once(r, get_req("/x"))
        assert(second.status_code() == 429)
        assert(hdr(second, "retry-after") == "1")
    }
}
```

`RateLimit.new(capacity, per_sec)` — `capacity` токенов burst'а,
пополняемых со скоростью `per_sec` токенов в секунду, поверх `TokenBucket`
из `std`. По умолчанию — **один глобальный bucket** (форма chi'шного
`Throttle`); `@per_client(true)` разделяет buckets по первому хопу
`X-Forwarded-For` (тот же предупреждающий комментарий про доверие, что и у
`RealIP` в `log`). Отклонённый запрос получает `429` +
`Retry-After: <ceil(1/per_sec)>` секунд — ближайший момент, когда токен
может появиться снова. Как и `log`, построение middleware несёт эффект-ряд
`Time` (bucket пополняется относительно `Monotonic.now()`); тесты
фиксируют часы тем же способом.

> **Известное упрощение**: bucket не защищён локом — под настоящей
> M:N-параллельностью два fiber'а в принципе могут одновременно увидеть
> последний токен. Over-admission примерно на один токен под конкуренцией
> throttle'ит, но не портит состояние.

## Связанные документы

**Полный пример:** [`examples/04-middleware`](../examples/04-middleware) — `log`+`ratelimit` реально запущенные (см. также [`10-mini-service`](../examples/10-mini-service) — `log` в сервисе побольше).

- [middleware.md](middleware.ru.md) — ядро `Middleware`/`Router.@layer`, на котором это построено
- [auth.md](auth.ru.md) — `require_jwt`/`session_layer`, ещё два готовых middleware
- [`src/middleware/`](../src/middleware) — полный исходник + pin-тесты для всех четырёх
