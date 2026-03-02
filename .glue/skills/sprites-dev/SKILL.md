---
name: sprites-dev
description: Use when user wants to run code in cloud sandboxes, spin up dev environments, deploy previews, or mentions Sprites, sprite boxes, or remote development. Manages sprite lifecycle, project deployment, and browser access.
---

# Sprites.dev Cloud Sandboxes

Sprites are persistent Ubuntu 24.04 cloud VMs with 100GB storage. They hibernate when idle and wake instantly on use. Pre-installed: Node.js, Python, Go, Ruby, Rust, Git, and dev tools.

## Prerequisites

Check if `sprite` CLI is installed:
```bash
which sprite
```

If not installed:
```bash
curl -fsSL https://sprites.dev/install.sh | sh
```

Check auth status:
```bash
sprite org list
```

If not authenticated, tell the user to run `sprite login` (opens browser for Fly.io auth). Do NOT run this automatically.

## State Tracking

Maintain a state file at `.glue/sprites-state.json` in the project root to track which sprites are associated with the project:

```json
{
  "sprites": {
    "sprite-name": {
      "purpose": "dev server for frontend",
      "created": "2026-03-02",
      "ports": {"8080": "vite dev server"},
      "public_url": true,
      "url": "https://sprite-name-xxxx.sprites.app"
    }
  }
}
```

Read this file at the start of any sprite operation. Update it after creating, destroying, or reconfiguring sprites. If the file doesn't exist, create it on first sprite creation.

## Quick Reference

| Task | Command |
|------|---------|
| Create sprite | `sprite create <name> -skip-console` |
| Set active | `sprite use <name>` |
| List sprites | `sprite list` |
| Run command | `sprite exec <cmd>` |
| Interactive shell | `sprite console` |
| Get public URL | `sprite url` |
| Make URL public | `sprite url update --auth public` |
| Forward port | `sprite proxy <local>:<remote>` |
| Destroy | `sprite destroy -s <name> -force` |
| Upload file | `sprite exec -file local.txt:/remote/path.txt echo done` |

## Common Workflows

### Deploy a project to a sprite

1. Create sprite: `sprite create <project>-dev -skip-console`
2. Set active: `sprite use <project>-dev`
3. Clone or upload code:
   ```bash
   sprite exec git clone <repo-url> /home/sprite/app
   ```
   Or upload files with `-file`:
   ```bash
   sprite exec -file ./package.json:/home/sprite/app/package.json -file ./src:/home/sprite/app/src echo "uploaded"
   ```
4. Install deps: `sprite exec -dir /home/sprite/app npm install`
5. Start server: `sprite exec -dir /home/sprite/app node server.js &` (or use services for persistence)
6. Make accessible: `sprite url update --auth public`
7. Get URL: `sprite url` (routes to port 8080 by default)
8. Update state file with the URL from step 7

### Open in browser

After making the URL public, open it locally:
```bash
open "$(sprite url 2>&1 | awk '/https:/{print $2}')"
```

### Port forwarding for local access

```bash
sprite proxy 3000          # forward remote 3000 to local 3000
sprite proxy 3001:3000     # forward remote 3000 to local 3001
sprite proxy 3000 5432     # forward multiple ports
```

### Persistent services (survive hibernation)

Services auto-restart when the sprite wakes:
```bash
sprite exec sprite-env services create my-server --cmd node --args server.js
```

Note: The `sprite-env` command runs INSIDE the sprite, not locally. Use it via `sprite exec`.

### Checkpoints (snapshots)

```bash
sprite checkpoint create                    # snapshot current state
sprite checkpoint create --comment "before upgrade"
sprite checkpoint list                      # list snapshots
sprite restore <checkpoint-id>              # rollback
```

### Sessions (detachable processes)

```bash
sprite exec -tty node server.js   # start TTY session (Ctrl+\ to detach)
sprite sessions list               # see running sessions
sprite sessions attach <id>        # reconnect
sprite sessions kill <id>          # terminate
```

## Networking

- Default URL routes to port **8080** inside the sprite
- URL format: `https://<sprite-name>-<hash>.sprites.app` (not predictable - always use `sprite url` to get it)
- Auth modes: `public` (open) or `default` (org members only)
- Use `sprite proxy` for non-8080 ports or local access

## Key Details

- **Filesystem persists** across hibernation (packages, files, git repos stay)
- **Processes do NOT persist** - use services for auto-restart on wake
- **Hibernation**: active -> warm (100-500ms wake) -> cold (1-2s wake)
- **Wake triggers**: any exec/console command, HTTP request, TCP connection
- Working dir flag: `sprite exec -dir /path/to/app <cmd>`
- Env vars: `sprite exec -env KEY=val,FOO=bar <cmd>`
- Target specific sprite: `sprite -s <name> exec <cmd>` or `sprite exec -s <name> <cmd>`
- Target specific org: `sprite -o <org> <cmd>`

## Per-Directory Config

Run `sprite use <name>` in a project directory to associate that sprite with it. Creates a `.sprite` file so all subsequent `sprite` commands in that directory target the right sprite.

## API (for advanced use via `sprite api`)

The `sprite api` command wraps curl with auth headers:
```bash
sprite api -o myorg /sprites                          # GET /v1/sprites
sprite api -o myorg -s mysprite /exec -X POST         # POST to sprite exec
sprite api -o myorg -s mysprite /checkpoints           # list checkpoints
```

When `-s` is set, paths are relative to `/v1/sprites/<name>/`. Without `-s`, paths are relative to `/v1/`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Auth failure | `sprite login` or `sprite org auth` |
| Sprite won't wake | Wait 30s, check `sprite list`, contact support |
| Port conflict | Use different local port: `sprite proxy 3001:3000` |
| Storage full | `sprite exec df -h`, clean up files |
| Process died after idle | Use services instead of bare processes |
