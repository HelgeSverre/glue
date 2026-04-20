<script setup lang="ts">
import { ref, useSlots } from "vue";

defineProps<{
  title?: string;
}>();

const slots = useSlots();
const copied = ref(false);

function slotText(): string {
  const nodes = slots.default?.() ?? [];
  const walk = (n: any): string => {
    if (typeof n === "string") return n;
    if (Array.isArray(n)) return n.map(walk).join("");
    if (n?.children) return walk(n.children);
    return "";
  };
  return walk(nodes).trim();
}

async function copy() {
  try {
    await navigator.clipboard.writeText(slotText());
    copied.value = true;
    setTimeout(() => (copied.value = false), 1200);
  } catch {
    /* clipboard blocked — ignore */
  }
}
</script>

<template>
  <div class="cs-wrap">
    <div class="cs-head">
      <span v-if="title" class="cs-title">{{ title }}</span>
      <button
        class="cs-copy"
        type="button"
        @click="copy"
        :aria-label="copied ? 'Copied' : 'Copy snippet'"
      >
        {{ copied ? "copied" : "copy" }}
      </button>
    </div>
    <div class="cs-body">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.cs-wrap {
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  overflow: hidden;
  margin: 1rem 0;
  background: var(--vp-c-bg-soft);
}

.cs-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.45rem 0.875rem;
  border-bottom: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-alt);
}

.cs-title {
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  color: var(--vp-c-text-3);
}

.cs-copy {
  border: none;
  background: transparent;
  color: var(--vp-c-text-3);
  font-family: var(--vp-font-family-mono);
  font-size: 12px;
  cursor: pointer;
  padding: 0.15rem 0.5rem;
}

.cs-copy:hover {
  color: var(--glue-accent);
}

.cs-body :deep(div[class*="language-"]) {
  margin: 0;
  border: none;
  border-radius: 0;
}

.cs-body :deep(pre) {
  margin: 0;
}
</style>
