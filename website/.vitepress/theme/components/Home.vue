<script setup lang="ts">
// ── Slim nav (replaces VitePress nav on homepage) ─────────────────────────
const navLinks = [
  { text: 'Docs',      href: '/docs/getting-started/installation' },
  { text: 'Models',    href: '/models' },
  { text: 'Runtimes',  href: '/runtimes' },
  { text: 'Changelog', href: '/changelog' },
]

// ── Hero screenshot: a realistic Glue session ─────────────────────────────
// Shown as an illustrative product shot. Not a live demo — stable copy,
// readable at a glance, balanced for the 2-col hero.
interface ShotLine {
  kind: 'prompt' | 'assistant' | 'tool' | 'output' | 'group'
  text: string
}

const shot: ShotLine[] = [
  { kind: 'prompt',    text: 'explain the retry logic in http_client.dart' },
  { kind: 'assistant', text: 'Reading the file and tests around it.' },
  { kind: 'group',     text: 'tool group · 3 calls · 210ms' },
  { kind: 'tool',      text: 'read  cli/lib/src/web/http_client.dart' },
  { kind: 'tool',      text: 'grep  retry  cli/test/' },
  { kind: 'output',    text: '3 matches in http_client_test.dart' },
  { kind: 'assistant', text: 'Exponential backoff with jitter, capped at 5 attempts.' },
  { kind: 'prompt',    text: 'add a retry for ECONNRESET' },
  { kind: 'tool',      text: 'edit  cli/lib/src/web/http_client.dart · +4 −0' },
  { kind: 'tool',      text: 'run   dart test test/web/http_client_test.dart' },
  { kind: 'output',    text: '✓ 12 tests passed' },
]

function gutter(kind: ShotLine['kind']) {
  switch (kind) {
    case 'prompt':    return '›'
    case 'assistant': return ' '
    case 'tool':      return '⏵'
    case 'output':    return ' '
    case 'group':     return '⌄'
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
          <span class="brand-mark" aria-hidden="true">◆</span>
          <span class="brand-name">glue</span>
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
            <div class="shot-head">
              <span class="shot-path">
                <span class="shot-path-dim">~/code/glue</span>
                <span class="shot-path-sep">/</span>
                <span>cli/lib/src/web/http_client.dart</span>
              </span>
              <span class="shot-branch">
                <span class="shot-branch-glyph" aria-hidden="true">⎇</span>
                main · clean
              </span>
            </div>

            <div class="shot-body">
              <div
                v-for="(line, i) in shot"
                :key="i"
                class="shot-line"
                :class="`shot-${line.kind}`"
              >
                <span class="shot-gutter" aria-hidden="true">{{ gutter(line.kind) }}</span>
                <span class="shot-text">{{ line.text }}</span>
              </div>
            </div>

            <div class="shot-foot">
              <span class="shot-foot-item">
                <span class="shot-dot shot-dot-ok" aria-hidden="true" />
                anthropic/claude-sonnet-4.6
              </span>
              <span class="shot-foot-sep">│</span>
              <span class="shot-foot-item">runtime: host</span>
              <span class="shot-foot-sep">│</span>
              <span class="shot-foot-item">approval: confirm</span>
              <span class="shot-foot-spacer" />
              <span class="shot-foot-item shot-foot-dim">142 events</span>
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
              <span class="script-gutter" aria-hidden="true">{{ gutter(step.kind as ShotLine['kind']) }}</span>
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
  align-items: baseline;
  gap: 0.5rem;
  color: var(--fg);
  font-family: var(--vp-font-family-mono);
  font-size: 0.98rem;
  font-weight: 600;
  letter-spacing: 0.005em;
}

.brand-mark {
  color: var(--accent);
  font-size: 0.9em;
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

/* ── Hero screenshot (illustrative) ──────────────────────────────────── */
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
  grid-template-rows: auto 1fr auto;
}

.shot-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.7rem 1rem;
  border-bottom: 1px solid #1e1e21;
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  color: var(--glue-term-dim);
  background: #111113;
  gap: 1rem;
}

.shot-path {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.shot-path-dim {
  color: var(--fg-3);
  opacity: 0.75;
}

.shot-path-sep {
  color: var(--fg-3);
  margin: 0 0.1rem;
}

.shot-branch {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  color: var(--fg-3);
  white-space: nowrap;
}

.shot-branch-glyph {
  color: var(--accent);
  font-weight: 600;
}

.shot-body {
  padding: 1.1rem 1.3rem 1.3rem;
  font-family: var(--vp-font-family-mono);
  font-size: 13.5px;
  line-height: 1.75;
  min-height: 22em;
  overflow: hidden;
}

.shot-line {
  display: grid;
  grid-template-columns: 1.4em 1fr;
  gap: 0.6rem;
}

.shot-gutter {
  color: var(--glue-term-dim);
  user-select: none;
  text-align: center;
}

.shot-prompt    { color: var(--glue-term-fg); font-weight: 500; }
.shot-prompt .shot-gutter { color: var(--accent); }

.shot-assistant { color: var(--glue-term-fg); }

.shot-tool      { color: #a6a6a6; }
.shot-tool .shot-gutter { color: var(--accent); opacity: 0.7; }

.shot-output    { color: var(--glue-term-dim); }

.shot-group {
  color: var(--fg-3);
  font-style: italic;
}
.shot-group .shot-gutter { color: var(--fg-3); }

.shot-foot {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.55rem 1rem;
  border-top: 1px solid #1e1e21;
  background: #0c0c0e;
  font-family: var(--vp-font-family-mono);
  font-size: 0.73rem;
  color: var(--glue-term-dim);
  white-space: nowrap;
  overflow: hidden;
}

.shot-foot-sep { opacity: 0.4; }
.shot-foot-spacer { flex: 1; }
.shot-foot-dim { color: var(--fg-3); }

.shot-foot-item {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
}

.shot-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  display: inline-block;
}

.shot-dot-ok {
  background: var(--glue-success);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--glue-success) 18%, transparent);
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
