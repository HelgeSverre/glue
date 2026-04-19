<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

// ── Slim nav (replaces VitePress nav on homepage) ─────────────────────────
const navLinks = [
  { text: 'Docs',      href: '/docs/getting-started/installation' },
  { text: 'Models',    href: '/models' },
  { text: 'Features',  href: '/features' },
  { text: 'Roadmap',   href: '/roadmap' },
  { text: 'Changelog', href: '/changelog' },
]

// ── Hero terminal: animated playback of a real Claude Code session ────────
// Rendered to match Glue's actual TUI (block_renderer.dart):
//   ❯ You          bold blue   · user prompt
//   ◆ Glue         bold yellow · assistant
//   ▶ Tool: name   bold yellow · tool_call (+ args, + phase suffix)
//   ✓ Tool result  bold green  · tool_result  (✗ red on failure)
//   status bar     left: mode · right: model │ [approval] │ cwd │ tok N
//   ❯ prompt       yellow      · input line
//
// Script source: website/public/demo-script.json (curated + redacted from the
// real conversation that built this site).
type Phase = 'preparing' | 'awaitingApproval' | 'running' | 'done' | 'denied' | 'error'

interface ShotEvent {
  kind: 'user' | 'assistant' | 'tool_call' | 'tool_result' | 'system'
  text?: string
  name?: string
  args?: Record<string, unknown>
  phase?: Phase
  ok?: boolean
  delay?: number
}

interface ShotMeta {
  cwd: string
  model: string
  approval: string
  tokensStart: number
}

// Fallback script — shown if fetch fails (SSR / no network / offline build).
const fallbackEvents: ShotEvent[] = [
  { kind: 'user',        text: 'fetch task about redoing the website from backlog' },
  { kind: 'assistant',   text: 'Searching the backlog for a website task.' },
  { kind: 'tool_call',   name: 'backlog.task_search', args: { query: 'website docs' }, phase: 'running' },
  { kind: 'tool_result', ok: true, text: 'TASK-23 · Website redesign · 10 subtasks' },
  { kind: 'user',        text: 'see if the plan was deleted in git' },
  { kind: 'tool_call',   name: 'bash', args: { cmd: "git log --diff-filter=D -- 'docs/plans/*'" }, phase: 'running' },
  { kind: 'tool_result', ok: true, text: '(no output)' },
  { kind: 'assistant',   text: 'Referenced in the task but never committed.' },
]
const fallbackMeta: ShotMeta = {
  cwd: '~/code/glue',
  model: 'anthropic/claude-sonnet-4.6',
  approval: 'confirm',
  tokensStart: 12340,
}

const events = ref<ShotEvent[]>(fallbackEvents)
const meta = ref<ShotMeta>(fallbackMeta)
const visible = ref<number>(0)
const isRunning = ref<boolean>(false)
let timer: ReturnType<typeof setTimeout> | null = null

function defaultDelay(kind: ShotEvent['kind']): number {
  switch (kind) {
    case 'user':        return 760
    case 'assistant':   return 580
    case 'tool_call':   return 360
    case 'tool_result': return 320
    case 'system':      return 260
  }
}

function scheduleNext() {
  const i = visible.value
  if (i >= events.value.length) {
    timer = setTimeout(() => {
      visible.value = 0
      scheduleNext()
    }, 5200)
    return
  }
  const step = events.value[i]
  const d = step.delay ?? defaultDelay(step.kind)
  timer = setTimeout(() => {
    visible.value = i + 1
    scheduleNext()
  }, d)
}

const visibleEvents = computed(() => events.value.slice(0, visible.value))

// The next event about to land determines the mode indicator. User is "Ready",
// assistant streaming → "Generating", tool_call → "⚙ Tool", tool_result → pass.
const nextEvent = computed<ShotEvent | null>(() =>
  visible.value < events.value.length ? events.value[visible.value] : null
)

const spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
const spinnerFrame = ref<number>(0)
let spinnerTimer: ReturnType<typeof setInterval> | null = null

const modeLeft = computed<{ text: string; spinner: boolean }>(() => {
  if (!isRunning.value) return { text: 'Ready', spinner: false }
  const next = nextEvent.value
  if (!next) return { text: 'Ready', spinner: false }
  switch (next.kind) {
    case 'assistant':   return { text: 'Generating', spinner: true }
    case 'tool_call':   return { text: 'Tool',       spinner: true }
    case 'tool_result': return { text: 'Tool',       spinner: true }
    default:            return { text: 'Ready',      spinner: false }
  }
})

