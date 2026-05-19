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
- The image in `docker.image` isn't pulled yet — run `docker pull &lt;image&gt;`.
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

## Cloud runtime failed to bootstrap

Daytona, Sprites, and Modal sandboxes have to clone or upload your repo
before the agent can work. When that step fails, Glue classifies the error
(via `BootstrapErrorKind`) and prints a remediation hint instead of a bare
exit code. Common kinds:

| Kind            | What it means                                                                       | What to try                                                                                  |
| --------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `auth`          | The sandbox couldn't authenticate to your git remote (401, missing token).          | Use the bundle bootstrap path (don't rely on sandbox-side credentials), or set up an HTTPS token. |
| `saml`          | SSO/SAML enforcement rejected the token.                                            | Authorise the token for the org in your SSO provider.                                        |
| `network`       | DNS / connect timeout / proxy block reaching the remote from the sandbox.           | Check the sandbox's outbound network policy; retry.                                          |
| `missingBinary` | `git` (or another required helper) isn't on `PATH` inside the sandbox image.        | Use a base image that includes git, or switch runtimes.                                      |
| `prep`          | Workspace prep (`mkdir` / `chown`) failed in the sandbox.                           | Usually transient — retry; otherwise file an issue.                                          |
| `upload`        | Uploading the host-side bundle to the sandbox failed.                               | See "Bundle exceeds upload cap" below.                                                       |
| `cloneBundle`   | The uploaded bundle couldn't be cloned inside the sandbox.                          | Re-run; if it persists, check that your local `git` produces a valid bundle.                 |
| `checkout`      | `git checkout &lt;sha&gt;` failed inside the sandbox.                                     | Make sure the commit is reachable (committed, not just staged) before starting.              |

## Bundle exceeds upload cap

The bundle bootstrap path packs your working tree into a `git bundle` and
ships it to the sandbox. Each runtime has its own per-call upload cap:

| Runtime   | Bundle cap |
| --------- | ---------- |
| Daytona   | 200 MB     |
| Modal     | 30 MB      |
| Sprites   | 3 MB       |

If your bundle exceeds the cap, the bootstrap fails with `upload` /
`cloneBundle`. Workarounds: trim large binaries / `node_modules` /
`.venv` from the tree, commit and push so the sandbox can clone from the
remote instead, or switch to a runtime with a larger cap.

## `glue session apply` conflicts

When you apply a captured session patch back to your host workspace, the
`git am --3way` (or fallback `git apply --3way`) step can hit conflicts —
typically because your host moved on while the agent was working in the
sandbox. Glue surfaces `.rej` files for the offending hunks:

```
git am and git apply both failed. Inspect rejections or apply manually:
  rejection: /path/to/file.dart.rej
```

Options:

- Apply to a clean checkout instead: `git worktree add /tmp/review HEAD`
  then `glue session apply &lt;id&gt; --target /tmp/review`.
- Pick a different base: `glue session apply &lt;id&gt; --branch glue/&lt;id&gt;`
  creates a fresh branch from current `HEAD`; the default name is the same.
- Inspect first: `glue session show &lt;id&gt;` for metadata, `glue session diff
  &lt;id&gt;` for the full patch.

See [Session patches](/docs/using-glue/session-patches) for the full
workflow.

## Tools hang waiting for approval

The default approval mode is `confirm`. Every untrusted tool asks before
running. Set `approval_mode: auto` in `~/.glue/config.yaml` if you want
Glue to run tools without prompting (use sparingly).

## Filing an issue

- Include the `glue --version` output.
- Include the relevant lines from `conversation.jsonl` (redact any
  secrets first).
- Note which runtime you're using (host, Docker).
