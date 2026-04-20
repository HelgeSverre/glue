# Browser Automation

The `web_browser` tool drives a real browser over the Chrome DevTools Protocol.
The session persists across calls, so an agent can navigate, interact, and
extract across multiple tool invocations.

<FeatureStatus status="experimental" /> The CDP-backed browser tool works
today; some provider integrations are newer than others. See the
*Status per backend* column below.

## Supported backends

Glue ships with seven browser backends today. Each implements the same
`BrowserEndpointProvider` interface (`cli/lib/src/web/browser/providers/`) —
picking one is a config change, not a code change.

| Backend        | Where it runs                             | Status                              | Best for                                                   |
| -------------- | ----------------------------------------- | ----------------------------------- | ---------------------------------------------------------- |
| `local`        | Your machine · Puppeteer-launched Chrome  | <FeatureStatus status="shipping" /> | Quick iteration. `headed: true` lets you watch it work.    |
| `docker`       | Local container (`browserless/chrome`)    | <FeatureStatus status="shipping" /> | Isolation from your host without leaving your machine.     |
| `browserbase`  | Cloud · [browserbase.com](https://browserbase.com) | <FeatureStatus status="experimental" /> | Hosted sessions with session replays.               |
| `browserless`  | Cloud or self-hosted · [browserless.io](https://browserless.io) | <FeatureStatus status="experimental" /> | Cheap scale-out; self-hostable. |
| `steel`        | Cloud · [steel.dev](https://steel.dev)    | <FeatureStatus status="experimental" /> | Agent-focused cloud sessions.                       |
| `anchor`       | Cloud · [anchorbrowser.io](https://anchorbrowser.io) | <FeatureStatus status="experimental" /> | Agentic browser sessions with live view and managed automation features. |
| `hyperbrowser` | Cloud · [hyperbrowser.ai](https://hyperbrowser.ai) | <FeatureStatus status="experimental" /> | Agent-focused cloud sessions with fast launches and a live view. |

## Available actions

The tool exposes a small, stable surface: `navigate`, `screenshot`, `click`,
`type`, `extract_text`, and `evaluate`. Actions run against the current
session so a single prompt can chain steps.

## Configuration

Configure the backend under `web.browser` in `~/.glue/config.yaml`.

### `local` — local Chrome or Chromium

```yaml
web:
  browser:
    backend: local
    headed: false     # set true to watch the browser interact live
```

### `docker` — headless Chrome in a container

```yaml
web:
  browser:
    backend: docker
    docker:
      image: browserless/chrome:latest
      port: 3000
```

The container is ephemeral: one per session, torn down when the session
closes. No state leaks into your host.

### `browserbase` — cloud via Browserbase

```yaml
web:
  browser:
    backend: browserbase
    browserbase:
      api_key: your-key
      project_id: your-project
```

### `browserless` — cloud or self-hosted

```yaml
web:
  browser:
    backend: browserless
    browserless:
      api_key: your-key
      base_url: https://chrome.browserless.io
```

Point `browserless.base_url` at your own deployment to self-host.

### `steel` — cloud via Steel

```yaml
web:
  browser:
    backend: steel
    steel:
      api_key: your-key
```

### `anchor` — cloud via Anchor Browser

```yaml
web:
  browser:
    backend: anchor
    anchor:
      api_key: your-key
```

### `hyperbrowser` — cloud via Hyperbrowser

```yaml
web:
  browser:
    backend: hyperbrowser
    hyperbrowser:
      api_key: your-key
```

::: info Credentials
Cloud backends need an API key. Prefer env vars or
[`~/.glue/credentials.json`](/docs/getting-started/configuration#credentials-json-api-keys)
over writing keys into `config.yaml`.
:::

## Pairing with runtimes

For risky or noisy browsing, pair the browser backend with a runtime that
doesn't touch your host:

| Goal                              | Runtime + backend                                   |
| --------------------------------- | --------------------------------------------------- |
| Develop an automation quickly     | `host` runtime + `local` browser (`headed: true`)   |
| Untrusted site inspection         | `docker` runtime + `docker` browser                 |
| High-volume scraping              | <FeatureStatus status="planned" /> cloud runtime + cloud browser |
| Agent-driven multi-step workflows | Any runtime + `steel`, `browserbase`, `anchor`, or `hyperbrowser` |

## Providers we're evaluating

More backend options are tracked in the backlog — see
[TASK-28: Evaluate and add new browser-automation providers](https://github.com/helgesverre/glue/blob/main/backlog/tasks/task-28%20-%20Evaluate-and-add-browser-automation-providers.md).
Next up: a first-party platform browser (Cloudflare Browser Rendering) and
a residential-proxy scraping backend (Bright Data Scraping Browser).

## See also

- [WebBrowserTool](/api/tools/web-browser-tool)
- [BrowserManager](/api/web/browser-manager)
- [BrowserConfig](/api/web/browser-config)
- [Web Tools overview](/web)
- [Runtimes](/runtimes)
