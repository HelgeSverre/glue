<script setup lang="ts">
defineProps<{
  status: 'shipping' | 'experimental' | 'planned'
  label?: string
}>()
</script>

<template>
  <span class="fs-pill" :data-status="status" :title="`Status: ${status}`">
    <span class="fs-dot" aria-hidden="true" />
    <span class="fs-label">{{ label ?? status }}</span>
  </span>
</template>

<style scoped>
.fs-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.125rem 0.5rem;
  border-radius: 999px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.72rem;
  font-weight: 600;
  line-height: 1.4;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-soft);
  color: var(--vp-c-text-2);
  vertical-align: baseline;
  text-transform: lowercase;
  letter-spacing: 0.02em;
}

.fs-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}

.fs-pill[data-status='shipping'] {
  color: var(--glue-success);
  border-color: color-mix(in srgb, var(--glue-success) 35%, var(--vp-c-divider));
}

.fs-pill[data-status='experimental'] {
  color: var(--glue-accent);
  border-color: color-mix(in srgb, var(--glue-accent) 40%, var(--vp-c-divider));
}

.fs-pill[data-status='planned'] {
  color: var(--vp-c-text-3);
}
</style>
