---
title: Features
description: The shipping, experimental, and planned pieces of Glue — honestly labelled.
sidebar: false
aside: false
outline: false
pageClass: page-marketing
---

<div class="features-hero">

# Features

Every feature carries a status —
<FeatureStatus status="shipping" /> is in the binary today,
<FeatureStatus status="experimental" /> works but rough,
<FeatureStatus status="planned" /> not yet shipped.

</div>

<div class="feature-grid">

<article class="feature-card">
  <div class="fc-icon">›</div>
  <div class="fc-head">
    <h3>Agent loop</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>The core ReAct loop — prompt, reason, tool, result, next step. Streamed, interruptible, and fully logged.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">✎</div>
  <div class="fc-head">
    <h3>File editing</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Targeted patches, multi-file edits, new files. Every change lands in the transcript as a diff summary.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">⏵</div>
  <div class="fc-head">
    <h3>Command execution</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Run shell commands through your <code>$SHELL</code>. Output is captured, streamed back, and written to the session log.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">◆</div>
  <div class="fc-head">
    <h3>Models &amp; providers</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Curated catalog. <code>provider/model</code> IDs. <code>adapter: openai</code> for any compatible endpoint. Credentials stay out of project config. <a href="/models">Catalog →</a></p>
</article>

<article class="feature-card">
  <div class="fc-icon">⌂</div>
  <div class="fc-head">
    <h3>Host runtime</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Commands run in your shell on your machine — fastest path, uses the tools you already have installed.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">⊟</div>
  <div class="fc-head">
    <h3>Docker sandbox</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Ephemeral containers for risky work. Workspace mounted in, container torn down with the session. Sandbox polish is <FeatureStatus status="experimental" />.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">☁</div>
  <div class="fc-head">
    <h3>Cloud runtimes</h3>
    <FeatureStatus status="planned" />
  </div>
  <p>Offload to remote workers (E2B, Modal, Daytona, custom SSH or container). Tracked by the runtime boundary plan. <a href="/runtimes">Runtimes →</a></p>
</article>

<article class="feature-card">
  <div class="fc-icon">⌘</div>
  <div class="fc-head">
    <h3>Sessions</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Append-only JSONL logs under <code>~/.glue/sessions/</code>. Resumable across runs. Replay UI is <FeatureStatus status="planned" />. <a href="/sessions">How it works →</a></p>
</article>

<article class="feature-card">
  <div class="fc-icon">◐</div>
  <div class="fc-head">
    <h3>Web tools</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Fetch, search, extract, PDF OCR, browser automation. The CDP backend is <FeatureStatus status="experimental" />. <a href="/web">Web →</a></p>
</article>

<article class="feature-card">
  <div class="fc-icon">⇶</div>
  <div class="fc-head">
    <h3>Subagents</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Delegate a sub-task to a separate agent with its own context and tool set. Useful for parallel search or independent investigations.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">◇</div>
  <div class="fc-head">
    <h3>Skills</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Discoverable, runnable skill definitions the agent can invoke as first-class tools.</p>
</article>

<article class="feature-card">
  <div class="fc-icon">⌁</div>
  <div class="fc-head">
    <h3>MCP integration</h3>
    <FeatureStatus status="shipping" />
  </div>
  <p>Talk to any MCP server as a tool source. Editor integration, external search providers, custom tool backends.</p>
</article>

</div>

<style scoped>
.features-hero {
  max-width: 700px;
  margin: 0 0 3rem;
}

.features-hero h1 {
  font-size: clamp(2.5rem, 5vw, 3.5rem);
  line-height: 1.05;
  letter-spacing: -0.025em;
  margin: 0 0 1.25rem;
  font-weight: 600;
}

.features-hero p {
  font-size: 1.05rem;
  line-height: 1.55;
  color: var(--vp-c-text-2);
  margin: 0;
  max-width: none;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
  margin: 2rem 0 3rem;
}

.feature-card {
  border: 1px solid var(--vp-c-divider);
  border-radius: 10px;
  padding: 1.5rem 1.5rem 1.35rem;
  background: var(--vp-c-bg-soft, #16171A);
  transition: border-color 150ms ease, transform 150ms ease, background 150ms ease;
  min-height: 168px;
  display: grid;
  grid-template-rows: auto auto 1fr;
  gap: 0.6rem;
}

.feature-card:hover {
  border-color: color-mix(in srgb, var(--glue-accent) 35%, var(--vp-c-divider));
  transform: translateY(-1px);
}

.fc-icon {
  font-family: var(--vp-font-family-mono);
  font-size: 1.6rem;
  line-height: 1;
  color: var(--glue-accent);
  margin-bottom: 0.15rem;
}

.fc-head {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  flex-wrap: wrap;
}

.fc-head h3 {
  margin: 0;
  font-size: 1.08rem;
  font-weight: 600;
  letter-spacing: -0.005em;
  color: var(--vp-c-text-1);
  border: none;
  padding: 0;
}

.feature-card p {
  margin: 0;
  color: var(--vp-c-text-2);
  font-size: 0.94rem;
  line-height: 1.55;
  max-width: none;
}

.feature-card p :deep(a) {
  color: var(--glue-accent);
  border-bottom: 1px dashed color-mix(in srgb, var(--glue-accent) 40%, transparent);
  padding-bottom: 1px;
  text-decoration: none;
}

.feature-card p :deep(a):hover {
  border-bottom-style: solid;
}

.feature-card :deep(code) {
  font-family: var(--vp-font-family-mono);
  background: var(--vp-c-bg-alt);
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  font-size: 0.85em;
}
</style>
