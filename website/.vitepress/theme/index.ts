import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import './custom.css'

import TerminalDemo from './components/TerminalDemo.vue'
import ModelTable from './components/ModelTable.vue'
import RuntimeMatrix from './components/RuntimeMatrix.vue'
import FeatureStatus from './components/FeatureStatus.vue'
import ConfigSnippet from './components/ConfigSnippet.vue'
import InstallSnippet from './components/InstallSnippet.vue'
import Home from './components/Home.vue'

const theme: Theme = {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('TerminalDemo', TerminalDemo)
    app.component('ModelTable', ModelTable)
    app.component('RuntimeMatrix', RuntimeMatrix)
    app.component('FeatureStatus', FeatureStatus)
    app.component('ConfigSnippet', ConfigSnippet)
    app.component('InstallSnippet', InstallSnippet)
    app.component('Home', Home)
  },
}

export default theme
