---
title: Why Glue
description: Six design trade-offs we made on purpose. What we gave up, and what we got.
sidebar: false
aside: false
outline: false
pageClass: page-marketing
---

<div class="why-hero">

# Why Glue

<p class="why-kicker">designed by subtraction</p>

<p class="why-lede">
Most coding assistants get bigger over time — more modes, more panels, more
knobs. We're trying something else: each feature we did <em>not</em> add is
something we chose to give up, for a specific reason. These are the six that
shaped the product.
</p>

</div>

<ol class="tradeoffs">

  <li class="tradeoff">
    <div class="td-num">01</div>
    <div class="td-body">
      <h2 class="td-title">No IDE bolt-on.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>A panel, an extension, a webview, or a cursor-integrated chat.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>Inline previews, click-through to definitions from the transcript, AI popups on highlight.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>Glue runs in the terminal you already have open. The transcript <em>is</em> the UI — nothing moves outside it.</p>
        </div>
      </div>
    </div>
  </li>

  <li class="tradeoff">
    <div class="td-num">02</div>
    <div class="td-body">
      <h2 class="td-title">No interaction modes.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>A <code>code</code>/<code>architect</code>/<code>ask</code> picker or a "planning" state.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>A "safer" mode you can put into other people's hands without thinking.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>One surface. Behaviour is steered by the prompt, by tool approval, and by the runtime — not by a hidden toggle you forgot to flip.</p>
        </div>
      </div>
    </div>
  </li>

  <li class="tradeoff">
    <div class="td-num">03</div>
    <div class="td-body">
      <h2 class="td-title">No hosted dashboard.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>A SaaS observability layer, account system, or telemetry upload.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>Team-wide analytics, replay UI out of the box, org-level usage metering.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>Every session is an append-only <code>JSONL</code> file under <code>~/.glue/sessions/</code>. <code>tail -f</code> works. No upload. No account. No vendor can take your history away.</p>
        </div>
      </div>
    </div>
  </li>

  <li class="tradeoff">
    <div class="td-num">04</div>
    <div class="td-body">
      <h2 class="td-title">No sprawling model list.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>A startup-time "fetch every model from every provider" sweep.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>Instant visibility of every legacy or preview model a provider ever listed.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>A curated catalog you can read in one screen. Startup is fast. Anything missing goes in via <code>adapter: openai</code>.</p>
        </div>
      </div>
    </div>
  </li>

  <li class="tradeoff">
    <div class="td-num">05</div>
    <div class="td-body">
      <h2 class="td-title">No mandatory cloud runtime.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>A remote execution layer you have to route through to get useful work done.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>Zero-setup remote code execution as the default path.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>Work runs on your host, or in a local Docker container you own. If a remote runtime is the right tool, it's a backend — never a requirement.</p>
        </div>
      </div>
    </div>
  </li>

  <li class="tradeoff">
    <div class="td-num">06</div>
    <div class="td-body">
      <h2 class="td-title">No autonomous mode.</h2>
      <div class="td-grid">
        <div>
          <div class="td-label">What we didn't build</div>
          <p>An "agent that runs for hours while you sleep" default, or a parallel-agents swarm.</p>
        </div>
        <div>
          <div class="td-label">What we gave up</div>
          <p>The fantasy of set-it-and-forget-it. Unbounded background work.</p>
        </div>
        <div>
          <div class="td-label">What we got</div>
          <p>Approval is on by default. You see the tool call, you see the output, you decide the next step. When Glue writes to your repo, you know why.</p>
        </div>
      </div>
    </div>
  </li>

</ol>

<div class="not-for">

## Who this isn't for

These trade-offs cost real things. It's only fair to say who's better off
with something else.

- **If you want deep IDE integration** — Cursor, Zed, and IDE-side AI panels
  are more cohesive in that seat.
- **If you want a hosted observability dashboard** — Langfuse and LangSmith
  do that well, and Glue's JSONL is trivial to forward to either.
- **If you want an autonomous multi-hour agent** — Devin and similar
  products are a different category.

If the six trade-offs above line up with the way you already work, Glue will
feel small and direct. If they don't, that's fine — use the tool that fits.

</div>

<div class="why-foot">

