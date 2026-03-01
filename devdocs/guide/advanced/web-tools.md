# Web Tools

Glue includes web-oriented tools for fetching pages and searching the web. All are configured under the `web:` block in your config.

## web_fetch

Fetches a URL and returns its content as clean markdown. The pipeline:

1. **HTML pages** — extracts main content, strips boilerplate, converts to markdown
2. **PDF documents** — extracts text directly; if the result is empty (scanned PDF), falls back to OCR via Mistral or OpenAI vision

Optional Jina AI fallback for difficult pages when `JINA_API_KEY` is set.

## web_search

Searches the web and returns structured results. Three providers:

| Provider     | API Key Env Var     |
| ------------ | ------------------- |
| Brave Search | `BRAVE_API_KEY`     |
| Tavily       | `TAVILY_API_KEY`    |
| Firecrawl    | `FIRECRAWL_API_KEY` |

If no explicit provider is configured, Glue auto-detects the first available provider by checking which API key is set.

## Configuration

```yaml
web:
  fetch:
    timeout_seconds: 30
    max_bytes: 5242880
    allow_jina_fallback: true

  search:
    provider: "brave" # brave | tavily | firecrawl
    max_results: 10

  pdf:
    enable_ocr_fallback: true
    ocr_provider: "mistral" # mistral | openai
```

## See also

- [WebFetchTool](/api/tools/web-fetch-tool)
- [WebSearchTool](/api/tools/web-search-tool)
- [WebFetchClient](/api/web/web-fetch-client)
- [SearchRouter](/api/web/search-router)
- [WebConfig](/api/web/web-config)
