# 09 — graceful

Гибкие ручки `ServerPolicy`, `BackgroundTasks`, запускающиеся после того,
как ответ уже на проводе, и честный взгляд на то, что «graceful» здесь
покрывает сегодня, а что нет.

По мотивам: примеры `graceful-shutdown` + `key-value-store` из axum.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18090
```

```sh
curl http://localhost:18090/health   # ok
curl http://localhost:18090/policy
# defaults: max_inflight=16 reject_with_503=true max_requests_per_conn=100 max_body_bytes=1048576
# tuned:    max_inflight=64 max_body_bytes=4194304

curl http://localhost:18090/log      # (empty -- hit /work first)
curl http://localhost:18090/work     # queued 1 background task(s)
curl http://localhost:18090/log      # background task ran
```

Ответ `/work` уходит клиенту ДО того, как выполнится очередная задача —
`/log` показывает эффект задачи только на СЛЕДУЮЩЕМ запросе, доказательство,
что работа реально произошла после записи в провод, а не до.

## Что здесь реально, а что нет (прочитай это)

- **`BackgroundTasks`** полностью реальны и живы: собственный драйвер
  соединения `serve_router` (`polaris.net.serve_connection`) вызывает
  `@drain()` сразу после записи байтов ответа
  (см. [`docs/serving.ru.md`](../../docs/serving.ru.md#фоновые-задачи)).
- Ручки **`ServerPolicy`** (admission control `max_inflight`, дедлайны,
  `max_body_bytes`) здесь тоже реальны и живы: `/policy` выше СТРОИТ и ЧИТАЕТ
  отдельное значение только для печати, но `main()` ниже подключает ТУ ЖЕ
  настроенную политику (`max_inflight(64)`) в настоящий accept-цикл
  `serve_router` — так что отчёт `/policy` — это ровно то, что управляет
  живым сокетом, а не просто иллюстрация.
- **recover-500** (пойманная паника хендлера, отвечающая `500` по
  `policy.panic_response()`) точно так же жив через тот же accept-цикл
  `serve_router`/`serve_connection`, который крутит `main()` этого примера.
- **Graceful shutdown** (дожидание фоновых задач в полёте при завершении
  процесса) НИГДЕ в Polaris пока не реализован — см.
  [`docs/roadmap.ru.md`](../../docs/roadmap.ru.md#graceful-shutdown-фоновых-задач).
  Имя этого примера совпадает с пунктом канон-списка плана; он не
  претендует на несуществующую функцию дожидания при завершении.

## Связанная документация

- [`docs/serving.ru.md`](../../docs/serving.ru.md) — `ServerPolicy`, accept-цикл, фоновые задачи, потоки
- [`docs/roadmap.ru.md`](../../docs/roadmap.ru.md) — что запланировано, но не реализовано (graceful shutdown и другое)

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