const tokenCount = computed(() => {
  const base = meta.value.tokensStart
  let bump = 0
  for (const ev of visibleEvents.value) {
    if (ev.kind === 'assistant' && ev.text) bump += Math.ceil(ev.text.length / 4)
    if (ev.kind === 'tool_result' && ev.text) bump += Math.ceil(ev.text.length / 6)
  }
  return base + bump
})

function formatTokens(n: number): string {
  return n.toLocaleString('en-US')
}

function formatArgs(args?: Record<string, unknown>): string {
  if (!args) return ''
  return Object.entries(args)
    .map(([k, v]) => `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`)
    .join(', ')
}

function phaseSuffix(phase: Phase | undefined): { text: string; cls: string } | null {
  switch (phase) {
    case 'preparing':       return { text: '(preparing…)',       cls: 'phase-prep' }
    case 'awaitingApproval':return { text: '(awaiting approval)',cls: 'phase-wait' }
    case 'running':         return { text: '(running…)',         cls: 'phase-run' }
    case 'denied':          return { text: '(denied)',           cls: 'phase-deny' }
    case 'error':           return { text: '(error)',            cls: 'phase-deny' }
    default:                return null
  }
}

async function loadScript() {
  try {
    const res = await fetch('/demo-script.json', { cache: 'no-store' })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    if (Array.isArray(data.events) && data.events.length > 0) {
      events.value = data.events
    }
    if (data.meta) {
      meta.value = { ...fallbackMeta, ...data.meta }
    }
  } catch {
    // keep fallback
  }
}

onMounted(async () => {
  const prefersReduced =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

  await loadScript()

  if (prefersReduced) {
    visible.value = events.value.length
    isRunning.value = false
    return
  }

  isRunning.value = true
  visible.value = 1
  scheduleNext()

  // Status-bar spinner — cycles regardless of event timer so it always feels
  // alive when the app is "thinking".
  spinnerTimer = setInterval(() => {
    spinnerFrame.value = (spinnerFrame.value + 1) % spinnerFrames.length
  }, 100)
})

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
  if (spinnerTimer) clearInterval(spinnerTimer)
  isRunning.value = false
})

// Auto-scroll the body as new events land so the latest output is in view.
const bodyRef = ref<HTMLElement | null>(null)
watch(visible, async () => {
  await Promise.resolve()
  const el = bodyRef.value
  if (!el) return
  el.scrollTop = el.scrollHeight
})

// Compact gutter for the inline demos in the "three moves" section below.
// The hero uses full Glue TUI blocks; these are denser by design.
type ScriptKind = 'prompt' | 'assistant' | 'tool' | 'output' | 'note'
function scriptGutter(kind: ScriptKind) {
  switch (kind) {
    case 'prompt':    return '›'
    case 'assistant': return ' '
    case 'tool':      return '⏵'
    case 'output':    return ' '
    case 'note':      return '#'
  }
}

// ── Featured moves ────────────────────────────────────────────────────────
const moves = [
  {
    num: '01',
    title: 'Edit with intent.',
    blurb:
      'Rename a helper across the repo, convert a test fixture, patch multiple files in one go. Every edit lands in the transcript as a diff summary.',
    steps: [
      { kind: 'prompt',    text: 'rename withRetry → retryable across the repo' },
      { kind: 'tool',      text: 'grep  withRetry  cli/lib/' },
      { kind: 'output',    text: '14 hits in 7 files' },
      { kind: 'tool',      text: 'edit  7 files · +14 −14' },
      { kind: 'assistant', text: 'Renamed. Tests still compile.' },
    ],
  },
  {
    num: '02',
    title: 'Run in a sandbox.',
    blurb:
      'Risky install? Untrusted script? Spin up an ephemeral Docker container, mount the workspace, run it there. The container goes away with the session.',
    steps: [
      { kind: 'prompt',    text: 'install the suspicious npm tarball and check for network calls' },
      { kind: 'output',    text: 'runtime · docker · ubuntu:24.04' },
      { kind: 'tool',      text: 'run   npm i ./odd-pkg.tgz' },
      { kind: 'output',    text: 'added 42 packages · 0 vulnerabilities' },
      { kind: 'assistant', text: 'No outbound calls on install. Runtime calls on import.' },
    ],
  },
  {
    num: '03',
    title: 'Resume anything.',
    blurb:
      'Every session is an append-only JSONL log on your machine. Stop mid-task, come back tomorrow, pick up exactly where you left off. No hosted service, no account, no upload.',
    steps: [
      { kind: 'prompt',    text: 'glue --resume 1740654600000-abc' },
      { kind: 'output',    text: 'resumed · 142 events · last: 2h ago' },
      { kind: 'assistant', text: 'Picking up where we left off — 3 tests still red.' },
      { kind: 'tool',      text: 'run   dart test test/shell/' },
      { kind: 'output',    text: '✓ all tests passing' },
    ],
  },
]

