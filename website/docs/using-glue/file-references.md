# File References

Type `@` in your message to open a fuzzy file picker. Selected files are expanded inline into your prompt, wrapped in fenced code blocks with syntax highlighting.

## Usage

```bash
# Fuzzy search across the project
❯ Refactor @auth_middleware     # opens autocomplete

# Browse a specific directory
❯ Review @lib/src/routes/       # lists files in that dir

# Paths with spaces
❯ Check @"my project/config.yaml"
```

## How It Works

- **Fuzzy matching** -- exact matches rank first, then prefix matches, then substrings.
- **Directory browsing** -- type `@dir/` to list contents of a directory.
- **Language detection** -- files get syntax tags based on extension (`.dart`, `.ts`, `.py`, `.rs`, etc.).
- **Smart expansion** -- content is wrapped in fenced code blocks, backtick-aware.

## Limits

| Limit                            | Value     |
| -------------------------------- | --------- |
| Max file size for expansion      | 100 KB    |
| Max tree entries in autocomplete | 2,000     |
| Max directory depth scanned      | 3 levels  |
| Autocomplete cache TTL           | 2 seconds |

::: warning
Files larger than 100 KB are skipped during expansion. Split large files or reference specific sections instead.
:::

## See also

- [FileExpander](/api/input/file-expander)
