# Infra: Local Observability + LLM Proxy

This stack runs entirely with Docker Compose from `infra/` and gives you:

- **One OTLP endpoint** for Glue (`otel-collector:4318`)  
- **Fan-out to 5 trace destinations** at once:
  1. Jaeger
  2. Grafana Tempo
  3. Zipkin
  4. OpenObserve
  5. Aspire Dashboard
- Optional **LiteLLM proxy** for API-key centralization + routing/cost controls.

## Quick Start

```bash
cd infra
cp .dockerconfig.example .dockerconfig
just up
```

Optional (includes LiteLLM):

```bash
just up-llm
```

## URLs

- OTEL Collector health: `http://localhost:13133/`
- Jaeger UI: `http://localhost:16686`
- Zipkin UI: `http://localhost:9411`
- Tempo API: `http://localhost:3200`
- Grafana: `http://localhost:3001` (default `admin` / `admin`)
- OpenObserve: `http://localhost:5080`
- Aspire Dashboard: `http://localhost:18888`
- LiteLLM proxy (optional): `http://localhost:4000`

## Glue Configuration

Point Glue OTEL to the Collector:

```yaml
telemetry:
  otel:
    enabled: true
    endpoint: http://localhost:4318/v1/traces
```

Your current Glue OTEL sink already emits valid OTLP JSON payloads to an HTTP endpoint, so no code change is needed.

## Optional Langfuse

Glue already has a native Langfuse sink. Keep both enabled if you want:

- OTEL -> Collector fan-out (this stack)
- Langfuse sink -> Langfuse endpoint directly

This gives you generic OTEL tooling plus dedicated LLM trace views.

## Optional LiteLLM Usage

This stack includes a LiteLLM profile for key management and budget/routing policies.
Fill provider keys in `.dockerconfig` and start with `just up-llm`.

Current Glue config uses provider-native base URLs for OpenAI/Anthropic/Mistral, so routing through LiteLLM would require either:

1. a Glue config option for provider base URLs, or
2. a small adapter mode in Glue to target LiteLLM’s OpenAI-compatible endpoint.

## Commands

```bash
just up         # start observability stack
just up-llm     # start observability + litellm profile
just ps
just logs
just down
```