// ── Runtime ladder ────────────────────────────────────────────────────────
const runtimes = [
  { label: 'host',   status: 'shipping', line: 'your shell, your machine' },
  { label: 'docker', status: 'shipping', line: 'ephemeral container · workspace mounted' },
  { label: 'cloud',  status: 'planned',  line: 'e2b · modal · daytona · ssh workers' },
]

// ── Providers ─────────────────────────────────────────────────────────────
const providers = [
  { id: 'anthropic',  model: 'claude-sonnet-4.6',   tag: 'default' },
  { id: 'openai',     model: 'gpt-5.4',             tag: 'hosted' },
  { id: 'gemini',     model: 'gemini-pro-latest',   tag: 'hosted' },
  { id: 'mistral',    model: 'codestral-latest',    tag: 'hosted' },
  { id: 'groq',       model: 'qwen/qwen3-coder',    tag: 'hosted' },
  { id: 'ollama',     model: 'qwen2.5-coder:32b',   tag: 'local' },
  { id: 'openrouter', model: 'any route',           tag: 'hosted' },
]

const jsonlSample = [
  `{"t":"10:30:00.000Z","type":"user_message","text":"explain retry logic"}`,
  `{"t":"10:30:00.510Z","type":"tool_call","name":"read","args":{"path":"http_client.dart"}}`,
  `{"t":"10:30:00.630Z","type":"tool_result","content":"…"}`,
  `{"t":"10:30:01.900Z","type":"assistant_message","text":"Exponential backoff with jitter."}`,
  `{"t":"10:30:02.120Z","type":"title_generated","title":"HTTP client retry walkthrough"}`,
]
</script>

