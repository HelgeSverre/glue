---
pageClass: page-marketing
title: Badges
description: Glue badges for your projects.
sidebar: false
aside: false
outline: false
---


<script setup>
    import {ref, computed, onMounted} from 'vue'

    const badges = ref([])
    const copySuccess = ref(null)
    const selectedStyle = ref('sm')
    const selectedVariant = ref('square')
    const selectedFormat = ref('markdown')

    const BADGE_URL_BASE = 'https://getglue.dev/badges'

    onMounted(async () => {
        const res = await fetch('/badges/badges.json')
        badges.value = await res.json()
    })

    function formatSnippet(badge) {
        const url = `${BADGE_URL_BASE}/${badge.file}`
        const alt = `${badge.label} ${badge.message}`
        switch (selectedFormat.value) {
            case 'html':
                return `<a href="https://getglue.dev"><img src="${url}" alt="${alt}"></a>`
            case 'url':
                return url
            case 'img':
                return `<img src="${url}" alt="${alt}">`
            case 'markdown':
            default:
                return `[![${badge.label}](${url})](https://getglue.dev)`
        }
    }

    function copyBadge(badge) {
        navigator.clipboard.writeText(formatSnippet(badge))
        copySuccess.value = badge.id
        setTimeout(() => copySuccess.value = null, 1500)
    }

    const categories = ['status', 'brand', 'reverse']
    const categoryLabels = {
        status: 'Status',
        brand: 'Brand',
        reverse: 'Reverse',
    }

    const styleLabels = {
        sm: 'sm (20px)',
        md: 'md (24px)',
        lg: 'lg (32px)'
    }

    const variantLabels = {
        square: 'square',
        rounded: 'rounded (4px)'
    }

    const formatLabels = {
        markdown: 'Markdown',
        html: 'HTML',
        url: 'URL',
        img: '<img>'
    }

    const filteredBadges = computed(() => {
        return badges.value.filter(b =>
            b.style === selectedStyle.value &&
            // Older manifests don't carry `variant`; default to square.
            (b.variant || 'square') === selectedVariant.value
        )
    })

    function badgesForCategory(cat) {
        return filteredBadges.value.filter(b => b.category === cat)
    }
</script>

# Badges

Glue badges for your projects. Click to copy.

<div class="toolbar">
    <div class="tab-group" role="group" aria-label="Size">
        <button
                v-for="style in ['sm', 'md', 'lg']"
                :key="style"
                :class="{ active: selectedStyle === style }"
                @click="selectedStyle = style"
        >
            {{ styleLabels[style] }}
        </button>
    </div>

    <div class="tab-group" role="group" aria-label="Shape">
        <button
                v-for="variant in ['square', 'rounded']"
                :key="variant"
                :class="{ active: selectedVariant === variant }"
                @click="selectedVariant = variant"
        >
            {{ variantLabels[variant] }}
        </button>
    </div>

    <div class="tab-group" role="group" aria-label="Copy format">
        <button
                v-for="fmt in ['markdown', 'html', 'url', 'img']"
                :key="fmt"
                :class="{ active: selectedFormat === fmt }"
                @click="selectedFormat = fmt"
        >
            {{ formatLabels[fmt] }}
        </button>
    </div>
</div>

<div class="badges-section" v-for="cat in categories" :key="cat">
    <h2>{{ categoryLabels[cat] }}</h2>
    <div class="badge-grid">
        <div
                v-for="badge in badgesForCategory(cat)"
                :key="badge.id"
                class="badge-card"
                :class="{ copied: copySuccess === badge.id }"
                @click="copyBadge(badge)"
        >
            <div class="badge-row">
                <div class="preview preview-dark">
                    <img :src="`/badges/${badge.file}`" :alt="badge.label + ' ' + badge.message" :width="badge.width" :height="badge.height" />
                </div>
                <div class="preview preview-light">
                    <img :src="`/badges/${badge.file}`" :alt="badge.label + ' ' + badge.message" :width="badge.width" :height="badge.height" />
                </div>
            </div>
            <div class="badge-footer">
                <code>{{ badge.file }}</code>
                <span v-if="badge.width && badge.height" class="dims">{{ badge.width }}×{{ badge.height }}</span>
            </div>
        </div>
    </div>
</div>

<style scoped>
    .toolbar {
        display: flex;
        flex-wrap: wrap;
        gap: 1.5rem;
        margin: 1.5rem 0;
    }

    .tab-group {
        display: flex;
        gap: 8px;
    }

    .tab-group button {
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

    .tab-group button:hover {
        border-color: #FACC15;
    }

    .tab-group button.active {
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
        /* auto-fill cards so narrow badges pack tight and wide ones
           get the room they need — the previous repeat(4, 1fr)
           stretched every card to the same column width regardless
           of badge size. */
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
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
        padding: 12px 12px;
        display: flex;
        align-items: center;
        justify-content: center;
    }

    .preview-dark {
        background: #333;
    }

    .preview-light {
        background: #FFFFFF;
    }

    .preview img {
        /* Render at native pixel dimensions — the previous
           `height: 18px` clamped every size to 18px tall, which made
           md/lg badges look 25%/44% smaller than the tabs claimed
           and hid the real width differences between configs. */
        width: auto;
        height: auto;
        display: block;
        /* Keep PNG previews crisp at native resolution. */
        image-rendering: -webkit-optimize-contrast;
        image-rendering: crisp-edges;
    }

    .badge-footer {
        padding: 6px 8px;
        border-top: 1px solid var(--vp-c-divider);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
    }

    .badge-footer code {
        font-size: 0.5625rem;
        color: var(--vp-c-text-3);
        font-family: var(--vp-font-family-mono);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .badge-footer .dims {
        font-size: 0.5625rem;
        color: var(--vp-c-text-3);
        font-family: var(--vp-font-family-mono);
        flex-shrink: 0;
    }

    @media (max-width: 640px) {
        .badge-grid {
            grid-template-columns: 1fr;
        }
    }
</style>
