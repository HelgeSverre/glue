import { defineConfig } from 'vitepress'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const vitepressDir = path.dirname(fileURLToPath(import.meta.url))
const apiSidebarPath = path.join(vitepressDir, 'sidebar.json')
const apiSidebar = fs.existsSync(apiSidebarPath)
  ? JSON.parse(fs.readFileSync(apiSidebarPath, 'utf-8'))
  : []

export default defineConfig({
  title: 'Glue',
  titleTemplate: ':title · Glue',
  description: 'A small terminal agent for real coding work.',
  cleanUrls: true,
  lastUpdated: true,

  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap', rel: 'stylesheet' }],
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/brand/symbol-yellow.svg' }],
    ['meta', { name: 'theme-color', content: '#0A0A0B' }],
  ],

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
              { text: 'Web Tools', link: '/web' },
              { text: 'Sessions', link: '/sessions' },
              { text: 'Roadmap', link: '/roadmap' },
              { text: 'Brand', link: '/brand' },
            ],
          },
        ],
      },
      { text: 'Models', link: '/models' },
      { text: 'Runtimes', link: '/runtimes' },
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