<template>
  <main class="home">
    <!-- ─── Slim nav ──────────────────────────────────────────────────── -->
    <header class="topbar">
      <div class="wrap topbar-inner">
        <a class="brand" href="/" aria-label="Glue home">
          <img class="brand-mark" src="/brand/symbol-yellow.svg" alt="" width="24" height="24" />
          <span class="brand-name">Glue</span>
        </a>
        <nav class="nav" aria-label="Primary">
          <a
            v-for="link in navLinks"
            :key="link.href"
            :href="link.href"
            class="nav-link"
          >{{ link.text }}</a>
          <a
            href="https://github.com/helgesverre/glue"
            class="nav-link nav-github"
            aria-label="GitHub"
          >GitHub ↗</a>
        </nav>
      </div>
    </header>

    <!-- ─── Hero (2 cols) ─────────────────────────────────────────────── -->
    <section class="hero">
      <div class="wrap hero-grid">
        <div class="hero-copy">
          <div class="eyebrow">glue · terminal-native coding agent</div>

          <h1 class="headline">
            A small terminal agent for <span class="accent">real coding work.</span>
          </h1>

          <p class="sub">
            Edits files. Runs tools. Keeps resumable sessions. Stays on your machine —
            or jumps into Docker when the work gets risky.
          </p>

          <div class="install">
            <InstallSnippet />
          </div>

          <div class="actions">
            <a class="btn btn-primary" href="/docs/getting-started/quick-start">Quick start →</a>
            <a class="btn btn-ghost" href="/why">Why Glue</a>
          </div>

          <div class="meta">
            <span><code>anthropic</code> · <code>openai</code> · <code>gemini</code> · <code>ollama</code></span>
            <span class="meta-sep">·</span>
            <span>host · docker · <span class="meta-planned">cloud</span></span>
          </div>
        </div>

        <figure class="shot" aria-label="Glue in a coding session">
          <div class="shot-frame">
            <div class="shot-tab">
              <span class="shot-tab-dot" />
              <span class="shot-tab-title">glue — {{ meta.cwd }}</span>
            </div>

            <div ref="bodyRef" class="shot-body">
              <template v-for="(ev, i) in visibleEvents" :key="i">

                <!-- user: ❯ You (bold blue) + indented body -->
                <div v-if="ev.kind === 'user'" class="tui-block tui-user">
                  <div class="tui-head"><span class="glyph glyph-blue">❯</span> You</div>
                  <div class="tui-body">{{ ev.text }}</div>
                </div>

                <!-- assistant: ◆ Glue (bold yellow) + body -->
                <div v-else-if="ev.kind === 'assistant'" class="tui-block tui-assistant">
                  <div class="tui-head"><span class="glyph glyph-accent">◆</span> Glue</div>
                  <div class="tui-body">{{ ev.text }}</div>
                </div>

                <!-- tool_call: ▶ Tool: name (+ phase) + args line -->
                <div v-else-if="ev.kind === 'tool_call'" class="tui-block tui-tool">
                  <div class="tui-head">
                    <span class="glyph glyph-accent">▶</span>
                    Tool: <span class="tool-name">{{ ev.name }}</span>
                    <span
                      v-if="phaseSuffix(ev.phase)"
                      class="phase"
                      :class="phaseSuffix(ev.phase)!.cls"
                    >
                      {{ phaseSuffix(ev.phase)!.text }}
                    </span>
                  </div>
                  <div v-if="ev.args && Object.keys(ev.args).length > 0" class="tui-args">
                    {{ formatArgs(ev.args) }}
                  </div>
                </div>

                <!-- tool_result: ✓ / ✗ Tool result + body -->
                <div v-else-if="ev.kind === 'tool_result'" class="tui-block tui-result">
                  <div class="tui-head">
                    <span
                      class="glyph"
                      :class="ev.ok === false ? 'glyph-danger' : 'glyph-success'"
                    >{{ ev.ok === false ? '✗' : '✓' }}</span>
                    Tool result
                  </div>
                  <pre class="tui-body tui-body-pre">{{ ev.text }}</pre>
                </div>

                <!-- system: gray leading line -->
                <div v-else-if="ev.kind === 'system'" class="tui-block tui-system">
                  {{ ev.text }}
                </div>

              </template>
            </div>

            <!-- Glue's status bar: left mode, right model │ [approval] │ cwd │ tok N -->
            <div class="shot-status">
              <span class="status-left">
                <span v-if="modeLeft.spinner" class="status-spinner">{{ spinnerFrames[spinnerFrame] }}</span>
                <span v-else class="status-ready-dot" />
                <span class="status-mode">{{ modeLeft.text }}</span>
              </span>
              <span class="status-right">
                <span>{{ meta.model }}</span>
                <span class="status-sep">│</span>
                <span>[{{ meta.approval }}]</span>
                <span class="status-sep">│</span>
                <span>{{ meta.cwd }}</span>
                <span class="status-sep">│</span>
                <span>tok {{ formatTokens(tokenCount) }}</span>
              </span>
            </div>

            <!-- Input line: ❯ yellow prompt + blinking cursor -->
            <div class="shot-input">
              <span class="input-prompt">❯</span>
              <span class="input-caret" aria-hidden="true" />
            </div>
          </div>
        </figure>
      </div>
    </section>

    <!-- ─── Loop ──────────────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">the loop</div>
        <h2 class="display">
          Ask → inspect → edit → run → verify.
        </h2>
        <p class="lede">
          Nothing hidden. Every step lands in the transcript in order — so you
          can stop, scroll, and challenge anything Glue did.
        </p>
      </div>
    </section>

    <!-- ─── Three moves ───────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">three moves, over and over</div>
      </div>

      <article v-for="move in moves" :key="move.num" class="move">
        <div class="wrap move-inner">
          <div class="move-copy">
            <div class="move-num">{{ move.num }}</div>
            <h3 class="move-title">{{ move.title }}</h3>
            <p class="move-blurb">{{ move.blurb }}</p>
          </div>
          <div class="move-script">
            <div
              v-for="(step, i) in move.steps"
              :key="i"
              class="script-line"
              :class="`line-${step.kind}`"
            >
              <span class="script-gutter" aria-hidden="true">{{ scriptGutter(step.kind as ScriptKind) }}</span>
              <span class="script-text">{{ step.text }}</span>
            </div>
          </div>
        </div>
      </article>
    </section>

    <!-- ─── Runtimes ──────────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">run it where it belongs</div>
        <h2 class="display">Host. Docker. Cloud.</h2>
        <p class="lede">
          Same agent, different backstops. Swap between them per session when
          you want a clean environment.
        </p>

        <ul class="ladder">
          <li
            v-for="rt in runtimes"
            :key="rt.label"
            class="rung"
            :data-status="rt.status"
          >
            <span class="rung-label">{{ rt.label }}</span>
            <span class="rung-line">{{ rt.line }}</span>
            <FeatureStatus :status="(rt.status as 'shipping' | 'planned')" />
          </li>
        </ul>

        <p class="more"><a href="/runtimes">Runtime capability matrix →</a></p>
      </div>
    </section>

    <!-- ─── Providers ─────────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">bring your models</div>
        <h2 class="display">Curated providers. No picker-zoo.</h2>
        <p class="lede">
          Seven providers bundled, a default per profile, and an
          <code>adapter: openai</code> escape hatch for any compatible endpoint.
          Credentials stay out of project config.
        </p>

        <ul class="providers">
          <li
            v-for="p in providers"
            :key="p.id"
            class="provider"
            :data-tag="p.tag"
          >
            <span class="provider-id"><code>{{ p.id }}/{{ p.model }}</code></span>
            <span class="provider-tag">{{ p.tag }}</span>
          </li>
        </ul>

        <p class="more"><a href="/models">Full model catalog →</a></p>
      </div>
    </section>

    <!-- ─── Sessions ──────────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">sessions you can grep</div>
        <h2 class="display">Every run is a file you own.</h2>
        <p class="lede">
          Append-only JSONL under <code>~/.glue/sessions/</code>. No hosted
          dashboard. No telemetry upload. <code>tail&nbsp;-f</code> works.
        </p>

        <pre class="jsonl"><code v-for="(line, i) in jsonlSample" :key="i">{{ line }}
