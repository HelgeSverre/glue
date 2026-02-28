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
  description: 'API Reference for the Glue coding agent',

  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700;800&display=swap', rel: 'stylesheet' }],
  ],

  themeConfig: {
    siteTitle: 'GLUE',

    nav: [
      { text: 'API Reference', link: '/api/' },
      { text: 'Website', link: 'https://glue.dev' },
      { text: 'GitHub', link: 'https://github.com/helgesverre/glue' },
    ],

    sidebar: {
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