Still curious?
<a href="/features">Features →</a> ·
<a href="/models">Models →</a> ·
<a href="/runtimes">Runtimes →</a>

</div>

<style scoped>
.why-hero {
  max-width: 780px;
  margin: 0 0 4rem;
}

.why-kicker {
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--vp-c-text-3);
  margin: 0 0 1.5rem;
}

.why-hero h1 {
  font-size: clamp(2.5rem, 5.5vw, 4rem);
  line-height: 1;
  letter-spacing: -0.03em;
  font-weight: 600;
  margin: 0 0 1.25rem;
}

.why-lede {
  font-size: clamp(1.05rem, 1.3vw, 1.2rem);
  line-height: 1.6;
  color: var(--vp-c-text-2);
  margin: 0;
  max-width: 620px;
}

.why-lede em {
  color: var(--glue-accent);
  font-style: normal;
  border-bottom: 1px dashed color-mix(in srgb, var(--glue-accent) 50%, transparent);
  padding-bottom: 2px;
}

.tradeoffs {
  list-style: none;
  margin: 0;
  padding: 0;
  counter-reset: tradeoff;
}

.tradeoff {
  display: grid;
  grid-template-columns: minmax(3rem, 4rem) 1fr;
  gap: 2rem;
  padding: 3rem 0;
  border-top: 1px solid var(--vp-c-divider);
}

.tradeoff:last-child {
  border-bottom: 1px solid var(--vp-c-divider);
}

.td-num {
  font-family: var(--vp-font-family-mono);
  font-size: 1.1rem;
  color: var(--glue-accent);
  letter-spacing: 0.08em;
  padding-top: 0.3rem;
}

.td-title {
  font-size: clamp(1.5rem, 2.8vw, 2rem);
  line-height: 1.1;
  letter-spacing: -0.02em;
  font-weight: 600;
  margin: 0 0 1.5rem;
  border: none;
  padding: 0;
  max-width: none;
}

.td-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1.25rem 2rem;
}

.td-grid p {
  color: var(--vp-c-text-2);
  font-size: 0.96rem;
  line-height: 1.55;
  margin: 0;
  max-width: none;
}

.td-grid code {
  font-family: var(--vp-font-family-mono);
  background: var(--vp-c-bg-alt);
  padding: 0.05rem 0.35rem;
  border-radius: 4px;
  font-size: 0.85em;
}

.td-grid em {
  font-style: normal;
  color: var(--vp-c-text-1);
  border-bottom: 1px dashed color-mix(in srgb, var(--glue-accent) 45%, transparent);
  padding-bottom: 1px;
}

.td-label {
  font-family: var(--vp-font-family-mono);
  font-size: 0.7rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--vp-c-text-3);
  margin-bottom: 0.4rem;
}

@media (max-width: 720px) {
  .tradeoff { grid-template-columns: 1fr; gap: 1rem; padding: 2.5rem 0; }
  .td-num { padding-top: 0; }
}

.not-for {
  max-width: 720px;
  margin: 5rem 0 3rem;
  padding-top: 3rem;
  border-top: 1px solid var(--vp-c-divider);
}

.not-for h2 {
  font-size: clamp(1.5rem, 2.8vw, 2rem);
  line-height: 1.1;
  letter-spacing: -0.02em;
  font-weight: 600;
  margin: 0 0 1rem;
  border: none;
  padding: 0;
}

.not-for ul {
  padding-left: 1.2em;
  margin: 1.5rem 0;
  max-width: none;
}

.not-for li {
  color: var(--vp-c-text-2);
  line-height: 1.6;
  margin: 0.75rem 0;
  max-width: 680px;
}

.not-for li strong {
  color: var(--vp-c-text-1);
}

.not-for p {
  color: var(--vp-c-text-2);
  line-height: 1.6;
  max-width: 680px;
}

.why-foot {
  padding: 2rem 0 4rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.88rem;
  color: var(--vp-c-text-3);
}

.why-foot a {
  color: var(--glue-accent);
  border-bottom: 1px dashed color-mix(in srgb, var(--glue-accent) 40%, transparent);
  padding-bottom: 1px;
  margin: 0 0.35rem;
  text-decoration: none;
}

.why-foot a:hover {
  border-bottom-style: solid;
}
</style>