</code></pre>

        <p class="more"><a href="/sessions">How sessions work →</a></p>
      </div>
    </section>

    <!-- ─── CTA ───────────────────────────────────────────────────────── -->
    <section class="section section-divider section-cta">
      <div class="wrap cta">
        <h2 class="display">
          Install it. Run <code class="cta-run">glue</code>.
        </h2>
        <div class="cta-install"><InstallSnippet /></div>
        <div class="actions">
          <a class="btn btn-primary" href="/docs/getting-started/quick-start">Quick start →</a>
          <a class="btn btn-ghost" href="/features">Feature list</a>
        </div>
      </div>
    </section>
  </main>
</template>

<style scoped>
/* ── Base ──────────────────────────────────────────────────────────────── */
.home {
  --fg:     var(--vp-c-text-1);
  --fg-dim: var(--vp-c-text-2);
  --fg-3:   var(--vp-c-text-3);
  --div:    var(--vp-c-divider);
  --accent: var(--glue-accent);

  font-family: var(--vp-font-family-base);
  color: var(--fg);
}

.home :deep(a) {
  text-decoration: none;
}

.home :deep(code) {
  font-family: var(--vp-font-family-mono);
  background: transparent;
  padding: 0;
  color: inherit;
  font-size: 0.92em;
}

.wrap {
  max-width: 1320px;
  margin: 0 auto;
  padding: 0 2rem;
}

@media (max-width: 720px) {
  .wrap { padding: 0 1.25rem; }
}

.section {
  padding: 6rem 0;
}

@media (max-width: 720px) {
  .section { padding: 4rem 0; }
}

.section-divider {
  border-top: 1px solid var(--div);
}

.kicker {
  font-family: var(--vp-font-family-mono);
  font-size: 0.74rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--fg-3);
  margin-bottom: 1.5rem;
}

.display {
  font-size: clamp(2.25rem, 4.8vw, 3.75rem);
  line-height: 1.04;
  letter-spacing: -0.025em;
  font-weight: 600;
  margin: 0 0 1.25rem;
}

.lede {
  max-width: 640px;
  color: var(--fg-dim);
  font-size: clamp(1.02rem, 1.25vw, 1.15rem);
  line-height: 1.55;
  margin: 0;
}

.more {
  margin-top: 2rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.88rem;
}

.more a {
  color: var(--accent);
  border-bottom: 1px dashed color-mix(in srgb, var(--accent) 40%, transparent);
  padding-bottom: 2px;
}

.more a:hover {
  border-bottom-style: solid;
}

