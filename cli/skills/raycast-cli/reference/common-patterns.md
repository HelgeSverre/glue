# Raycast Extension Common Patterns

Real-world patterns and workflows for building Raycast extensions.

## Development Workflow Patterns

### Basic Extension Development

```bash
# Create extension via Raycast
# Open Raycast → Type "Create Extension"
# Select template or start from scratch

# Navigate to extension directory
cd ~/Developer/my-extension

# Install dependencies
pnpm install

# Start development mode
pnpm dev

# Open Raycast (Cmd + Space)
# Extension appears at top of root search
# Test commands and functionality
```

### Hot Reload Development

```bash
# Start development mode
pnpm dev

# Edit files in src/ directory
# Changes reflect immediately in Raycast
# View logs in terminal
# View errors in Raycast overlay

# Toggle hot reload in Preferences
# Raycast → Preferences → Extensions → Development
# Toggle "Auto-reload on file changes"
```

### Testing Before Build

```bash
# Test in development mode
pnpm dev

# Verify all commands work
# Check error handling
# Test edge cases
# Verify preferences work

# Run linter
pnpm lint

# Build for production
pnpm build

# Test production build in Raycast
```

## Extension Structure Patterns

### Single Command Extension

```typescript
// src/index.tsx
import { List, ActionPanel, Action, Icon } from "@raycast/api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="Item 1"
        subtitle="Description"
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

### Multi-Command Extension

```
src/
├── search.tsx           # Search command
├── create.tsx           # Create command
├── settings.tsx         # Settings command
└── utils/
    ├── api.ts           # Shared API client
    └── types.ts         # Shared types
```

```json
// package.json
{
  "commands": [
    {
      "name": "search",
      "title": "Search Items",
      "description": "Search through items",
      "mode": "view"
    },
    {
      "name": "create",
      "title": "Create Item",
      "description": "Create a new item",
      "mode": "view"
    },
    {
      "name": "settings",
      "title": "Extension Settings",
      "description": "Configure extension",
      "mode": "view"
    }
  ]
}
```

## API Integration Patterns

### Basic API Client

```typescript
// src/utils/api.ts
import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiKey: string;
  apiUrl: string;
}

export class APIClient {
  private apiKey: string;
  private apiUrl: string;

  constructor() {
    const prefs = getPreferenceValues<Preferences>();
    this.apiKey = prefs.apiKey;
    this.apiUrl = prefs.apiUrl;
  }

  async fetchData(endpoint: string) {
    const response = await fetch(`${this.apiUrl}${endpoint}`, {
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }

    return response.json();
  }
}
```

### Error Handling Pattern

```typescript
import { showToast, Toast } from "@raycast/api";

export default function Command() {
  async function fetchData() {
    try {
      const data = await api.fetchData("/items");
      // Process data
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Failed to fetch data",
        message: String(error),
      });
    }
  }

  return <List>...</List>;
}
```

### Loading States Pattern

```typescript
import { List } from "@raycast/api";
import { useState, useEffect } from "react";

export default function Command() {
  const [items, setItems] = useState<Item[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function loadData() {
      try {
        const data = await api.fetchData("/items");
        setItems(data);
      } finally {
        setIsLoading(false);
      }
    }
    loadData();
  }, []);

  return (
    <List isLoading={isLoading}>
      {items.map((item) => (
        <List.Item key={item.id} title={item.name} />
      ))}
    </List>
  );
}
```

## Data Storage Patterns

### LocalStorage for Persistence

```typescript
import { LocalStorage } from "@raycast/api";

// Save data
await LocalStorage.setItem("favorites", JSON.stringify(favoriteItems));

// Load data
const stored = await LocalStorage.getItem("favorites");
const favorites = stored ? JSON.parse(stored) : [];

// Remove data
await LocalStorage.removeItem("favorites");

// Clear all data
await LocalStorage.clear();
```

### Cache for Temporary Data

```typescript
import { Cache } from "@raycast/api";

const cache = new Cache();

// Store data (expires after session)
cache.set("searchQuery", query);

// Retrieve data
const cached = cache.get("searchQuery");

// Check if exists
const hasCache = cache.has("searchQuery");

// Remove data
cache.remove("searchQuery");

// Clear all cache
cache.clear();
```

### Favorites Pattern

```typescript
import { LocalStorage, Icon } from "@raycast/api";

export async function toggleFavorite(itemId: string) {
  const stored = await LocalStorage.getItem("favorites");
  const favorites = stored ? JSON.parse(stored) : [];

  const index = favorites.indexOf(itemId);
  if (index > -1) {
    favorites.splice(index, 1);
  } else {
    favorites.push(itemId);
  }

  await LocalStorage.setItem("favorites", JSON.stringify(favorites));
}

export async function isFavorite(itemId: string): Promise<boolean> {
  const stored = await LocalStorage.getItem("favorites");
  const favorites = stored ? JSON.parse(stored) : [];
  return favorites.includes(itemId);
}
```

## UI Component Patterns

### List with Search

```typescript
import { List } from "@raycast/api";
import { useState } from "react";

