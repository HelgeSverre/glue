<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

// ── Hero terminal: animated playback of a real Glue session ──────────────
// Rendered to match Glue's actual TUI (block_renderer.dart):
//   ❯ You          bold blue   · user prompt
//   ◆ Glue         bold yellow · assistant
//   ▶ Tool: name   bold yellow · tool_call (+ args, + phase suffix)
//   ✓ Tool result  bold green  · tool_result  (✗ red on failure)
//   status bar     left: mode · right: model │ [approval] │ cwd │ tok N
//   ❯ prompt       yellow      · input line
//
// Script source: website/public/demo-script.json — a browser-driven scene
// (navigate → extract_text → screenshot → diff) showing the web_browser tool
// with a session that survives across calls.
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
  { kind: 'user',        text: 'extract the pricing tiers from stripe.com/pricing and save as json' },
  { kind: 'assistant',   text: 'Opening a browser session.' },
  { kind: 'tool_call',   name: 'web_browser', args: { action: 'navigate', url: 'https://stripe.com/pricing' }, phase: 'running' },
  { kind: 'tool_result', ok: true, text: 'loaded · 1.8s · "Pricing & fees | Stripe"' },
  { kind: 'tool_call',   name: 'web_browser', args: { action: 'extract_text', selector: 'main' }, phase: 'running' },
  { kind: 'tool_result', ok: true, text: '5,312 chars of markdown · session kept warm' },
  { kind: 'tool_call',   name: 'web_browser', args: { action: 'screenshot', fullPage: true }, phase: 'running' },
  { kind: 'tool_result', ok: true, text: 'saved ./pricing.png · 1.4 MB' },
  { kind: 'assistant',   text: 'Three tiers: Integrated, Customized, Enterprise. Writing JSON.' },
]
const fallbackMeta: ShotMeta = {
  cwd: '~/code/research',
  model: 'anthropic/claude-sonnet-4.6',
  approval: 'confirm',
  tokensStart: 18240,
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

  spinnerTimer = setInterval(() => {
    spinnerFrame.value = (spinnerFrame.value + 1) % spinnerFrames.length
  }, 100)
})

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
  if (spinnerTimer) clearInterval(spinnerTimer)
  isRunning.value = false
})

const bodyRef = ref<HTMLElement | null>(null)
watch(visible, async () => {
  await Promise.resolve()
  const el = bodyRef.value
  if (!el) return
  el.scrollTop = el.scrollHeight
})

// ── The six CDP primitives ────────────────────────────────────────────────
const primitives = [
  { name: 'navigate',     desc: 'open a URL and wait for network idle' },
  { name: 'click',        desc: 'click any CSS selector in the live DOM' },
  { name: 'type',         desc: 'fill inputs without reopening the tab' },
  { name: 'screenshot',   desc: 'full page or a single element' },
  { name: 'extract_text', desc: 'cleaned markdown of the current page' },
  { name: 'evaluate',     desc: 'run arbitrary JavaScript in page context' },
]

// ── Browser backends ──────────────────────────────────────────────────────
type BackendStatus = 'shipping' | 'experimental' | 'planned'
interface Backend {
  name: string
  tagline: string
  status: BackendStatus
  yaml: string
}
const backends: Backend[] = [
  {
    name: 'local',
    tagline: 'Puppeteer-launched Chrome on your machine. headed: true and you can watch it work.',
    status: 'shipping',
    yaml: `web:
  browser:
    backend: local
    headed: true`,
  },
  {
    name: 'docker',
    tagline: 'Ephemeral browserless/chrome container, one per session. No state touches your host.',
    status: 'shipping',
    yaml: `web:
  browser:
    backend: docker
    docker_image: browserless/chrome:latest
    docker_port: 3000`,
  },
  {
    name: 'cloud',
    tagline: 'Browserbase, Browserless, or Steel. Session replays, self-hosting, scale.',
    status: 'experimental',
    yaml: `web:
  browser:
    backend: browserbase
    browserbase_project_id: proj_…`,
  },
]

// ── Fetch / OCR / search config snippet ───────────────────────────────────
const fetchCfg = `web:
  fetch:
    jina_api_key: \${JINA_API_KEY}   # optional, for hostile pages
  pdf:
    enabled: true
    ocr_provider: mistral            # or openai — scanned PDFs → vision
  search:
    provider: brave                  # auto-detects brave | tavily | firecrawl`