/* ── Topbar (slim homepage nav) ───────────────────────────────────────── */
.topbar {
  position: sticky;
  top: 0;
  z-index: 20;
  padding: 0.9rem 0;
  background: color-mix(in srgb, var(--vp-c-bg) 85%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border-bottom: 1px solid transparent;
  transition: border-color 150ms ease;
}

.topbar-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 2rem;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--fg);
  font-family: var(--vp-font-family-base);
  font-size: 1.05rem;
  font-weight: 600;
  letter-spacing: normal;
}

.brand-mark {
  width: 24px;
  height: 24px;
  display: block;
}

.brand-name {
  color: var(--fg);
}

.nav {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.nav-link {
  font-family: var(--vp-font-family-base);
  font-size: 0.93rem;
  font-weight: 500;
  color: var(--fg-dim);
  transition: color 120ms ease;
}

.nav-link:hover {
  color: var(--fg);
}

.nav-github {
  font-family: var(--vp-font-family-mono);
  font-size: 0.88rem;
}

@media (max-width: 560px) {
  .nav { gap: 0.85rem; font-size: 0.85rem; }
  .nav-link { font-size: 0.85rem; }
  .nav-github { display: none; }
}

/* ── Hero (2 cols) ────────────────────────────────────────────────────── */
.hero {
  padding: 5rem 0 6rem;
}

.hero-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.05fr);
  gap: 4rem;
  align-items: center;
}

@media (max-width: 1040px) {
  .hero-grid { grid-template-columns: 1fr; gap: 2.5rem; }
}

.eyebrow {
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  letter-spacing: 0.12em;
  color: var(--fg-3);
  margin-bottom: 1.75rem;
}

.eyebrow::before {
  content: '◆';
  color: var(--accent);
  margin-right: 0.5rem;
}

.headline {
  font-size: clamp(2.5rem, 5.5vw, 4.75rem);
  line-height: 1;
  letter-spacing: -0.03em;
  font-weight: 600;
  margin: 0 0 1.75rem;
}

.accent {
  color: var(--accent);
}

.sub {
  font-size: clamp(1.05rem, 1.35vw, 1.2rem);
  line-height: 1.5;
  color: var(--fg-dim);
  max-width: 560px;
  margin: 0 0 2rem;
  font-weight: 400;
}

.install {
  max-width: 540px;
  margin: 0 0 1.5rem;
}

.actions {
  display: flex;
  gap: 0.65rem;
  flex-wrap: wrap;
}

.meta {
  margin-top: 1.75rem;
  display: flex;
  gap: 0.6rem;
  flex-wrap: wrap;
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  color: var(--fg-3);
}

.meta code {
  color: var(--fg-dim);
}

.meta-sep {
  opacity: 0.5;
}

.meta-planned {
  color: var(--fg-3);
  font-style: italic;
}

/* ── Buttons ──────────────────────────────────────────────────────────── */
.btn {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.7rem 1.2rem;
  border-radius: 6px;
  font-size: 0.95rem;
  font-weight: 600;
  transition: background 120ms ease, color 120ms ease, border-color 120ms ease;
  color: var(--fg);
}

.btn-primary {
  background: var(--accent);
  color: #0A0A0B;
}

.btn-primary:hover {
  background: #fde047;
}

.btn-ghost {
  border: 1px solid var(--div);
  background: transparent;
}

.btn-ghost:hover {
  border-color: var(--accent);
  color: var(--accent);
}

/* ── Hero screenshot — matches Glue's real TUI (block_renderer.dart) ──── */
.shot {
  margin: 0;
  min-width: 0;
}

.shot-frame {
  background: var(--glue-term-bg);
  color: var(--glue-term-fg);
  border: 1px solid var(--div);
  border-radius: 10px;
  overflow: hidden;
  box-shadow:
    0 20px 50px -20px rgba(0,0,0,0.55),
    0 1px 0 0 color-mix(in srgb, #ffffff 5%, transparent) inset;
  display: grid;
  grid-template-rows: auto 1fr auto auto;
  font-family: var(--vp-font-family-mono);
}

/* Terminal-tab style title row */
.shot-tab {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.55rem 0.9rem;
  background: #141416;
  border-bottom: 1px solid #1e1e21;
  font-size: 0.72rem;
  color: var(--glue-term-dim);
}
.shot-tab-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--accent);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 15%, transparent);
}
.shot-tab-title {
  letter-spacing: 0.01em;
}

