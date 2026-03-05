# Raycast CLI Commands Reference

Complete reference for all Raycast CLI commands with detailed options and flags.

## Installation & Setup

### Prerequisites

```bash
# Check prerequisites
node --version          # Required: Node.js 22.14 or higher
open -a Raycast        # Required: Raycast 1.26.0 or higher

# Create new extension
# Open Raycast → Type "Create Extension"
# Follow wizard to generate project structure
```

### Package Manager Installation

```bash
# Install dependencies
npm install

# Or with pnpm (recommended)
pnpm install

# Or with yarn
yarn install
```

## Core CLI Commands

### `npx ray help`

Display all available CLI commands and their descriptions.

```bash
# Show all commands
npx ray help

# Get help for specific command
npx ray help develop
npx ray help build
npx ray help publish
```

### `npx ray develop`

Start development mode with hot-reloading and debugging features.

```bash
# Start development mode
npx ray develop

# Development mode features:
# - Extension appears at top of root search
# - Auto-reloading on file changes (toggleable in Preferences)
# - Detailed error overlays with stack traces
# - Terminal log message display
# - Build status indicator in navigation
# - Automatic extension import to Raycast

# Alternative npm scripts
npm run dev
pnpm dev
yarn dev
```

**Development Features:**
- Hot reload on file changes
- Error overlays with stack traces
- Terminal log streaming
- Build status indicator
- Automatic import to Raycast

### `npx ray build`

Create optimized production build for distribution.

```bash
# Build extension for production
npx ray build

# Build with validation of distribution directory
npx ray build -e dist

# Verify extension without publishing
npm run build

# Alternative npm scripts
pnpm build
yarn build
```

**Build Process:**
- TypeScript compilation
- Dependency bundling
- Asset optimization
- Validation checks
- Distribution preparation

### `npx ray lint`

Run ESLint for all files in the `src` directory.

```bash
# Run linter
npx ray lint

# Check code style and errors
npm run lint
pnpm lint
yarn lint

# Fix issues automatically (if ESLint configured)
npm run lint -- --fix
pnpm lint --fix
yarn lint --fix
```

### `npx ray migrate`

Migrate extension to latest `@raycast/api` version.

```bash
# Migrate to latest API version
npx ray migrate

# What it does:
# - Updates package.json dependencies
# - Migrates deprecated code patterns
# - Updates API usage to latest conventions
# - Provides migration report

# After migration, review changes and test
pnpm dev
pnpm build
```

### `npx ray publish`

Verify, build, and publish extension.

```bash
# Publish extension
npx ray publish

# For public extensions:
# - Authenticates with GitHub
# - Creates pull request in raycast/extensions repo
# - Triggers automated checks
# - Awaits team review and merge

# For private extensions:
# - Publishes to organization's private store
# - Requires organization membership

# Alternative npm scripts
npm run publish
pnpm publish
yarn publish
```

**Publish Prerequisites:**
- Complete `package.json` metadata
- README.md with description
- Screenshots in `assets/` directory
- Working production build
- All tests passing

## Global Options

All Raycast CLI commands support these options:

```bash
# Show CLI version
npx ray --version

# Get help
npx ray --help

# Verbose output (if supported)
npx ray develop --verbose
npx ray build --verbose
```

## Extension Structure Files

### package.json

Main configuration file for extension metadata and commands.

```json
{
  "name": "my-extension",
  "title": "My Extension",
  "description": "Extension description",
  "icon": "icon.png",
  "author": "yourname",
  "license": "MIT",
  "commands": [
    {
      "name": "index",
      "title": "Command Title",
      "description": "Command description",
      "mode": "view"
    }
  ],
  "preferences": [
    {
      "name": "apiKey",
      "type": "password",
      "required": true,
      "title": "API Key",
      "description": "Your API key"
    }
  ],
  "dependencies": {
    "@raycast/api": "^1.48.0"
  },
  "devDependencies": {
    "@types/node": "^18.8.3",
    "@types/react": "^18.0.9",
    "typescript": "^4.4.3"
  },
  "scripts": {
    "build": "ray build -e dist",
    "dev": "ray develop",
    "lint": "ray lint"
  }
}
```

**Command Modes:**
- `view` - Full UI with components (List, Detail, Form)
- `no-view` - Background task without UI
- `menu-bar` - Menu bar extra command

**Preference Types:**
- `textfield` - Single line text
- `password` - Password field (encrypted storage)
- `checkbox` - Boolean toggle
- `dropdown` - Select from options

### tsconfig.json

TypeScript configuration for extension development.

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "jsx": "react",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

### README.md

Extension documentation for the Raycast Store.

```markdown
# Extension Name

Short description of what the extension does.

## Features

- Feature 1
- Feature 2
- Feature 3

## Setup

1. Get API key from service
2. Install extension from Raycast Store
3. Configure API key in extension preferences

## Usage

- Command 1 - Description
- Command 2 - Description
```

### Assets Structure

```
assets/
├── icon.png              # Extension icon (512x512, PNG)
├── screenshot-1.png      # Command screenshot (required)
├── screenshot-2.png      # Additional screenshots (optional)
└── command-icon.png      # Custom command icons (optional)
```