// ── Runtime × browser matrix ──────────────────────────────────────────────
const matrixCaps = ['local', 'docker', 'browserbase', 'browserless', 'steel']
const matrixRows = [
  {
    runtime: 'host',
    status: 'shipping' as const,
    notes: 'your shell, your machine',
    capabilities: {
      local: 'yes', docker: 'yes',
      browserbase: 'partial', browserless: 'partial', steel: 'partial',
    },
  },
  {
    runtime: 'docker',
    status: 'shipping' as const,
    notes: 'ephemeral container, workspace mounted',
    capabilities: {
      local: 'no', docker: 'yes',
      browserbase: 'partial', browserless: 'partial', steel: 'partial',
    },
  },
  {
    runtime: 'cloud',
    status: 'planned' as const,
    notes: 'e2b · modal · daytona · ssh workers',
    capabilities: {
      local: 'no', docker: 'planned',
      browserbase: 'planned', browserless: 'planned', steel: 'planned',
    },
  },
] as const

// ── JSONL sample for the "also: coding" section ───────────────────────────
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
      <div class="wrap hero-grid">
        <div class="hero-copy">
          <div class="eyebrow">glue · a terminal agent where the browser is a runtime</div>

          <h1 class="headline">
            Drive a real browser <span class="accent">from the terminal.</span>
          </h1>

          <p class="sub">
            A terminal coding agent that treats Chrome like shell — navigate, click, type,
            screenshot, extract — with sessions that survive across tool calls. Swap between
            local Chrome, a Docker container, or Browserbase/Browserless/Steel with one
            config line.
          </p>

          <div class="install">
            <InstallSnippet />
          </div>

          <div class="actions">
            <a class="btn btn-primary" href="/docs/getting-started/quick-start">Quick start →</a>
            <a class="btn btn-ghost" href="/docs/advanced/browser-automation">Browser automation</a>
          </div>

          <div class="meta">
            <span><code>anthropic</code> · <code>openai</code> · <code>gemini</code> · <code>ollama</code></span>
            <span class="meta-sep">·</span>
            <span>host · docker · <span class="meta-planned">cloud</span></span>
            <span class="meta-sep">·</span>
            <span><code>local</code> · <code>docker</code> · <code>browserbase</code> · <code>browserless</code> · <code>steel</code></span>
          </div>
        </div>

        <figure class="shot" aria-label="Glue driving a browser session">
          <div class="shot-frame">
            <div class="shot-tab">
              <span class="shot-tab-dot" />
              <span class="shot-tab-title">glue — {{ meta.cwd }}</span>
            </div>

            <div ref="bodyRef" class="shot-body">
              <template v-for="(ev, i) in visibleEvents" :key="i">

                <div v-if="ev.kind === 'user'" class="tui-block tui-user">
                  <div class="tui-head"><span class="glyph glyph-blue">❯</span> You</div>
                  <div class="tui-body">{{ ev.text }}</div>
                </div>

                <div v-else-if="ev.kind === 'assistant'" class="tui-block tui-assistant">
                  <div class="tui-head"><span class="glyph glyph-accent">◆</span> Glue</div>
                  <div class="tui-body">{{ ev.text }}</div>
                </div>

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

                <div v-else-if="ev.kind === 'system'" class="tui-block tui-system">
                  {{ ev.text }}
                </div>

              </template>
            </div>

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

            <div class="shot-input">
              <span class="input-prompt">❯</span>
              <span class="input-caret" aria-hidden="true" />
            </div>
          </div>
        </figure>
      </div>
    </section>

    <!-- ─── The browser is a runtime ──────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">one runtime · six primitives</div>
        <h2 class="display">Chrome, driven from the transcript.</h2>
        <p class="lede">
          Every other terminal agent treats the web as <code>fetch(url)</code>. Glue exposes a
          real browser through Chrome DevTools Protocol — and the session stays open between
          tool calls so the agent can fill a form, submit, and read the result without
          re-opening the tab.
        </p>

        <ul class="primitives">
          <li v-for="p in primitives" :key="p.name" class="primitive">
            <code class="prim-name">{{ p.name }}</code>
            <span class="prim-desc">{{ p.desc }}</span>
          </li>
        </ul>

        <p class="callout">
          <span class="callout-label">within-turn session</span>
          The CDP session survives across tool invocations in the same prompt —
          navigate, click, type, screenshot, extract, all against the same live tab.
        </p>
      </div>
    </section>

    <!-- ─── Swap backend, not code ────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">swap backend · not code</div>
        <h2 class="display">Same six actions. Somewhere else to run them.</h2>
        <p class="lede">
          One interface — <code>BrowserEndpointProvider</code> — behind every backend. Pick
          local Chrome for iteration, a Docker container when the page is sketchy, or a cloud
          vendor when you need replays and scale. Swap is a config change, not a code change.
        </p>

        <div class="backends">
          <article
            v-for="b in backends"
            :key="b.name"
            class="backend"
            :data-status="b.status"
          >
            <header class="backend-head">
              <span class="backend-name">{{ b.name }}</span>
              <FeatureStatus :status="b.status" />
            </header>
            <p class="backend-sub">{{ b.tagline }}</p>
            <pre class="backend-code"><code>{{ b.yaml }}</code></pre>
          </article>
        </div>
      </div>
    </section>

    <!-- ─── Fetch / OCR / search ──────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">fetch · ocr · search</div>
        <h2 class="display">Scanned PDFs. Hostile pages. Results you can use.</h2>
        <p class="lede">
          Not every page needs a browser. The fetch tool reads HTML as cleaned markdown,
          pulls text out of PDFs, and falls back to a vision model when the PDF is scanned.
          Search picks whichever provider you've already paid for.
        </p>

        <ul class="capabilities">
          <li>
            <code>web_fetch</code> · HTML → markdown · PDF → text ·
            <strong>OCR fallback</strong> via <code>mistral</code> or <code>openai</code> vision for scanned documents.
          </li>
          <li>
            <code>web_fetch</code> · optional <strong>Jina</strong> fallback for pages that don't extract cleanly
            (<code>JINA_API_KEY</code>).
          </li>
          <li>
            <code>web_search</code> · auto-detects the first available of
            <code>BRAVE_API_KEY</code>, <code>TAVILY_API_KEY</code>, <code>FIRECRAWL_API_KEY</code>.
          </li>
        </ul>

        <pre class="cfg"><code>{{ fetchCfg }}</code></pre>

        <p class="more"><a href="/docs/advanced/web-tools">Web tools guide →</a></p>
      </div>
    </section>

    <!-- ─── Runtime × browser matrix ──────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">pair them how you like</div>
        <h2 class="display">Runtime × browser.</h2>
        <p class="lede">
          Run the agent on your host or inside an ephemeral Docker container. Drive a browser
          on your machine, in a sibling container, or in someone else's cloud. They compose.
        </p>

        <RuntimeMatrix
          :capabilities="matrixCaps"
          :rows="matrixRows as any"
          caption='"partial" = the backend works but is still flagged experimental. "planned" = cloud runtimes are tracked but not shipped.'
        />

        <p class="more"><a href="/runtimes">Full runtime capability matrix →</a></p>
      </div>
    </section>

    <!-- ─── Also: coding ──────────────────────────────────────────────── -->
    <section class="section section-divider">
      <div class="wrap">
        <div class="kicker">also · coding</div>
        <h2 class="display">Everything else you'd expect from a coding agent.</h2>
        <p class="lede">
          Glue is still a full coding agent underneath. It edits files, runs shell, jumps
          into Docker for risky work, and writes every session to an append-only JSONL log
          on your machine — nothing hosted, nothing uploaded.
        </p>

        <ul class="coding-list">
          <li><strong>Edits.</strong> Multi-file changes land in the transcript as diffs.</li>
          <li><strong>Shell.</strong> Host shell or ephemeral Docker container — your call, per session.</li>
          <li><strong>Sessions.</strong> Append-only JSONL under <code>~/.glue/sessions/</code>. <code>tail -f</code> works.</li>
          <li><strong>Providers.</strong> Anthropic, OpenAI, Gemini, Mistral, Groq, Ollama, OpenRouter — bring your own key.</li>
        </ul>

        <pre class="jsonl"><code v-for="(line, i) in jsonlSample" :key="i">{{ line }}