/* Transcript body */
.shot-body {
  padding: 0.75rem 0.25rem 1rem;
  font-size: 13px;
  line-height: 1.65;
  height: 24em;
  overflow-y: auto;
  scroll-behavior: smooth;
  scrollbar-width: thin;
  scrollbar-color: #2a2b2e transparent;
}
.shot-body::-webkit-scrollbar { width: 6px; }
.shot-body::-webkit-scrollbar-thumb { background: #2a2b2e; border-radius: 3px; }

/* Each TUI block reserves a 1-char left margin matching Glue's ` ` prefix. */
.tui-block {
  padding: 0 0.75rem 0 0.85rem;
  margin-bottom: 0.5rem;
  animation: tui-appear 220ms ease-out both;
}

@keyframes tui-appear {
  from { opacity: 0; transform: translateY(3px); }
  to   { opacity: 1; transform: translateY(0); }
}

.tui-head {
  font-weight: 700;
}

.tui-body,
.tui-body-pre {
  margin: 0;
  padding-left: 2ch;               /* matches Glue's `   ` / `    ` indent */
  color: var(--glue-term-fg);
  white-space: pre-wrap;
  word-break: break-word;
  font-family: var(--vp-font-family-mono);
  font-size: inherit;
  line-height: inherit;
  background: transparent;
}

.tui-body-pre {
  color: var(--glue-term-dim);
}

/* Role-specific colours — match block_renderer.dart headers. */
.tui-user .tui-head      { color: #3B82F6; }          /* bold blue  */
.tui-assistant .tui-head { color: var(--accent); }    /* bold yellow */
.tui-tool .tui-head      { color: var(--accent); }    /* bold yellow */
.tui-result .tui-head    { /* ok/danger handled by glyph class */ }
.tui-system              { color: var(--glue-term-dim); }

.glyph {
  display: inline-block;
  margin-right: 0.25rem;
}
.glyph-blue    { color: #3B82F6; }
.glyph-accent  { color: var(--accent); }
.glyph-success { color: var(--glue-success); }
.glyph-danger  { color: var(--glue-error); }

.tui-result .tui-head { color: var(--glue-success); }
.tui-result .tui-head:has(.glyph-danger) { color: var(--glue-error); }

.tool-name {
  font-weight: 700;
}

.tui-args {
  padding-left: 4ch;                /* Glue uses a 4-space indent for args */
  color: var(--glue-term-dim);
  white-space: pre-wrap;
  word-break: break-word;
}

.phase {
  margin-left: 0.4rem;
  font-weight: 500;
}
.phase-prep { color: var(--glue-term-dim); }
.phase-wait { color: var(--accent); }
.phase-run  { color: #22D3EE; }     /* cyan, matches Glue's `\x1b[36m` */
.phase-deny { color: var(--glue-error); }

@media (prefers-reduced-motion: reduce) {
  .tui-block { animation: none; }
}

/* Status bar — Glue's bottom line, left mode · right model │ [approval] │ cwd │ tok N */
.shot-status {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.4rem 0.75rem;
  border-top: 1px solid #1e1e21;
  background: #0c0c0e;
  font-size: 0.72rem;
  color: var(--glue-term-dim);
  white-space: nowrap;
  overflow: hidden;
}

.status-left {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--glue-term-fg);
  font-weight: 600;
}

.status-spinner {
  color: var(--accent);
  display: inline-block;
  width: 1ch;
  text-align: center;
}

.status-ready-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--glue-success);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--glue-success) 18%, transparent);
}

.status-mode {
  color: var(--glue-term-fg);
}

.status-right {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--glue-term-dim);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}

.status-sep {
  opacity: 0.45;
  color: var(--glue-term-dim);
}

/* Input zone — ❯ prompt + blinking cursor */
.shot-input {
  padding: 0.55rem 0.9rem 0.65rem;
  border-top: 1px solid #1e1e21;
  background: #0c0c0e;
  font-size: 13px;
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.input-prompt {
  color: var(--accent);
  font-weight: 700;
}

.input-caret {
  display: inline-block;
  width: 0.6em;
  height: 1.05em;
  background: var(--accent);
  animation: tui-caret-blink 1s steps(1) infinite;
}

@keyframes tui-caret-blink {
  50% { opacity: 0; }
}

@media (prefers-reduced-motion: reduce) {
  .input-caret { animation: none; }
}

/* ── Moves (stacked, generous whitespace) ─────────────────────────────── */
.move {
  padding: 4rem 0;
  border-top: 1px solid var(--div);
}

.move:first-of-type {
  border-top: none;
}

.move-inner {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.1fr);
  gap: 3rem;
  align-items: start;
}

