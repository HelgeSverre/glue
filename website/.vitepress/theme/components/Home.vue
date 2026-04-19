<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

// ── Hero: auto-cycling script shown as plain lines (no fake window) ───────
interface Step {
  kind: 'prompt' | 'assistant' | 'tool' | 'output'
  text: string
  delay?: number
}

const heroScript: Step[] = [
  { kind: 'prompt',    text: 'explain the retry logic in http_client.dart' },
  { kind: 'assistant', text: 'Reading the file and the tests around it.' },
  { kind: 'tool',      text: 'read  cli/lib/src/web/http_client.dart' },
  { kind: 'tool',      text: 'grep  retry  cli/test/' },
  { kind: 'output',    text: '3 matches in http_client_test.dart' },
  { kind: 'assistant', text: 'Exponential backoff with jitter, capped at 5 attempts.' },
  { kind: 'prompt',    text: 'add a retry for ECONNRESET' },
  { kind: 'tool',      text: 'edit  cli/lib/src/web/http_client.dart · +4 −0' },
  { kind: 'tool',      text: 'run   dart test test/web/http_client_test.dart' },
  { kind: 'output',    text: '✓ 12 tests passed' },
]

const visible = ref<number>(0)
let timer: ReturnType<typeof setTimeout> | null = null

function schedule() {
  const i = visible.value
  if (i >= heroScript.length) {
    timer = setTimeout(() => {
      visible.value = 0
      schedule()
    }, 4500)
    return
  }
  const step = heroScript[i]
  const baseDelay = step.delay ?? (step.kind === 'output' ? 260 : step.kind === 'tool' ? 340 : 620)
  timer = setTimeout(() => {
    visible.value = i + 1
    schedule()
  }, baseDelay)
}

function gutter(kind: Step['kind']) {
  switch (kind) {
    case 'prompt':    return '›'
    case 'assistant': return ' '
    case 'tool':      return '⏵'
    case 'output':    return ' '
  }
}

onMounted(() => {
  const prefersReduced =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  if (prefersReduced) {
    visible.value = heroScript.length
    return
  }
  visible.value = 1
  schedule()
})

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
})

// ── Featured moves (stacked, not cards) ───────────────────────────────────
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
    <!-- ─── Hero ──────────────────────────────────────────────────────── -->
    <section class="hero">
      <div class="wrap">
        <div class="eyebrow">glue · terminal-native coding agent</div>

        <h1 class="headline">
          A small terminal agent for<br />
          <span class="accent">real coding work.</span>
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
          <a class="btn btn-ghost" href="https://github.com/helgesverre/glue">GitHub ↗</a>
        </div>
      </div>
    </section>

    <!-- ─── Live script ───────────────────────────────────────────────── -->
    <section class="section">
      <div class="wrap">
        <div class="script" aria-label="Glue interactive session">
          <div
            v-for="(step, i) in heroScript.slice(0, visible)"
            :key="i"
            class="script-line"
            :class="`line-${step.kind}`"
          >
            <span class="script-gutter" aria-hidden="true">{{ gutter(step.kind) }}</span>
            <span class="script-text">{{ step.text }}</span>
          </div>
          <div v-if="visible < heroScript.length" class="script-caret" aria-hidden="true" />
        </div>
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

    <!-- ─── Three moves (stacked) ─────────────────────────────────────── -->
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
              <span class="script-gutter" aria-hidden="true">{{ gutter(step.kind as Step['kind']) }}</span>
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
  font-feature-settings: "ss01", "ss02";
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
  max-width: 1040px;
  margin: 0 auto;
  padding: 0 1.75rem;
}

.section {
  padding: 6rem 0;
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

/* ── Hero ──────────────────────────────────────────────────────────────── */
.hero {
  padding: 8rem 0 5rem;
}

.eyebrow {
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  letter-spacing: 0.12em;
  color: var(--fg-3);
  margin-bottom: 2rem;
}

.eyebrow::before {
  content: '◆';
  color: var(--accent);
  margin-right: 0.5rem;
}

.headline {
  font-size: clamp(2.75rem, 7vw, 5.75rem);
  line-height: 1;
  letter-spacing: -0.035em;
  font-weight: 600;
  margin: 0 0 1.75rem;
  max-width: 14ch;
}

.accent {
  color: var(--accent);
}

.sub {
  font-size: clamp(1.1rem, 1.6vw, 1.35rem);
  line-height: 1.5;
  color: var(--fg-dim);
  max-width: 620px;
  margin: 0 0 2.25rem;
  font-weight: 400;
}

.install {
  max-width: 560px;
  margin: 0 0 1.75rem;
}

.actions {
  display: flex;
  gap: 0.65rem;
  flex-wrap: wrap;
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

/* ── Script (no window chrome — just monospace lines) ─────────────────── */
.script {
  font-family: var(--vp-font-family-mono);
  font-size: clamp(0.88rem, 1.2vw, 1.02rem);
  line-height: 1.75;
  letter-spacing: 0.005em;
  color: var(--fg-dim);
  min-height: 16em;
}

.script-line {
  display: grid;
  grid-template-columns: 1.4em 1fr;
  gap: 0.6rem;
  animation: fade-in 200ms ease-out both;
}

@keyframes fade-in {
  from { opacity: 0; transform: translateY(2px); }
  to   { opacity: 1; transform: translateY(0); }
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

.script-caret {
  display: inline-block;
  width: 0.55em;
  height: 1.05em;
  margin-left: 2em;
  background: var(--accent);
  animation: blink 1s steps(1) infinite;
  vertical-align: text-bottom;
}

@keyframes blink {
  50% { opacity: 0; }
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

/* ── Providers (clean list, no cards) ─────────────────────────────────── */
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

/* ── JSONL (plain pre) ────────────────────────────────────────────────── */
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

@media (prefers-reduced-motion: reduce) {
  .script-caret,
  .script-line {
    animation: none;
  }
}
</style>
