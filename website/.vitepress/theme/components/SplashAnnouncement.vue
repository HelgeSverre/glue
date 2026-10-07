<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";

const banner = ref<HTMLElement>();
let resizeObserver: ResizeObserver | undefined;

onMounted(() => {
  const element = banner.value;
  if (!element) return;

  // Keep VitePress navigation and anchor offsets in sync when the text wraps.
  const updateHeight = () => {
    document.documentElement.style.setProperty(
      "--vp-layout-top-height",
      `${element.offsetHeight}px`,
    );
  };

  updateHeight();
  resizeObserver = new ResizeObserver(updateHeight);
  resizeObserver.observe(element);
});

onUnmounted(() => {
  resizeObserver?.disconnect();
  document.documentElement.style.removeProperty("--vp-layout-top-height");
});
</script>

<template>
  <aside ref="banner" class="splash-announcement" aria-label="Announcement">
    <a href="https://splash.computer">
      <strong>Meet Splash.</strong> Run coding agents side by side.&nbsp;<span
        aria-hidden="true"
        >↗</span
      >
    </a>
  </aside>
</template>

<style scoped>
.splash-announcement {
  position: fixed;
  inset: 0 0 auto;
  z-index: var(--vp-z-index-layout-top);
  background: var(--glue-accent);
  color: #0a0a0b;
}

.splash-announcement a {
  display: block;
  min-height: 3rem;
  padding: 0.75rem 1.5rem;
  color: inherit;
  font-size: 0.875rem;
  line-height: 1.5rem;
  text-align: center;
}

.splash-announcement strong {
  font-weight: 700;
  text-decoration: underline;
  text-underline-offset: 0.2em;
}

.splash-announcement a:hover {
  background: #fde047;
}

.splash-announcement a:focus-visible {
  outline: 2px solid currentColor;
  outline-offset: -4px;
  border-radius: 0;
}
</style>
