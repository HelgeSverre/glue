import { defineConfig, type DefaultTheme } from 'vitepress'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const vitepressDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(vitepressDir, '..', '..')

// ── API reference sidebar (auto-generated) ───────────────────────────────
const apiSidebarPath = path.join(vitepressDir, 'sidebar.json')
const apiSidebar = fs.existsSync(apiSidebarPath)
  ? JSON.parse(fs.readFileSync(apiSidebarPath, 'utf-8'))
  : []

// ── Changelog version sidebar (built from cli/CHANGELOG.md) ──────────────
const changelogSidebar = buildChangelogSidebar()

function buildChangelogSidebar(): DefaultTheme.SidebarItem[] {
  const changelogPath = path.join(repoRoot, 'cli', 'CHANGELOG.md')
  if (!fs.existsSync(changelogPath)) return []
  const text = fs.readFileSync(changelogPath, 'utf-8')
  const versions: { text: string; slug: string }[] = []
  for (const line of text.split('\n')) {
    // Matches e.g. `## [Unreleased]` or `## [0.1.0] — Initial development`
    const match = /^##\s+(.+?)\s*$/.exec(line)
    if (!match) continue
    const heading = match[1]
    if (!/^\[/.test(heading)) continue
    versions.push({ text: heading, slug: slugify(heading) })
  }
  return [
    {
      text: 'Changelog',
      items: [
        { text: 'Top', link: '/changelog' },
        ...versions.map(v => ({ text: v.text, link: `/changelog#${v.slug}` })),
      ],
    },
  ]
}

// Mirrors VitePress' default slugify: lowercases, strips punctuation it
// doesn't accept as part of an anchor, collapses runs to single `-`.
function slugify(input: string): string {
  return input
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\w\-\s]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
}

// ── Site-wide default OG/Twitter meta. Per-page title/description override
// via the transformPageData hook below.
const ogDefaults = {
  siteName: 'Glue',
  image: 'https://getglue.dev/og-default.svg',
  twitterSite: '@helgesverre',
}

export default defineConfig({
  title: 'Glue',
  titleTemplate: ':title · Glue',
  description: 'A small terminal agent for real coding work.',
  cleanUrls: true,
  lastUpdated: true,
  appearance: 'force-dark',

  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap', rel: 'stylesheet' }],
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/brand/symbol-yellow.svg' }],
    ['meta', { name: 'theme-color', content: '#0A0A0B' }],

    // OpenGraph / Twitter defaults. transformPageData below overrides title
    // and description per-page.
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: ogDefaults.siteName }],
    ['meta', { property: 'og:image', content: ogDefaults.image }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:site', content: ogDefaults.twitterSite }],
    ['meta', { name: 'twitter:image', content: ogDefaults.image }],
  ],

  // Populate og:title / og:description / og:url / twitter:* per page from
  // the page's own `title` + `description` frontmatter.
  transformPageData(pageData) {
    const head = pageData.frontmatter.head ?? []
    const title = pageData.title
      ? `${pageData.title} · Glue`
      : 'Glue · A small terminal agent for real coding work'
    const description = (pageData.description as string | undefined)
      ?? pageData.frontmatter.description
      ?? 'A small terminal agent for real coding work.'
    head.push(['meta', { property: 'og:title', content: title }])
    head.push(['meta', { property: 'og:description', content: description }])
    head.push(['meta', { name: 'twitter:title', content: title }])
    head.push(['meta', { name: 'twitter:description', content: description }])

    const relativePath = pageData.relativePath.replace(/\.md$/, '').replace(/\/index$/, '/')
    head.push(['meta', { property: 'og:url', content: `https://getglue.dev/${relativePath}` }])

    pageData.frontmatter.head = head
  },

  themeConfig: {
    siteTitle: 'Glue',
    logo: { src: '/brand/symbol-yellow.svg', alt: 'Glue' },

    nav: [
      {
        text: 'Docs',
        items: [
          {
            text: 'Reference',
            items: [
              { text: 'Guide', link: '/docs/getting-started/installation' },
              { text: 'API Reference', link: '/api/' },
            ],
          },
          {
            text: 'Overviews',
            items: [
              { text: 'Why Glue', link: '/why' },
              { text: 'Features', link: '/features' },
              { text: 'Runtimes', link: '/runtimes' },
              { text: 'Web Tools', link: '/web' },
              { text: 'Sessions', link: '/sessions' },
              { text: 'Brand', link: '/brand' },
            ],
          },
        ],
      },
      { text: 'Models', link: '/models' },
      { text: 'Roadmap', link: '/roadmap' },
      { text: 'Changelog', link: '/changelog' },
    ],

    sidebar: {
      '/docs/': [
        {
          text: 'Getting Started',
          items: [
            { text: 'Installation', link: '/docs/getting-started/installation' },
            { text: 'Quick Start', link: '/docs/getting-started/quick-start' },
            { text: 'Configuration', link: '/docs/getting-started/configuration' },
          ],
        },
        {
          text: 'Using Glue',
          items: [
            { text: 'Interactive Mode', link: '/docs/using-glue/interactive-mode' },
            { text: 'Models & Providers', link: '/docs/using-glue/models-and-providers' },
            { text: 'Tools', link: '/docs/using-glue/tools' },
            { text: 'Tool Approval', link: '/docs/using-glue/tool-approval' },
            { text: 'Sessions', link: '/docs/using-glue/sessions' },
            { text: 'File References', link: '/docs/using-glue/file-references' },
            { text: 'Bash Mode', link: '/docs/using-glue/bash-mode' },
            { text: 'Worktrees', link: '/docs/using-glue/worktrees' },
            { text: 'Docker Sandbox', link: '/docs/using-glue/docker-sandbox' },
          ],
        },
        {
          text: 'Advanced',
          items: [
            { text: 'Runtimes', link: '/docs/advanced/runtimes' },
            { text: 'Browser Automation', link: '/docs/advanced/browser-automation' },
            { text: 'Web Tools', link: '/docs/advanced/web-tools' },
            { text: 'MCP Integration', link: '/docs/advanced/mcp-integration' },
            { text: 'Skills', link: '/docs/advanced/skills' },
            { text: 'Subagents', link: '/docs/advanced/subagents' },
            { text: 'Project Context', link: '/docs/advanced/project-context' },
            { text: 'Observability', link: '/docs/advanced/observability' },
            { text: 'Shell Completions', link: '/docs/advanced/shell-completions' },
            { text: 'Troubleshooting', link: '/docs/advanced/troubleshooting' },
          ],
        },
        {
          text: 'Contributing',
          collapsed: true,
          items: [
            { text: 'Development Setup', link: '/docs/contributing/development-setup' },
            { text: 'Architecture', link: '/docs/contributing/architecture' },
            { text: 'Testing', link: '/docs/contributing/testing' },
          ],
        },
      ],
      '/api/': apiSidebar,
      '/changelog': changelogSidebar,
    },

    outline: [2, 3],

    search: {
      provider: 'local',
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/helgesverre/glue' },
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: `© ${new Date().getFullYear()} Glue`,
    },
  },
})
