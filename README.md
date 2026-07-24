# nova-polaris

**Polaris** ⭐ — серверный веб-фреймворк для [Nova](https://nv-lang.org):
`Router` (segment-trie, `{param}`/`{*rest}`, nest/fallback), extractors,
`IntoResponse`, middleware-композиция + батарейки (cors, static, compress,
log, ratelimit), auth (basic/bearer/session), websocket, graceful serve.

**Nova** — новая звезда; **Polaris** — та, по которой держат курс.

```nova
import polaris.{Router, get}

fn main() Net -> () {
    ro app = Router.new()
        .route("/hello/{name}", get(fn(req ServerRequest) -> ServerResponse =>
            ServerResponse.text(StatusCode.OK, "hello, ${req.param("name")}")))
    polaris.serve(app, ":8080")
}
```

Ядро протокола (типы `Request`/`Response`/`HeaderMap`/`Url`, HTTP-клиент,
транспорт) — пакет [`http`](https://github.com/nv-lang/nova-http): Polaris
зависит от него, пользователю он приходит транзитивно.

## Статус

Извлечение фреймворк-слоёв из `nova-http` в эту репу — план 222 (раскол
утверждён 2026-07-24). До завершения извлечения содержимое `src/` неполно.

## Лицензия

MIT OR Apache-2.0.
