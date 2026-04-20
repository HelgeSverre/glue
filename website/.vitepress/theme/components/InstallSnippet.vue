<script setup lang="ts">
import { ref } from "vue";

const command = "curl -fsSL https://getglue.dev/install.sh | sh";
const copied = ref(false);

async function copy() {
  try {
    await navigator.clipboard.writeText(command);
    copied.value = true;
    setTimeout(() => (copied.value = false), 1200);
  } catch {
    /* clipboard blocked — ignore */
  }
}
</script>

<template>
  <div class="is-wrap">
    <pre class="is-code"><code>{{ command }}</code></pre>
    <button
      class="is-copy"
      type="button"
      @click="copy"
      :aria-label="copied ? 'Copied' : 'Copy install command'"
    >
      {{ copied ? "copied" : "copy" }}
    </button>
  </div>
</template>

<style scoped>
.is-wrap {
  position: relative;
  display: flex;
  align-items: stretch;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background: var(--glue-term-bg);
  color: var(--glue-term-fg);
  font-family: var(--vp-font-family-mono);
  overflow: hidden;
  margin: 1rem 0;
}

.is-code {
  flex: 1;
  margin: 0;
  padding: 0.85rem 1rem;
  background: transparent;
  color: inherit;
  font-size: 13px;
  white-space: pre;
  overflow-x: auto;
}

.is-copy {
  border: none;
  border-left: 1px solid var(--vp-c-divider);
  background: transparent;
  color: var(--glue-term-dim);
  padding: 0 1rem;
  font-family: var(--vp-font-family-mono);
  font-size: 12px;
  cursor: pointer;
  transition: color 120ms ease;
}

.is-copy:hover {
  color: var(--glue-accent);
}
</style>