@media (max-width: 860px) {
  .move-inner { grid-template-columns: 1fr; gap: 2rem; }
}

.move-num {
  font-family: var(--vp-font-family-mono);
  font-size: 0.85rem;
  color: var(--accent);
  letter-spacing: 0.1em;
  margin-bottom: 0.75rem;
}

.move-title {
  font-size: clamp(1.75rem, 3vw, 2.25rem);
  line-height: 1.1;
  letter-spacing: -0.02em;
  font-weight: 600;
  margin: 0 0 1rem;
}

.move-blurb {
  color: var(--fg-dim);
  font-size: 1.05rem;
  line-height: 1.6;
  margin: 0;
  max-width: 42ch;
}

.move-script {
  font-family: var(--vp-font-family-mono);
  font-size: 0.92rem;
  line-height: 1.8;
}

.script-line {
  display: grid;
  grid-template-columns: 1.4em 1fr;
  gap: 0.6rem;
  color: var(--fg-dim);
}

.script-gutter {
  color: var(--fg-3);
  user-select: none;
  text-align: right;
}

.line-prompt    { color: var(--fg); font-weight: 500; }
.line-prompt .script-gutter { color: var(--accent); }

.line-assistant { color: var(--fg); }

.line-tool      { color: var(--fg-dim); }
.line-tool .script-gutter { color: var(--accent); opacity: 0.7; }

.line-output    { color: var(--fg-3); }

.line-group     { color: var(--fg-3); font-style: italic; }
.line-group .script-gutter { color: var(--fg-3); }

/* ── Runtime ladder ───────────────────────────────────────────────────── */
.ladder {
  list-style: none;
  padding: 0;
  margin: 2.5rem 0 0;
  display: grid;
  gap: 0;
}

.rung {
  display: grid;
  grid-template-columns: minmax(8rem, 14rem) 1fr auto;
  gap: 1.5rem;
  align-items: baseline;
  padding: 1.5rem 0;
  border-top: 1px solid var(--div);
}

.rung:last-child {
  border-bottom: 1px solid var(--div);
}

.rung[data-status='planned'] .rung-label,
.rung[data-status='planned'] .rung-line {
  color: var(--fg-3);
}

.rung-label {
  font-family: var(--vp-font-family-mono);
  font-size: clamp(1.3rem, 2.2vw, 1.8rem);
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--fg);
}

.rung-line {
  font-family: var(--vp-font-family-mono);
  font-size: 0.95rem;
  color: var(--fg-dim);
}

@media (max-width: 640px) {
  .rung {
    grid-template-columns: 1fr auto;
    gap: 0.5rem;
  }
  .rung-line { grid-column: 1 / -1; }
}

/* ── Providers ────────────────────────────────────────────────────────── */
.providers {
  list-style: none;
  padding: 0;
  margin: 2.5rem 0 0;
  display: grid;
  gap: 0;
}

.provider {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 1.5rem;
  align-items: baseline;
  padding: 1rem 0;
  border-top: 1px solid var(--div);
}

.provider:last-child {
  border-bottom: 1px solid var(--div);
}

.provider-id {
  font-family: var(--vp-font-family-mono);
  font-size: clamp(0.95rem, 1.35vw, 1.1rem);
  color: var(--fg);
}

.provider-tag {
  font-family: var(--vp-font-family-mono);
  font-size: 0.72rem;
  letter-spacing: 0.12em;
  color: var(--fg-3);
  text-transform: uppercase;
}

.provider[data-tag='default'] .provider-tag { color: var(--accent); }
.provider[data-tag='local']   .provider-tag { color: var(--glue-success); }

/* ── JSONL ────────────────────────────────────────────────────────────── */
.jsonl {
  margin: 2.5rem 0 0;
  padding: 0;
  font-family: var(--vp-font-family-mono);
  font-size: 0.82rem;
  line-height: 1.85;
  color: var(--fg-dim);
  overflow-x: auto;
}

.jsonl code {
  display: block;
  white-space: pre;
}

/* ── CTA ──────────────────────────────────────────────────────────────── */
.section-cta {
  padding: 7rem 0 8rem;
}

.cta {
  text-align: center;
}

.cta .display {
  margin: 0 auto 2rem;
}

.cta-run {
  color: var(--accent);
}

.cta-install {
  max-width: 560px;
  margin: 0 auto 1.75rem;
}

.cta .actions {
  justify-content: center;
}
</style>