**Asset Requirements:**
- Extension icon: 512x512 PNG
- Screenshots: min 1, max 4
- Supported formats: PNG, JPG

## Raycast Extension Commands

Commands available through Raycast interface (not CLI).

### Create Extension

```bash
# Via Raycast search
# Type: "Create Extension"
# Options:
# - Start from template
# - Start from scratch
# - Browse template gallery
```

### Import Extension

```bash
# Via Raycast search
# Type: "Import Extension"
# Browse to extension source directory
# Extension appears in development mode
```

### Manage Extensions

```bash
# Via Raycast search
# Type: "Manage Extensions"
# View published extensions
# Edit extension metadata
# View analytics and usage
```

### Extension Store

```bash
# Via Raycast search
# Type: "Store"
# Browse and install published extensions
# Search by category or keyword
```

## Environment Variables

### Available at Runtime

```typescript
import { environment } from "@raycast/api";

// Raycast version
environment.raycastVersion: string

// Extension information
environment.extensionName: string
environment.commandName: string
environment.commandMode: "view" | "no-view" | "menu-bar"

// User preferences
environment.appearance: "dark" | "light"
environment.textSize: "medium" | "large"

// Paths
environment.assetsPath: string        // Path to assets/ directory
environment.supportPath: string       // Path for extension data storage

// Development flag
environment.isDevelopment: boolean    // true in dev mode

// Launch context
environment.launchType: LaunchType    // UserInitiated | Background
```

### Using Preferences

```typescript
import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiKey: string;
  theme: string;
  enableNotifications: boolean;
}

export default function Command() {
  const prefs = getPreferenceValues<Preferences>();
  console.log(prefs.apiKey);
  console.log(prefs.theme);
}
```

## ESLint Configuration

### Installing Raycast ESLint Config

```bash
# Install ESLint configuration
pnpm add -D @raycast/eslint-config eslint

# Create .eslintrc.js
cat > .eslintrc.js << 'EOF'
module.exports = {
  extends: "@raycast"
};
EOF

# Run linter
pnpm lint

# Fix issues automatically
pnpm lint --fix
```

### Custom ESLint Rules

```javascript
// .eslintrc.js
module.exports = {
  extends: "@raycast",
  rules: {
    // Add custom rules here
    "no-console": "warn",
    "@typescript-eslint/explicit-module-boundary-types": "off"
  }
};
```

## API Modules Reference

### UI Components

```typescript
import {
  List,              // List view with items
  Detail,            // Markdown detail view
  Form,              // Form with inputs
  Action,            // Action in ActionPanel
  ActionPanel,       // Panel with actions
  Icon,              // Built-in icons
  Color,             // Built-in colors
  MenuBarExtra,      // Menu bar dropdown
  Grid,              // Grid view
} from "@raycast/api";
```

### Utilities

```typescript
import {
  showToast,         // Show toast notification
  Toast,             // Toast configuration
  Clipboard,         // Clipboard operations
  showHUD,           // Show HUD overlay
  closeMainWindow,   // Close Raycast window
  popToRoot,         // Navigate to root
  openExtensionPreferences,  // Open preferences
  getSelectedText,   // Get selected text
  getSelectedFinderItems,    // Get Finder selection
} from "@raycast/api";
```

### Data Storage

```typescript
import {
  LocalStorage,      // Key-value storage
  Cache,             // Temporary cache
} from "@raycast/api";
```

### Authentication

```typescript
import {
  OAuth,             // OAuth authentication
} from "@raycast/api";
```

### System Integration

```typescript
import {
  open,              // Open URL or file
  trash,             // Move to trash
  showInFinder,      // Show in Finder
  getApplications,   // List installed apps
} from "@raycast/api";
```

## Command Flags and Options

### Build Flags

```bash
# Specify output directory
npx ray build -e dist
npx ray build --export dist

# Enable verbose logging
npx ray build --verbose
```

### Publish Flags

```bash
# Publish to specific organization
npx ray publish --org my-org

# Skip validation (not recommended)
npx ray publish --skip-validation
```

### Development Flags

```bash
# Watch mode (default in develop)
npx ray develop

# Specify port (if applicable)
npx ray develop --port 3000
```

## Version Information

```bash
# Show installed CLI version
npx ray --version

# Show installed API version
cat package.json | grep "@raycast/api"

# Check for updates
npm outdated @raycast/api
pnpm outdated @raycast/api
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Publish Extension

on:
  push:
    branches: [main]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: actions/setup-node@v3
        with:
          node-version: "18"

      - name: Install dependencies
        run: npm install

      - name: Lint extension
        run: npm run lint

      - name: Build extension
        run: npm run build

      - name: Publish to Raycast
        env:
          RAYCAST_TOKEN: ${{ secrets.RAYCAST_TOKEN }}
        run: npm run publish
```

### CI Best Practices

```bash
# Always use package-lock.json
# Raycast CI uses npm by default
npm install

# Ensure consistent versions
# CI should match local environment

# Run all checks before publish
npm run lint && npm run build && npm run publish

# Test locally before CI
npm run lint
npm run build
```
