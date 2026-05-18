---
pageClass: page-marketing
title: Runtimes
description: Where Glue runs work — your host, an ephemeral Docker container, or a remote cloud sandbox on Daytona, Sprites, or Modal.
sidebar: false
aside: false
outline: false
---

# Runtimes

Glue runs commands through a `CommandExecutor` + `Workspace` abstraction
chosen at startup by the `RuntimeFactory`. Today that's your host shell, an
ephemeral Docker container, or one of three cloud sandboxes — Daytona,
Sprites (Fly.io), or Modal.

Canonical source: [`docs/reference/runtime-capabilities.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/runtime-capabilities.yaml).

## The ladder

<div class="ladder">
<code>host</code> → <code>Docker</code> → <code>Daytona</code> / <code>Sprites</code> / <code>Modal</code>
</div>

- **Host** <FeatureStatus status="shipping" /> — fastest; uses your tools, your env.
- **Docker** <FeatureStatus status="shipping" /> — ephemeral containers for risky or messy work. Sandbox polish is <FeatureStatus status="experimental" />.
- **Daytona** <FeatureStatus status="shipping" /> — clean REST API; per-sandbox toolbox URL discovered automatically; US + EU regions.
- **Sprites** <FeatureStatus status="shipping" /> — persistent Fly.io sandbox driven via the `sprite` CLI; auto-sleeps when idle, resumes by name.
- **Modal** <FeatureStatus status="shipping" /> — Modal sandbox via an embedded Python sidecar; sandbox auto-terminates on a configurable timeout to cap billing.

## Capability matrix

<RuntimeMatrix
  caption="What each runtime can do today. Cloud-provided browsers + session artifacts are tracked separately."
  :capabilities="['command_capture','command_streaming','background_jobs','filesystem_read','filesystem_write','mount_host_paths','browser_cdp','artifacts','secrets','snapshots','internet','gpu']"
  :rows="[
    {
      runtime: 'host',
      status: 'shipping',
      notes: 'Runs in your shell on your machine.',
      capabilities: {
        command_capture: 'yes',
        command_streaming: 'yes',
        background_jobs: 'yes',
        filesystem_read: 'yes',
        filesystem_write: 'yes',
        mount_host_paths: 'yes',
        browser_cdp: 'partial',
        artifacts: 'yes',
        secrets: 'no',
        snapshots: 'no',
        internet: 'yes',
        gpu: 'yes',
      },
    },
    {
      runtime: 'docker',
      status: 'shipping',
      notes: 'Ephemeral container; workspace mounted in.',
      capabilities: {
        command_capture: 'yes',
        command_streaming: 'yes',
        background_jobs: 'partial',
        filesystem_read: 'yes',
        filesystem_write: 'yes',
        mount_host_paths: 'yes',
        browser_cdp: 'partial',
        artifacts: 'yes',
        secrets: 'no',
        snapshots: 'no',
        internet: 'yes',
        gpu: 'partial',
      },
    },
    {
      runtime: 'daytona',
      status: 'shipping',
      notes: 'REST API; workspace bootstrapped via git clone into /workspace.',
      capabilities: {
        command_capture: 'yes',
        command_streaming: 'yes',
        background_jobs: 'yes',
        filesystem_read: 'yes',
        filesystem_write: 'yes',
        mount_host_paths: 'no',
        browser_cdp: 'planned',
        artifacts: 'planned',
        secrets: 'no',
        snapshots: 'yes',
        internet: 'yes',
        gpu: 'planned',
      },
    },
    {
      runtime: 'sprites',
      status: 'shipping',
      notes: 'Persistent Fly.io sprite via `sprite` CLI; auto-sleeps when idle.',
      capabilities: {
        command_capture: 'yes',
        command_streaming: 'yes',
        background_jobs: 'yes',
        filesystem_read: 'yes',
        filesystem_write: 'yes',
        mount_host_paths: 'no',
        browser_cdp: 'planned',
        artifacts: 'planned',
        secrets: 'no',
        snapshots: 'yes',
        internet: 'yes',
        gpu: 'planned',
      },
    },
    {
      runtime: 'modal',
      status: 'shipping',
      notes: 'Modal sandbox via embedded Python sidecar; capped by sandbox_timeout_seconds.',
      capabilities: {
        command_capture: 'yes',
        command_streaming: 'yes',
        background_jobs: 'yes',
        filesystem_read: 'yes',
        filesystem_write: 'yes',
        mount_host_paths: 'no',
        browser_cdp: 'planned',
        artifacts: 'planned',
        secrets: 'no',
        snapshots: 'no',
        internet: 'yes',
        gpu: 'planned',
      },
    },
  ]"
/>

## Choosing a runtime

- **Default to host.** Fastest feedback loop, direct access to your tools.
- **Switch to Docker** when you're about to run code you haven't audited —
  third-party dependency installs, generated scripts, anything grabbing
  network resources you don't recognize. The container goes away when the
  session ends.
- **Reach for a cloud runtime** when the work shouldn't touch your host at
  all — scraping at volume, suspicious artifacts, long-running agent jobs,
  or workflows that need to keep state between sessions:
  - **Daytona** — clean REST API, fast to spin up, persistent FS, US + EU
    regions, snapshot-based. Best general-purpose cloud sandbox.
  - **Sprites** — persistent Fly.io VM. Resumes by name; auto-sleeps when
    idle so you only pay for active wall-clock. Great when one named
    sandbox should outlive several glue sessions.
  - **Modal** — runs inside a real Modal App, so you can reuse the same
    image and Python deps your other Modal functions use. Sandbox
    auto-terminates on `sandbox_timeout_seconds` — cheap insurance against
    runaway billing.

## Configuring runtimes

Pick a runtime with `runtime:` in `~/.glue/config.yaml`, then add the
matching per-runtime block. `GLUE_RUNTIME` and per-adapter env vars
override config values.

### Docker

<ConfigSnippet title="~/.glue/config.yaml — Docker">

```yaml
runtime: docker
docker:
  enabled: true
  image: ubuntu:24.04
  shell: sh
  fallback_to_host: true
  mounts:
    - /abs/path/to/workspace
```

</ConfigSnippet>

`fallback_to_host: true` keeps the session usable if Docker isn't running
locally — the executor drops back to host with a visible notice instead of
failing.

<p><a href="/docs/using-glue/docker-sandbox">Docker sandbox guide →</a></p>

### Daytona

<ConfigSnippet title="~/.glue/config.yaml — Daytona">

```yaml
runtime: daytona
daytona:
  api_key: env:DAYTONA_API_KEY
  # api_base_url: https://app-eu.daytona.io/api   # EU region; defaults to US
  # snapshot: my-snapshot-id                       # org default if omitted
```

</ConfigSnippet>

Set `DAYTONA_API_KEY` in your environment. Glue calls the control plane to
create a sandbox, discovers the per-sandbox `toolboxProxyUrl` from the
create response, and uses it for every exec / FS call after that.

<p><a href="/docs/using-glue/daytona">Daytona guide →</a></p>

### Sprites

<ConfigSnippet title="~/.glue/config.yaml — Sprites">

```yaml
runtime: sprites
sprites:
  # sprite_name: my-sandbox      # reuse a named sprite across sessions
  # delete_on_close: false       # keep the sprite after the session (auto-sleeps)
```

</ConfigSnippet>

Requires the `sprite` CLI on `$PATH` and `sprite login` once. Glue
generates a unique sprite name per session unless `sprite_name` is set.

<p><a href="/docs/using-glue/sprites">Sprites guide →</a></p>

### Modal

<ConfigSnippet title="~/.glue/config.yaml — Modal">

```yaml
runtime: modal
modal:
  app_name: glue
  # image: python:3.12-slim
  sandbox_timeout_seconds: 1800
```

</ConfigSnippet>

Requires `modal` on `$PATH`, the Python `modal` package importable, and
`modal token set` run once. The sandbox auto-terminates after
`sandbox_timeout_seconds` even if glue exits uncleanly — caps runaway
billing.

<p><a href="/docs/using-glue/modal">Modal guide →</a></p>

<style scoped>
.ladder {
  font-family: var(--vp-font-family-mono);
  font-size: 0.95rem;
  padding: 0.65rem 1rem;
  background: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-divider);
  border-radius: 6px;
  display: inline-block;
}

.ladder code {
  background: transparent;
  padding: 0;
}
</style>
