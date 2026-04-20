---
pageClass: page-marketing
title: Badges
description: Glue badges for your projects.
sidebar: false
aside: false
outline: false
---

<script setup>
import { ref, computed, onMounted } from 'vue'

const badges = ref([])
const copySuccess = ref(null)
const selectedStyle = ref('sm')

const BADGE_URL_BASE = 'https://getglue.dev/badges'

onMounted(async () => {
  const res = await fetch('/badges/badges.json')
  badges.value = await res.json()
})

function copyMarkdown(badge) {
  const url = `${BADGE_URL_BASE}/${badge.file}`
  const md = `[![${badge.label}](${url})](https://getglue.dev)`
  navigator.clipboard.writeText(md)
  copySuccess.value = badge.id
  setTimeout(() => copySuccess.value = null, 1500)
}

const categories = ['status', 'brand', 'reverse', 'meme']
const categoryLabels = {
  status: 'Status',
  brand: 'Brand',
  reverse: 'Reverse',
  meme: 'meme 😅'
}

const styleLabels = {
  sm: 'sm (20px)',
  md: 'md (24px)',
  lg: 'lg (32px)'
}

const filteredBadges = computed(() => {
  return badges.value.filter(b => b.style === selectedStyle.value)
})

function badgesForCategory(cat) {
  return filteredBadges.value.filter(b => b.category === cat)
}
</script>

# Badges

Glue badges for your projects. Click to copy.

<div class="style-tabs">
  <button
    v-for="style in ['sm', 'md', 'lg']"
    :key="style"
    :class="{ active: selectedStyle === style }"
    @click="selectedStyle = style"
  >
    {{ styleLabels[style] }}
  </button>
</div>

<div class="badges-section" v-for="cat in categories" :key="cat">
  <h2>{{ categoryLabels[cat] }}</h2>
  <div class="badge-grid">
    <div
      v-for="badge in badgesForCategory(cat)"
      :key="badge.id"
      class="badge-card"
      :class="{ copied: copySuccess === badge.id }"
      @click="copyMarkdown(badge)"
    >
      <div class="badge-row">
        <div class="preview" :style="{ background: '#0A0A0B' }">
          <img :src="`/badges/${badge.file}`" :alt="badge.label + ' ' + badge.message" />
        </div>
        <div class="preview" :style="{ background: '#FFFFFF' }">
          <img :src="`/badges/${badge.file}`" :alt="badge.label + ' ' + badge.message" />
        </div>
      </div>
      <div class="badge-footer">
        <code>{{ badge.file }}</code>
      </div>
    </div>
  </div>
</div>

<style scoped>
.style-tabs {
  display: flex;
  gap: 8px;
  margin: 1.5rem 0;
}

.style-tabs button {
  background: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-divider);
  border-radius: 6px;
  padding: 6px 14px;
  font-size: 0.8125rem;
  font-family: var(--vp-font-family-mono);
  color: var(--vp-c-text-2);
  cursor: pointer;
  transition: all 0.15s;
}

.style-tabs button:hover {
  border-color: #FACC15;
}

.style-tabs button.active {
  background: #FACC15;
  border-color: #FACC15;
  color: #0A0A0B;
  font-weight: 600;
}

.badges-section {
  margin-top: 1.5rem;
}

.badges-section h2 {
  font-size: 0.875rem;
  font-weight: 600;
  margin: 1.25rem 0 0.75rem;
  color: var(--vp-c-text-2);
}

.badge-grid {
  display: grid;
  gap: 8px;
  grid-template-columns: repeat(4, 1fr);
}

.badge-card {
  background: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  padding: 0;
  cursor: pointer;
  overflow: hidden;
  transition: all 0.15s ease;
}

.badge-card:hover {
  border-color: #FACC15;
}

.badge-card.copied {
  border-color: #22C55E;
  background: rgba(34, 197, 94, 0.1);
}

.badge-row {
  display: flex;
  flex-direction: column;
  gap: 1px;
  background: var(--vp-c-divider);
}

.preview {
  padding: 8px 6px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.preview img {
  height: 18px;
  width: auto;
  display: block;
}

.badge-footer {
  padding: 6px 8px;
  border-top: 1px solid var(--vp-c-divider);
}

.badge-footer code {
  font-size: 0.5625rem;
  color: var(--vp-c-text-3);
  font-family: var(--vp-font-family-mono);
}

@media (max-width: 768px) {
  .badge-grid {
    grid-template-columns: repeat(3, 1fr);
  }
}

@media (max-width: 640px) {
  .badge-grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
</style>