export default function Command() {
  const [searchText, setSearchText] = useState("");
  const [items, setItems] = useState<Item[]>([]);

  // Filter items based on search
  const filteredItems = items.filter((item) =>
    item.name.toLowerCase().includes(searchText.toLowerCase())
  );

  return (
    <List
      searchBarPlaceholder="Search items..."
      onSearchTextChange={setSearchText}
    >
      {filteredItems.map((item) => (
        <List.Item key={item.id} title={item.name} />
      ))}
    </List>
  );
}
```

### Detail View with Markdown

```typescript
import { Detail, ActionPanel, Action } from "@raycast/api";

export default function Command() {
  const markdown = `
# Title

## Subtitle

- Item 1
- Item 2

**Bold text** and *italic text*

\`\`\`typescript
const code = "example";
\`\`\`
  `;

  return (
    <Detail
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard content={markdown} />
        </ActionPanel>
      }
    />
  );
}
```

### Form with Validation

```typescript
import { Form, ActionPanel, Action, showToast, Toast } from "@raycast/api";
import { useState } from "react";

export default function Command() {
  const [nameError, setNameError] = useState<string | undefined>();

  function validateName(value: string | undefined) {
    if (!value || value.length === 0) {
      setNameError("Name is required");
    } else if (value.length < 3) {
      setNameError("Name must be at least 3 characters");
    } else {
      setNameError(undefined);
    }
  }

  async function handleSubmit(values: { name: string; email: string }) {
    if (nameError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Validation failed",
        message: nameError,
      });
      return;
    }

    // Process form data
    await showToast({
      style: Toast.Style.Success,
      title: "Success",
      message: "Form submitted",
    });
  }

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="name"
        title="Name"
        placeholder="Enter name"
        error={nameError}
        onChange={validateName}
        onBlur={(event) => validateName(event.target.value)}
      />
      <Form.TextField
        id="email"
        title="Email"
        placeholder="Enter email"
      />
    </Form>
  );
}
```

## Authentication Patterns

### OAuth Flow

```typescript
import { OAuth } from "@raycast/api";

const client = new OAuth.PKCEClient({
  redirectMethod: OAuth.RedirectMethod.Web,
  providerName: "GitHub",
  providerIcon: "github-logo.png",
  providerId: "github",
  description: "Connect your GitHub account",
});

export async function authorize(): Promise<string> {
  const tokenSet = await client.getTokens();
  if (tokenSet?.accessToken) {
    return tokenSet.accessToken;
  }

  const authRequest = await client.authorizationRequest({
    endpoint: "https://github.com/login/oauth/authorize",
    clientId: "your-client-id",
    scope: "repo user",
  });

  const { authorizationCode } = await client.authorize(authRequest);

  const tokens = await fetchTokens(authRequest, authorizationCode);
  await client.setTokens(tokens);

  return tokens.access_token;
}

async function fetchTokens(
  authRequest: OAuth.AuthorizationRequest,
  authCode: string
): Promise<OAuth.TokenResponse> {
  const response = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: "your-client-id",
      client_secret: "your-client-secret",
      code: authCode,
      code_verifier: authRequest.codeVerifier,
      grant_type: "authorization_code",
      redirect_uri: authRequest.redirectURI,
    }),
  });

  return response.json();
}
```

### API Key Authentication

```typescript
// Define preferences in package.json
{
  "preferences": [
    {
      "name": "apiKey",
      "type": "password",
      "required": true,
      "title": "API Key",
      "description": "Your API key from the service"
    }
  ]
}

// Use in command
import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiKey: string;
}

export default function Command() {
  const { apiKey } = getPreferenceValues<Preferences>();

  async function makeRequest() {
    const response = await fetch("https://api.example.com/data", {
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
    });
    return response.json();
  }
}
```

## Action Patterns

### Common Actions

```typescript
import { ActionPanel, Action, Icon } from "@raycast/api";

<ActionPanel>
  {/* Open URL */}
  <Action.OpenInBrowser url="https://example.com" />

  {/* Copy to clipboard */}
  <Action.CopyToClipboard content="Text to copy" />

  {/* Push new view */}
  <Action.Push
    title="View Details"
    target={<DetailView item={item} />}
    icon={Icon.Eye}
  />

  {/* Run callback */}
  <Action
    title="Delete Item"
    icon={Icon.Trash}
    onAction={async () => {
      await deleteItem(item.id);
    }}
  />

  {/* Open with specific app */}
  <Action.Open
    title="Open in VS Code"
    target="/path/to/file"
    application="Visual Studio Code"
  />

  {/* Show in Finder */}
  <Action.ShowInFinder path="/path/to/file" />
</ActionPanel>
```

### Keyboard Shortcuts

```typescript
import { ActionPanel, Action, Icon } from "@raycast/api";

<ActionPanel>
  <Action.OpenInBrowser
    url="https://example.com"
    shortcut={{ modifiers: ["cmd"], key: "o" }}
  />
  <Action.CopyToClipboard
    content="Text"
    shortcut={{ modifiers: ["cmd"], key: "c" }}
  />
  <Action
    title="Delete"
    icon={Icon.Trash}
    shortcut={{ modifiers: ["cmd"], key: "d" }}
    onAction={deleteItem}
  />
