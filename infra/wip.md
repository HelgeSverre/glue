# Observability Toolbox WIP

All URLs below use the current compose project name: `glue-observability`.

## 11 New Tools Added

| Tool          | Compose Profile  | Local URL                                                        | OrbStack URL                                                                                             | Default Login                       | Auth Disabled? | Notes                                                                               |
| ------------- | ---------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| LLMFlow       | `tool-llmflow`   | `http://localhost:8899`                                          | `http://llmflow.glue-observability.orb.local:8899`                                                       | none                                | yes            | Local flow/debug UI.                                                                |
| Helicone      | `tool-helicone`  | `http://localhost:8585` (gateway), `http://localhost:8989` (web) | `http://helicone.glue-observability.orb.local:8585`, `http://helicone.glue-observability.orb.local:8989` | create account on first run (web)   | partial        | Gateway has no auth; web login is enabled.                                          |
| Langfuse      | `tool-langfuse`  | `http://localhost:3002`                                          | `http://langfuse.glue-observability.orb.local:3002`                                                      | `helge.sverre@gmail.com` / `123456` | no             | Bootstrapped via `LANGFUSE_INIT_*`.                                                 |
| Opik          | `tool-opik`      | `http://localhost:5179`                                          | `http://opik-frontend.glue-observability.orb.local:5179`                                                 | none (local default)                | yes            | Full local stack (mysql/redis/clickhouse/minio + backend/frontend).                 |
| Arize Phoenix | `tool-phoenix`   | `http://localhost:6006`                                          | `http://phoenix.glue-observability.orb.local:6006`                                                       | none                                | yes            | `PHOENIX_ENABLE_AUTH=false`.                                                        |
| OpenLIT       | `tool-openlit`   | `http://localhost:3011`                                          | `http://openlit.glue-observability.orb.local:3011`                                                       | none                                | yes            | Out-of-box local UI.                                                                |
| Dozzle        | `tool-dozzle`    | `http://localhost:8088`                                          | `http://dozzle.glue-observability.orb.local:8088`                                                        | none                                | yes            | Live Docker log viewer (`DOCKER_SOCKET_PATH` is OrbStack-ready in `.dockerconfig`). |
| Netdata       | `tool-netdata`   | `http://localhost:19999`                                         | `http://netdata.glue-observability.orb.local:19999`                                                      | none                                | yes            | Node/container metrics dashboard.                                                   |
| Pyroscope     | `tool-pyroscope` | `http://localhost:4040`                                          | `http://pyroscope.glue-observability.orb.local:4040`                                                     | none                                | yes            | Continuous profiling UI.                                                            |
| MLflow        | `tool-mlflow`    | `http://localhost:5000`                                          | `http://mlflow.glue-observability.orb.local:5000`                                                        | none                                | yes            | MLflow Tracking Server for LLM experiment tracking.                                 |
| Seq           | `tool-seq`       | `http://localhost:8082`                                          | `http://seq.glue-observability.orb.local:8082`                                                           | none (default local)                | yes            | Log/event UI, OTLP/ingest endpoints available.                                      |

## Product Hunt Radar (recent)

These were included/considered as recent PH-adjacent picks for AI observability/dev tooling:

- Langfuse: https://www.producthunt.com/products/langfuse
- Helicone: https://www.producthunt.com/products/helicone
- TensorZero (watchlist, not added): https://www.producthunt.com/posts/tensorzero
- Unify (watchlist, not added): https://www.producthunt.com/products/unify-4

## Existing Tool Login Update

| Tool        | Local URL               | OrbStack URL                                           | Default Login                       |
| ----------- | ----------------------- | ------------------------------------------------------ | ----------------------------------- |
| OpenObserve | `http://localhost:5080` | `http://openobserve.glue-observability.orb.local:5080` | `helge.sverre@gmail.com` / `123456` |

## Useful Commands

```bash
cd infra
cp -n .dockerconfig.example .dockerconfig

# Base stack
just up

# All new tools
just up-extras

# One tool profile at a time
just up-tool llmflow
just up-tool langfuse
just up-tool opik

# Plus llm proxy profile
just up-llm
```
