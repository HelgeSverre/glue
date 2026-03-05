---
name: raycast-cli
description: Raycast CLI expert for extension development. Use when users need to create, develop, test, or publish Raycast extensions.
---

# Raycast CLI Guide

Raycast is a productivity platform that allows developers to build custom extensions using TypeScript and React. This guide provides essential workflows and quick references for creating and publishing Raycast extensions.

## Quick Start

```bash
# Check prerequisites
node --version          # Required: Node.js 22.14+
open -a Raycast        # Required: Raycast 1.26.0+

# Create extension via Raycast
# Open Raycast → Type "Create Extension"

# Install dependencies
pnpm install

# Start development
pnpm dev

# Test in Raycast
# Open Raycast (Cmd + Space)
# Extension appears at top of search
```

## Common Workflows

### Workflow 1: Create New Extension

```bash
# Create extension via Raycast
# Open Raycast → Type "Create Extension"
# Choose template or start from scratch

# Navigate to extension directory
cd ~/Developer/my-extension

# Install dependencies
pnpm install

# Start development
pnpm dev

# Open Raycast to test
# Extension appears at top of root search
```

### Workflow 2: Development with Hot Reload

```bash
# Start development mode
pnpm dev

# Edit files in src/ directory
# Changes reflect immediately in Raycast
# View logs in terminal
# View errors in Raycast overlay

# Toggle hot reload if needed
# Raycast → Preferences → Extensions → Development
# "Auto-reload on file changes"
```

### Workflow 3: Build and Publish Extension

```bash
# Run linter
pnpm lint

# Build for production
pnpm build

# Add README and screenshots
cat > README.md << 'EOF'
# Extension Name
Description and usage
EOF

# Add screenshots to assets/
# Take screenshots of each command

# Publish to Raycast Store
pnpm publish

# For public extensions:
# - Authenticates with GitHub
# - Creates PR in raycast/extensions repo
# - Awaits team review
```

### Workflow 4: API Integration

```bash
# Add API preferences to package.json
# Configure authentication in preferences

# Start development
pnpm dev

# Test API integration
# View logs in terminal
# Handle errors with showToast

# Build and test
pnpm build
```

### Workflow 5: Debug Extension Issues

```bash
# Check for errors
pnpm dev
# View terminal for build/runtime errors

# Check error overlay in Raycast
# Shows stack trace and details

# Restart Raycast if needed
# Cmd+Q → Reopen Raycast

# Clear cache if needed
# Raycast → Settings → Advanced → Clear Cache
```

## Decision Tree

**When to use which command:**

- **To create a new extension**: Use Raycast "Create Extension" command
- **To start development**: Use `pnpm dev` or `npx ray develop`
- **To test changes**: Hot reload in dev mode (automatic)
- **To run linter**: Use `pnpm lint` or `npx ray lint`
- **To build for production**: Use `pnpm build` or `npx ray build`
- **To update API version**: Use `npx ray migrate`
- **To publish extension**: Use `pnpm publish` or `npx ray publish`
- **For detailed command syntax**: See [Commands Reference](./reference/commands-reference.md)
- **For complex patterns**: See [Common Patterns](./reference/common-patterns.md)
- **For troubleshooting**: See [Troubleshooting Guide](./reference/troubleshooting.md)

## Common Patterns

### Extension Structure

```
my-extension/
├── package.json          # Extension metadata
├── tsconfig.json         # TypeScript config
├── README.md             # Documentation
├── assets/
│   ├── icon.png          # 512x512 icon
│   └── screenshot-1.png  # Screenshots
└── src/
    └── index.tsx         # Main command
```

### Basic Command

```typescript
import { List, ActionPanel, Action, Icon } from "@raycast/api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="Item"
        icon={Icon.Star}
        actions={
          <ActionPanel>
            <Action.OpenInBrowser url="https://example.com" />
          </ActionPanel>
        }
      />
    </List>
  );
}
```

### API Integration

```typescript
import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiKey: string;
}

const { apiKey } = getPreferenceValues<Preferences>();

async function fetchData() {
  const response = await fetch("https://api.example.com/data", {
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  });
  return response.json();
}
```

### Error Handling

```typescript
import { showToast, Toast } from "@raycast/api";

try {
  const data = await fetchData();
} catch (error) {
  await showToast({
    style: Toast.Style.Failure,
    title: "Error",
    message: String(error),
  });
}
```

### Data Persistence

```typescript
import { LocalStorage } from "@raycast/api";

// Save data
await LocalStorage.setItem("favorites", JSON.stringify(items));

// Load data
const stored = await LocalStorage.getItem("favorites");
const favorites = stored ? JSON.parse(stored) : [];
```

## Troubleshooting

**Common Issues:**

1. **Extension not appearing in Raycast**
   - Solution: Restart dev mode with `pnpm dev`
   - See: [Extension Not Appearing](./reference/troubleshooting.md#extension-not-appearing-in-raycast)

2. **Hot reload not working**
   - Quick fix: Toggle auto-reload in Preferences → Extensions → Development
   - See: [Hot Reload Not Working](./reference/troubleshooting.md#hot-reload-not-working)

3. **Build errors**
   - Quick fix: Run `pnpm install` and verify `tsconfig.json`
   - See: [Build Errors](./reference/troubleshooting.md#build-errors)

4. **API authentication fails**
   - Quick fix: Verify API key is configured in extension preferences
   - See: [API Authentication Fails](./reference/troubleshooting.md#api-authentication-fails)

5. **Extension crashes**
   - Quick fix: Add error handling with try-catch and showToast
   - See: [Runtime Errors](./reference/troubleshooting.md#runtime-errors)

For detailed troubleshooting steps, see the [Troubleshooting Guide](./reference/troubleshooting.md).

## Reference Files

**Load as needed for detailed information:**

- **[Commands Reference](./reference/commands-reference.md)** - Complete CLI command documentation with all flags, options, and configuration files. Use when you need exact syntax, package.json structure, tsconfig settings, or ESLint configuration.

- **[Common Patterns](./reference/common-patterns.md)** - Real-world patterns for development workflows, API integration, UI components, authentication, data storage, menu bar extensions, background commands, and publishing. Use for implementing specific features or workflows.

- **[Troubleshooting Guide](./reference/troubleshooting.md)** - Detailed error messages, diagnosis steps, and resolution strategies for development, build, runtime, API, storage, UI, publishing, and performance issues. Use when encountering errors or unexpected behavior.

**When to use each reference:**

- Use **Commands Reference** when you need exact syntax, package.json structure, API module imports, or configuration file formats
- Use **Common Patterns** for implementing search, forms, OAuth, menu bar extensions, background tasks, or optimization strategies
- Use **Troubleshooting** when extensions won't load, hot reload fails, builds error, API requests fail, or UI components don't render

## Resources

- Official Docs: https://developers.raycast.com
- API Reference: https://developers.raycast.com/api-reference
- Extensions Store: https://raycast.com/store
- GitHub Examples: https://github.com/raycast/extensions
- Community Forum: https://raycast.com/community
