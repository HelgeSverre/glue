<script setup lang="ts">
interface Model {
  id: string;
  provider: string;
  capabilities?: string[];
  recommended?: boolean;
  notes?: string;
}

defineProps<{
  models: Model[];
  caption?: string;
}>();

const CAP_ICONS: Record<string, string> = {
  chat: "💬",
  tools: "🔧",
  vision: "👁",
  files: "📎",
  json: "{}",
  reasoning: "🧠",
  coding: "⌨",
  local: "🖥",
  browser: "🌐",
};

function capIcon(cap: string) {
  return CAP_ICONS[cap] ?? cap;
}
</script>

<template>
  <div class="mt-wrap">
    <table class="mt-table">
      <caption v-if="caption" class="mt-caption">
        {{
          caption
        }}
      </caption>
      <thead>
        <tr>
          <th scope="col">Model</th>
          <th scope="col">Provider</th>
          <th scope="col">Capabilities</th>
          <th scope="col">Notes</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="m in models"
          :key="`${m.provider}/${m.id}`"
          :class="{ 'mt-recommended': m.recommended }"
        >
          <td class="mt-id">
            <code>{{ m.provider }}/{{ m.id }}</code>
            <span v-if="m.recommended" class="mt-badge" title="Recommended"
              >★</span
            >
          </td>
          <td>{{ m.provider }}</td>
          <td class="mt-caps">
            <span
              v-for="c in m.capabilities ?? []"
              :key="c"
              class="mt-cap"
              :title="c"
            >
              {{ capIcon(c) }}
            </span>
          </td>
          <td class="mt-notes">{{ m.notes ?? "" }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.mt-wrap {
  overflow-x: auto;
  margin: 1rem 0;
}

.mt-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.92rem;
}

.mt-caption {
  caption-side: bottom;
  text-align: left;
  padding-top: 0.5rem;
  color: var(--vp-c-text-3);
  font-size: 0.8rem;
}

.mt-table th,
.mt-table td {
  border-bottom: 1px solid var(--vp-c-divider);
  padding: 0.6rem 0.75rem;
  text-align: left;
  vertical-align: top;
}

.mt-table th {
  font-family: var(--vp-font-family-mono);
  font-size: 0.72rem;
  color: var(--vp-c-text-3);
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.mt-id code {
  font-family: var(--vp-font-family-mono);
  background: var(--vp-c-bg-soft);
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  font-size: 0.82rem;
}

.mt-badge {
  margin-left: 0.35rem;
  color: var(--glue-accent);
}

.mt-caps {
  font-family: var(--vp-font-family-mono);
  font-size: 0.85rem;
}

.mt-cap {
  display: inline-block;
  margin-right: 0.4rem;
}

.mt-notes {
  color: var(--vp-c-text-2);
  font-size: 0.85rem;
}
</style>