</ActionPanel>
```

## Menu Bar Extensions

### Simple Menu Bar

```typescript
import { MenuBarExtra, Icon } from "@raycast/api";

export default function Command() {
  return (
    <MenuBarExtra icon={Icon.Star} tooltip="My Extension">
      <MenuBarExtra.Item
        title="Action 1"
        onAction={() => console.log("Action 1")}
      />
      <MenuBarExtra.Item
        title="Action 2"
        onAction={() => console.log("Action 2")}
      />
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item
        title="Settings"
        onAction={() => console.log("Settings")}
      />
    </MenuBarExtra>
  );
}
```

### Dynamic Menu Bar with State

```typescript
import { MenuBarExtra, Icon } from "@raycast/api";
import { useState, useEffect } from "react";

export default function Command() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    // Update count periodically
    const interval = setInterval(() => {
      setCount((prev) => prev + 1);
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <MenuBarExtra icon={Icon.Circle} tooltip={`Count: ${count}`}>
      <MenuBarExtra.Item title={`Current Count: ${count}`} />
      <MenuBarExtra.Item
        title="Reset"
        onAction={() => setCount(0)}
      />
    </MenuBarExtra>
  );
}
```

## Background Commands

### Scheduled Background Task

```json
// package.json
{
  "commands": [
    {
      "name": "sync",
      "title": "Background Sync",
      "description": "Syncs data in background",
      "mode": "no-view",
      "interval": "1h"
    }
  ]
}
```

```typescript
// src/sync.tsx
import { LaunchType, environment, showHUD } from "@raycast/api";

export default async function Command() {
  // Check if launched in background
  if (environment.launchType === LaunchType.Background) {
    // Perform sync operation
    await syncData();
    return; // Don't show UI
  }

  // Manual launch - show notification
  await showHUD("Sync completed");
}

async function syncData() {
  // Sync logic here
  console.log("Background sync running...");
}
```

## Publishing Patterns

### Pre-Publish Checklist

```bash
# 1. Verify all commands work
pnpm dev
# Test each command thoroughly

# 2. Run linter
pnpm lint
# Fix any issues

# 3. Build extension
pnpm build
# Verify build succeeds

# 4. Add README.md
cat > README.md << 'EOF'
# Extension Name

Description

## Features
- Feature 1
- Feature 2

## Setup
1. Install extension
2. Configure preferences
EOF

# 5. Add screenshots to assets/
# Take screenshots of each command

# 6. Update package.json metadata
# Verify title, description, author

# 7. Publish
pnpm publish
```

### Version Management

```bash
# Update version in package.json
npm version patch   # 1.0.0 -> 1.0.1
npm version minor   # 1.0.0 -> 1.1.0
npm version major   # 1.0.0 -> 2.0.0

# Publish updated version
pnpm publish
```

## Performance Optimization

### Debounced Search

```typescript
import { useState, useEffect, useRef } from "react";

export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(handler);
    };
  }, [value, delay]);

  return debouncedValue;
}

// Usage in command
export default function Command() {
  const [searchText, setSearchText] = useState("");
  const debouncedSearch = useDebounce(searchText, 300);

  useEffect(() => {
    // Only search when debounced value changes
    if (debouncedSearch) {
      performSearch(debouncedSearch);
    }
  }, [debouncedSearch]);

  return <List onSearchTextChange={setSearchText}>...</List>;
}
```

### Lazy Loading

```typescript
import { List } from "@raycast/api";
import { useState, useEffect } from "react";

export default function Command() {
  const [items, setItems] = useState<Item[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [page, setPage] = useState(1);

  async function loadMore() {
    setIsLoading(true);
    const newItems = await fetchPage(page);
    setItems([...items, ...newItems]);
    setPage(page + 1);
    setIsLoading(false);
  }

  return (
    <List
      isLoading={isLoading}
      onSelectionChange={(id) => {
        // Load more when near end
        if (id === items[items.length - 1]?.id) {
          loadMore();
        }
      }}
    >
      {items.map((item) => (
        <List.Item key={item.id} title={item.name} />
      ))}
    </List>
  );
}
```

## Testing Patterns

### Manual Testing Workflow

```bash
# 1. Start development mode
pnpm dev

# 2. Open Raycast
# Extension appears at top

# 3. Test each command
# - Happy path
# - Error cases
# - Edge cases

# 4. Test preferences
# - Open extension preferences
# - Verify all settings work

# 5. Test keyboard shortcuts
# - Verify all shortcuts work
# - No conflicts with system shortcuts

# 6. Check console logs
# View terminal for logs and errors
```

### Debug Logging

```typescript
// Development logging
if (environment.isDevelopment) {
  console.log("Debug info:", data);
}

// Always log errors
console.error("Error occurred:", error);

// Log with context
console.log(`[${environment.commandName}] Processing item ${id}`);
```