</code></pre>

        <p class="more">
          <a href="/sessions">How sessions work →</a>
          <span class="more-sep">·</span>
          <a href="/models">Model catalog →</a>
          <span class="more-sep">·</span>
          <a href="/features">Feature list →</a>
        </p>
      </div>
    </section>

    <!-- ─── CTA ───────────────────────────────────────────────────────── -->
    <section class="section section-divider section-cta">
      <div class="wrap cta">
        <h2 class="display">
          Install it. <span class="cta-run">Open a tab.</span>
        </h2>
        <div class="cta-install"><InstallSnippet /></div>
        <div class="actions">
          <a class="btn btn-primary" href="/docs/getting-started/quick-start">Quick start →</a>
          <a class="btn btn-ghost" href="/docs/advanced/browser-automation">Browser automation</a>
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
  max-width: 680px;
  color: var(--fg-dim);
  font-size: clamp(1.02rem, 1.25vw, 1.15rem);
  line-height: 1.55;
  margin: 0;
}

.more {
  margin-top: 2rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.88rem;
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
  align-items: baseline;
}

.more a {
  color: var(--accent);
  border-bottom: 1px dashed color-mix(in srgb, var(--accent) 40%, transparent);
  padding-bottom: 2px;
}

.more a:hover {
  border-bottom-style: solid;
}

