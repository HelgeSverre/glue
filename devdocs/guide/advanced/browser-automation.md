# Browser Automation

The `web_browser` tool automates a browser via Chrome DevTools Protocol. The browser session persists across calls, so the agent can navigate, interact, and extract data across multiple steps.

## Available Actions

The browser tool supports the following actions: `navigate`, `screenshot`, `click`, `type`, `extract_text`, and `evaluate`.

## Backends

Glue supports five browser backends:

| Backend | Description |
|---|---|
| `local` | Uses a locally installed Chrome or Chromium |
| `docker` | Runs headless Chrome inside a Docker container |
| `browserbase` | Cloud browser via Browserbase API |
| `browserless` | Cloud browser via Browserless API |
| `steel` | Cloud browser via Steel API |

## Configuration

Configure the browser backend and behavior in your `glue.yaml`:

```yaml
web:
  browser:
    backend: "local"            # local | docker | browserbase | browserless | steel
    headed: false
```

::: tip
Use `headed: true` during development to watch the browser interact with pages in real time. This only applies to the `local` backend.
:::

::: info
Cloud backends (`browserbase`, `browserless`, `steel`) require API keys configured in their respective environment variables or config sections.
:::

## See also

- [WebBrowserTool](/api/tools/web-browser-tool)
- [BrowserManager](/api/web/browser-manager)
- [BrowserConfig](/api/web/browser-config)
