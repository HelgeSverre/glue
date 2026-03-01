import { defineConfig } from 'vitepress'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

// Import generated sidebar (falls back to empty if not yet generated)
const vitepressDir = path.dirname(fileURLToPath(import.meta.url))
const sidebarPath = path.join(vitepressDir, 'sidebar.json')
const sidebar = fs.existsSync(sidebarPath)
  ? JSON.parse(fs.readFileSync(sidebarPath, 'utf-8'))
  : []

export default defineConfig({
  title: 'Glue',
  description: 'Documentation for the Glue coding agent',

  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700;800&display=swap', rel: 'stylesheet' }],
  ],

  themeConfig: {
    siteTitle: 'GLUE',

    nav: [
      { text: 'Guide', link: '/guide/getting-started/installation' },
      { text: 'API Reference', link: '/api/' },
      { text: 'Website', link: 'https://glue.dev' },
      { text: 'GitHub', link: 'https://github.com/helgesverre/glue' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Getting Started',
          items: [
            { text: 'Installation', link: '/guide/getting-started/installation' },
            { text: 'Quick Start', link: '/guide/getting-started/quick-start' },
            { text: 'Configuration', link: '/guide/getting-started/configuration' },
          ],
        },
        {
          text: 'Using Glue',
          items: [
            { text: 'Interactive Mode', link: '/guide/using-glue/interactive-mode' },
            { text: 'Bash Mode', link: '/guide/using-glue/bash-mode' },
            { text: 'File References', link: '/guide/using-glue/file-references' },
            { text: 'Models & Providers', link: '/guide/using-glue/models-and-providers' },
            { text: 'Built-in Tools', link: '/guide/using-glue/built-in-tools' },
            { text: 'Tool Approval', link: '/guide/using-glue/tool-approval' },
            { text: 'Sessions & Resume', link: '/guide/using-glue/sessions' },
            { text: 'Worktrees', link: '/guide/using-glue/worktrees' },
            { text: 'Docker Sandbox', link: '/guide/using-glue/docker-sandbox' },
          ],
        },
        {
          text: 'Advanced',
          items: [
            { text: 'Project Context', link: '/guide/advanced/project-context' },
            { text: 'Subagents', link: '/guide/advanced/subagents' },
            { text: 'Skills', link: '/guide/advanced/skills' },
            { text: 'Web Tools', link: '/guide/advanced/web-tools' },
            { text: 'Browser Automation', link: '/guide/advanced/browser-automation' },
            { text: 'Observability', link: '/guide/advanced/observability' },
            { text: 'Shell Completions', link: '/guide/advanced/shell-completions' },
            { text: 'MCP Integration', link: '/guide/advanced/mcp-integration' },
          ],
        },
        {
          text: 'Contributing',
          collapsed: true,
          items: [
            { text: 'Architecture Overview', link: '/guide/contributing/architecture' },
            { text: 'Development Setup', link: '/guide/contributing/development-setup' },
            { text: 'Testing', link: '/guide/contributing/testing' },
          ],
        },
      ],
      '/api/': sidebar,
    },

    search: {
      provider: 'local',
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/helgesverre/glue' },
    ],
  },
})
