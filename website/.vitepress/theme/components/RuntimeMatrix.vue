<script setup lang="ts">
type Cell = 'yes' | 'no' | 'planned' | 'partial'

interface Row {
  runtime: string
  status?: 'shipping' | 'experimental' | 'planned'
  notes?: string
  capabilities: Record<string, Cell>
}

defineProps<{
  capabilities: string[]
  rows: Row[]
  caption?: string
}>()

const CELL_GLYPH: Record<Cell, string> = {
  yes: '✓',
  no: '—',
  planned: '◌',
  partial: '◐',
}

function cellLabel(c: Cell) {
  return CELL_GLYPH[c] ?? '—'
}
</script>

<template>
  <div class="rm-wrap">
    <table class="rm-table">
      <caption v-if="caption" class="rm-caption">{{ caption }}</caption>
      <thead>
        <tr>
          <th scope="col">Runtime</th>
          <th v-for="cap in capabilities" :key="cap" scope="col" class="rm-cap-head">{{ cap }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.runtime">
          <th scope="row" class="rm-row-head">
            <div class="rm-runtime">{{ row.runtime }}</div>
            <div v-if="row.status" class="rm-status" :data-status="row.status">{{ row.status }}</div>
            <div v-if="row.notes" class="rm-notes">{{ row.notes }}</div>
          </th>
          <td v-for="cap in capabilities" :key="cap" :data-cell="row.capabilities[cap] ?? 'no'" :title="`${row.runtime} · ${cap}: ${row.capabilities[cap] ?? 'no'}`">
            {{ cellLabel(row.capabilities[cap] ?? 'no') }}
          </td>
        </tr>
      </tbody>
    </table>
    <div class="rm-legend" aria-label="Legend">
      <span><b>✓</b> yes</span>
      <span><b>◐</b> partial</span>
      <span><b>◌</b> planned</span>
      <span><b>—</b> no</span>
    </div>
  </div>
</template>

<style scoped>
.rm-wrap {
  overflow-x: auto;
  margin: 1rem 0;
}

.rm-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.9rem;
}

.rm-caption {
  caption-side: bottom;
  text-align: left;
  padding-top: 0.5rem;
  color: var(--vp-c-text-3);
  font-size: 0.8rem;
}

.rm-table th,
.rm-table td {
  border: 1px solid var(--vp-c-divider);
  padding: 0.55rem 0.7rem;
  text-align: center;
  vertical-align: middle;
}

.rm-table th:first-child {
  width: 200px;
  min-width: 180px;
  max-width: 220px;
}

.rm-cap-head {
  font-family: var(--vp-font-family-mono);
  font-size: 0.7rem;
  color: var(--vp-c-text-3);
  font-weight: 600;
  letter-spacing: 0.03em;
  white-space: nowrap;
}

.rm-row-head {
  text-align: left;
}

.rm-runtime {
  font-weight: 600;
}

.rm-status {
  display: inline-block;
  margin-top: 0.15rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.7rem;
  color: var(--vp-c-text-3);
  text-transform: lowercase;
}

.rm-status[data-status='shipping'] { color: var(--glue-success); }
.rm-status[data-status='experimental'] { color: var(--glue-accent); }
.rm-status[data-status='planned'] { color: var(--vp-c-text-3); }

.rm-notes {
  font-size: 0.76rem;
  color: var(--vp-c-text-3);
  margin-top: 0.15rem;
}

.rm-table td[data-cell='yes'] { color: var(--glue-success); font-weight: 600; }
.rm-table td[data-cell='partial'] { color: var(--glue-accent); }
.rm-table td[data-cell='planned'] { color: var(--vp-c-text-3); }
.rm-table td[data-cell='no'] { color: var(--vp-c-text-3); }

.rm-legend {
  margin-top: 0.5rem;
  display: flex;
  gap: 1rem;
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  color: var(--vp-c-text-3);
}

.rm-legend b {
  margin-right: 0.3rem;
  color: var(--vp-c-text-2);
}
</style>
