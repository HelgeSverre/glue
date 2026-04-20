<!-- Generated from docs/reference/runtime-capabilities.yaml. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

# Runtime capability matrix

Source: [`docs/reference/runtime-capabilities.yaml`](https://github.com/helgesverre/glue/blob/main/docs/reference/runtime-capabilities.yaml)

## Capabilities

| Capability | Meaning |
| --- | --- |
| `command_capture` | Run a command and capture its stdout/stderr/exit code. |
| `command_streaming` | Stream output back to the TUI as it happens. |
| `background_jobs` | Start long-running processes that outlive one tool call. |
| `filesystem_read` | Read files the agent has access to. |
| `filesystem_write` | Write or edit files the agent has access to. |
| `mount_host_paths` | Mount local directories into the runtime. |
| `browser_cdp` | Run a headless browser reachable by the agent. |
| `artifacts` | Produce files the user can retrieve after the session. |
| `secrets` | Provide per-runtime secret storage separate from the host. |
| `snapshots` | Snapshot and restore runtime state between sessions. |
| `internet` | Outbound internet access from inside the runtime. |
| `gpu` | Access to GPU devices. |

## Matrix

| Runtime | Status | Notes | `command_capture` | `command_streaming` | `background_jobs` | `filesystem_read` | `filesystem_write` | `mount_host_paths` | `browser_cdp` | `artifacts` | `secrets` | `snapshots` | `internet` | `gpu` |
| --- | --- | --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `host` | shipping | Runs in the user's shell on the user's machine. | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ◐ | ✓ | — | — | ✓ | ✓ |
| `docker` | shipping | Ephemeral container with the workspace mounted; sandbox polish is experimental. | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | ◐ | ✓ | — | — | ✓ | ◐ |
| `cloud` | planned | Remote runtimes — E2B, Modal, Daytona, custom SSH or container workers. | ◌ | ◌ | ◌ | ◌ | ◌ | — | ◌ | ◌ | ◌ | ◌ | ◌ | ◌ |

Legend: `✓` yes · `◐` partial · `◌` planned · `—` no

