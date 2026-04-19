---
pageClass: page-marketing
title: Runtimes
description: Where Glue runs work — your host, an ephemeral Docker container, or (planned) a remote cloud runtime.
sidebar: false
aside: false
outline: false
---

# Runtimes

Glue runs commands through a `CommandExecutor` abstraction. Today that's your
host shell or an ephemeral Docker container. Cloud runtimes are planned — see
the runtime boundary plan in the repo for details.

Canonical source: [`docs/reference/runtime-capabilities.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/runtime-capabilities.yaml).

## The ladder

<div class="ladder">
<code>host</code> → <code>Docker</code> → <code>cloud</code> <FeatureStatus status="planned" />
</div>

- **Host** <FeatureStatus status="shipping" /> — fastest; uses your tools, your env.
- **Docker** <FeatureStatus status="shipping" /> — ephemeral containers for risky or messy work. Sandbox polish is <FeatureStatus status="experimental" />.
- **Cloud** <FeatureStatus status="planned" /> — E2B, Modal, Daytona, custom SSH or container workers. Tracked by the runtime boundary plan.

## Capability matrix

<RuntimeMatrix
  caption="What each runtime can do today. Cloud runtimes land when the plan is implemented."
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
      runtime: 'cloud',
      status: 'planned',
      notes: 'E2B, Modal, Daytona, SSH, or custom workers.',
      capabilities: {
        command_capture: 'planned',
        command_streaming: 'planned',
        background_jobs: 'planned',
        filesystem_read: 'planned',
        filesystem_write: 'planned',
        mount_host_paths: 'no',
        browser_cdp: 'planned',
        artifacts: 'planned',
        secrets: 'planned',
        snapshots: 'planned',
        internet: 'planned',
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
- **Cloud runtimes** are planned for workloads that shouldn't touch your host
  at all: scraping at volume, suspicious artifacts, long-running or
  GPU-heavy agent work.

## Enabling Docker

<ConfigSnippet title="~/.glue/config.yaml — enable Docker sandbox">

```yaml
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
