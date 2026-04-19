# Troubleshooting

Common issues and how to work around them. This page is growing —
open an issue on GitHub if you hit something that isn't covered here.

## The CLI can't find my credentials

Glue looks for credentials in this order:

1. Environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
   `MISTRAL_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, etc.)
2. `~/.glue/credentials.json`
3. A keychain integration (planned)

Double-check the env var name matches the provider exactly. `glue --debug`
prints the resolution order at startup.

## Docker runtime falls back to host

If you set `docker.enabled: true` but the session runs on the host, look for
a notice in the status bar. Common causes:

- Docker Desktop isn't running.
- The image in `docker.image` isn't pulled yet — run `docker pull <image>`.
- The path in `docker.mounts` doesn't exist.

With `docker.fallback_to_host: true`, Glue drops back to host instead of
refusing to start. Set `fallback_to_host: false` to fail loudly instead.

## The model I want isn't in the catalog

The bundled catalog is curated. To add a model:

- Drop `models.yaml` into `~/.glue/` with your provider/model entry. It
  merges on top of the bundled catalog.
- Or use `adapter: openai` with `base_url` pointing at any
  OpenAI-compatible endpoint.

See [Models and Providers](/docs/using-glue/models-and-providers).

## My session file looks weird

Sessions are append-only JSONL. A partial last line means the CLI crashed
mid-event — the rest of the file is still valid. You can safely re-open
the session.

If `meta.json` is missing but `conversation.jsonl` exists, the session is
effectively orphaned — move or delete the directory.

## Tools hang waiting for approval

The default approval mode is `confirm`. Every untrusted tool asks before
running. Set `approval_mode: auto` in `~/.glue/config.yaml` if you want
Glue to run tools without prompting (use sparingly).

## Filing an issue

- Include the `glue --version` output.
- Include the relevant lines from `conversation.jsonl` (redact any
  secrets first).
- Note which runtime you're using (host, Docker).
