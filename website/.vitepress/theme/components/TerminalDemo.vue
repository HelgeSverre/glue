<script setup lang="ts">
interface Step {
  kind: "prompt" | "assistant" | "tool" | "output" | "note";
  text: string;
}

defineProps<{
  steps: Step[];
  title?: string;
}>();
</script>

<template>
  <div class="td-frame" role="img" :aria-label="title ?? 'Terminal demo'">
    <div class="td-bar">
      <span class="td-dot" />
      <span class="td-dot" />
      <span class="td-dot" />
      <span v-if="title" class="td-title">{{ title }}</span>
    </div>
    <pre class="td-body"><template v-for="(step, i) in steps" :key="i"><span
      class="td-line" :class="`td-${step.kind}`"><span
      class="td-gutter" aria-hidden="true">{{ gutter(step.kind) }}</span>{{ step.text }}
</span></template></pre>
  </div>
</template>

<script lang="ts">
function gutter(kind: string) {
  switch (kind) {
    case "prompt":
      return "› ";
    case "assistant":
      return "· ";
    case "tool":
      return "⏵ ";
    case "output":
      return "  ";
    case "note":
      return "# ";
    default:
      return "  ";
  }
}
</script>

<style scoped>
.td-frame {
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background: var(--glue-term-bg);
  color: var(--glue-term-fg);
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
  line-height: 1.55;
  overflow: hidden;
  margin: 1.25rem 0;
}

.td-bar {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem;
  background: #141416;
  border-bottom: 1px solid var(--vp-c-divider);
}

.td-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #2a2b2e;
}

.td-title {
  margin-left: 0.5rem;
  font-size: 0.72rem;
  color: var(--glue-term-dim);
  letter-spacing: 0.02em;
}

.td-body {
  margin: 0;
  padding: 1rem 1.25rem;
  white-space: pre-wrap;
  word-break: break-word;
  background: transparent;
  color: inherit;
}

.td-line {
  display: block;
}

.td-gutter {
  color: var(--glue-term-dim);
  user-select: none;
}

.td-prompt {
  color: var(--glue-accent);
}
.td-prompt .td-gutter {
  color: var(--glue-accent);
}

.td-assistant {
  color: var(--glue-term-fg);
}

.td-tool {
  color: var(--glue-info);
}
.td-tool .td-gutter {
  color: var(--glue-info);
}

.td-output {
  color: var(--glue-term-dim);
}

.td-note {
  color: var(--glue-term-dim);
  font-style: italic;
}
</style>