.more-sep {
  color: var(--fg-3);
  opacity: 0.6;
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
  max-width: 620px;
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
  padding-left: 2ch;
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

.tui-user .tui-head      { color: #3B82F6; }
.tui-assistant .tui-head { color: var(--accent); }
.tui-tool .tui-head      { color: var(--accent); }
.tui-result .tui-head    { /* handled by glyph class */ }
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
  padding-left: 4ch;
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
.phase-run  { color: #22D3EE; }
.phase-deny { color: var(--glue-error); }

@media (prefers-reduced-motion: reduce) {
  .tui-block { animation: none; }
}

/* Status bar */
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

/* ── Primitives grid (six actions) ────────────────────────────────────── */
.primitives {
  list-style: none;
  padding: 0;
  margin: 2.5rem 0 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 0;
  border-top: 1px solid var(--div);
}

.primitive {
  padding: 1.25rem 1.25rem 1.25rem 0;
  border-bottom: 1px solid var(--div);
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.prim-name {
  font-family: var(--vp-font-family-mono);
  font-size: 1.05rem;
  font-weight: 600;
  color: var(--accent);
}

.prim-desc {
  color: var(--fg-dim);
  font-size: 0.95rem;
  line-height: 1.5;
}

.callout {
  margin: 2rem 0 0;
  padding: 1rem 1.25rem;
  border-left: 2px solid var(--accent);
  background: color-mix(in srgb, var(--accent) 6%, transparent);
  color: var(--fg-dim);
  font-size: 0.98rem;
  line-height: 1.55;
}

.callout-label {
  display: inline-block;
  font-family: var(--vp-font-family-mono);
  font-size: 0.72rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--accent);
  margin-right: 0.6rem;
  font-weight: 600;
}

/* ── Backends (three tiles) ───────────────────────────────────────────── */
.backends {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 1.25rem;
  margin-top: 2.5rem;
}

@media (max-width: 900px) {
  .backends { grid-template-columns: 1fr; }
}

.backend {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  padding: 1.5rem;
  border: 1px solid var(--div);
  border-radius: 10px;
  background: var(--vp-c-bg-soft);
}

.backend[data-status='experimental'] {
  border-color: color-mix(in srgb, var(--accent) 35%, var(--div));
}

.backend-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}

.backend-name {
  font-family: var(--vp-font-family-mono);
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--fg);
}

.backend-sub {
  margin: 0;
  color: var(--fg-dim);
  font-size: 0.95rem;
  line-height: 1.5;
  min-height: 3em;
}

.backend-code {
  margin: 0;
  padding: 0.85rem 1rem;
  background: var(--glue-term-bg);
  color: var(--glue-term-fg);
  border: 1px solid #1e1e21;
  border-radius: 6px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.8rem;
  line-height: 1.55;
  white-space: pre;
  overflow-x: auto;
}

/* ── Capabilities list (fetch/ocr/search) ─────────────────────────────── */
.capabilities {
  list-style: none;
  padding: 0;
  margin: 2.5rem 0 0;
  border-top: 1px solid var(--div);
}

.capabilities li {
  padding: 1.25rem 0;
  border-bottom: 1px solid var(--div);
  color: var(--fg-dim);
  font-size: 1rem;
  line-height: 1.55;
}

.capabilities code {
  color: var(--accent);
}

.capabilities strong {
  color: var(--fg);
  font-weight: 600;
}

.cfg {
  margin: 2rem 0 0;
  padding: 1.25rem 1.5rem;
  background: var(--glue-term-bg);
  color: var(--glue-term-fg);
  border: 1px solid #1e1e21;
  border-radius: 8px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.85rem;
  line-height: 1.7;
  white-space: pre;
  overflow-x: auto;
}

/* ── Coding list ──────────────────────────────────────────────────────── */
.coding-list {
  list-style: none;
  padding: 0;
  margin: 2.5rem 0 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 0;
  border-top: 1px solid var(--div);
}

.coding-list li {
  padding: 1.25rem 1.25rem 1.25rem 0;
  border-bottom: 1px solid var(--div);
  color: var(--fg-dim);
  font-size: 0.98rem;
  line-height: 1.55;
}

.coding-list strong {
  color: var(--fg);
  font-weight: 600;
  margin-right: 0.35rem;
}

.coding-list code {
  color: var(--accent);
}

/* ── JSONL block ──────────────────────────────────────────────────────── */
.jsonl {
  margin: 2rem 0 0;
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
