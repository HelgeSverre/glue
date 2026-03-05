# Raycast Extension Troubleshooting Guide

Common issues and solutions for Raycast extension development and deployment.

## Extension Development Issues

### Extension Not Appearing in Raycast

**Symptom:** Extension doesn't show up after running `pnpm dev`

**Diagnosis:**
```bash
# Check if dev mode is running
pnpm dev
# Look for success message in terminal

# Check Raycast development settings
# Raycast → Preferences → Extensions → Development
# Verify "Show Development Extensions" is enabled

# Check for build errors in terminal
# Look for TypeScript or build errors
```

**Solutions:**
```bash
# Restart development mode
# Press Ctrl+C to stop
pnpm dev

# Restart Raycast
# Cmd+Q to quit Raycast completely
# Open Raycast again

# Verify package.json is valid
cat package.json | jq .
# Should parse without errors

# Check extension location
# Raycast only loads from specific locations
pwd
# Should be in ~/Developer or configured location

# Re-import extension manually
# Raycast → Type "Import Extension"
# Browse to extension directory
```

### Hot Reload Not Working

**Symptom:** Changes to code don't reflect in Raycast

**Diagnosis:**
```bash
# Check if auto-reload is enabled
# Raycast → Preferences → Extensions → Development
# "Auto-reload on file changes" should be ON

# Check terminal for rebuild messages
# Should see "Rebuilding..." on file save

# Check for TypeScript errors
# Errors can prevent rebuild
```

**Solutions:**
```bash
# Toggle auto-reload
# Raycast → Preferences → Extensions → Development
# Toggle "Auto-reload on file changes" OFF and ON

# Restart development mode
# Ctrl+C to stop
pnpm dev

# Clear Raycast cache
# Raycast → Settings → Advanced → Clear Cache
# Restart Raycast after clearing

# Manually reload extension
# Cmd+R in Raycast to reload current extension
```

### TypeScript Errors in Development

**Symptom:** TypeScript compilation errors in terminal

**Diagnosis:**
```bash
# Check TypeScript version
npx tsc --version

# View full error details
pnpm dev
# Read error messages carefully

# Check tsconfig.json
cat tsconfig.json
# Verify configuration is valid
```

**Solutions:**
```bash
# Update @raycast/api to latest
pnpm update @raycast/api

# Run migration tool
npx ray migrate

# Fix import statements
# Ensure all imports are from @raycast/api
import { List } from "@raycast/api";

# Check for missing type definitions
pnpm add -D @types/node @types/react

# Verify tsconfig.json settings
cat > tsconfig.json << 'EOF'
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
EOF
```

### Build Errors

**Symptom:** `pnpm build` fails with errors

**Common Errors:**

**Error: "Cannot find module '@raycast/api'"**
```bash
# Solution: Install dependencies
rm -rf node_modules package-lock.json
pnpm install

# Verify @raycast/api is in dependencies
cat package.json | grep "@raycast/api"
```

**Error: "Invalid package.json"**
```bash
# Solution: Validate JSON syntax
cat package.json | jq .

# Check required fields
# - name, title, description, icon
# - commands array
# - dependencies with @raycast/api

# Fix with valid package.json structure
```

**Error: "Missing assets"**
```bash
# Solution: Add required assets
ls assets/
# Should have icon.png (512x512)

# Add icon if missing
# Create 512x512 PNG icon
# Save to assets/icon.png

# Update package.json
# "icon": "icon.png"
```

### Runtime Errors

**Symptom:** Extension crashes or shows error overlay

**Diagnosis:**
```bash
# Check terminal logs
pnpm dev
# View error messages and stack traces

# Check error overlay in Raycast
# Shows detailed error with stack trace
# Click for more details

# Check browser console (if using web)
# Right-click error overlay → Inspect Element
```

**Solutions:**
```typescript
// Add error handling
try {
  const data = await fetchData();
} catch (error) {
  console.error("Error:", error);
  await showToast({
    style: Toast.Style.Failure,
    title: "Error",
    message: String(error),
  });
}

// Validate data before use
if (!data || !Array.isArray(data)) {
  throw new Error("Invalid data format");
}

// Handle async operations properly
useEffect(() => {
  let isMounted = true;

  async function loadData() {
    try {
      const result = await fetchData();
      if (isMounted) {
        setData(result);
      }
    } catch (error) {
      console.error(error);
    }
  }

  loadData();
  return () => { isMounted = false; };
}, []);
```

## API Integration Issues

### API Authentication Fails

**Symptom:** API requests return 401 Unauthorized

**Diagnosis:**
```bash
# Check if API key is set
# Raycast → Extension Preferences
# Verify API key is configured

# Test API key manually
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://api.example.com/test
```

**Solutions:**
```typescript
// Validate API key before use
import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiKey: string;
}

const { apiKey } = getPreferenceValues<Preferences>();

if (!apiKey || apiKey.trim() === "") {
  await showToast({
    style: Toast.Style.Failure,
    title: "API Key Required",
    message: "Please configure your API key in preferences",
  });
  return;
}

// Include proper headers
const response = await fetch(url, {
  headers: {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  },
});
```

### API Requests Timing Out

**Symptom:** Requests hang or timeout

**Solutions:**
```typescript
// Add timeout to fetch requests
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 10000); // 10s timeout

try {
  const response = await fetch(url, {
    signal: controller.signal,
  });
  clearTimeout(timeoutId);
  return response.json();
} catch (error) {
  if (error.name === "AbortError") {
    throw new Error("Request timeout");
  }
  throw error;
}

// Show loading state
const [isLoading, setIsLoading] = useState(true);

useEffect(() => {
  const fetchData = async () => {
    try {
      const data = await api.fetchData();
      setData(data);
    } finally {
      setIsLoading(false);
    }
  };
  fetchData();
}, []);

return <List isLoading={isLoading}>...</List>;
```

### CORS Errors

**Symptom:** API requests fail with CORS error

**Diagnosis:**
```bash
# Check browser console (if applicable)
# CORS errors appear in browser console

# Test API with curl
curl -I https://api.example.com/endpoint
# Check Access-Control-Allow-Origin header
```

**Solutions:**
```typescript
// Raycast extensions run in Node.js context
// CORS doesn't apply to server-side requests

// If seeing CORS errors:
// 1. Check if using browser-only API
// 2. Use Node.js fetch (built-in in Node 18+)
// 3. Don't use browser-specific APIs

// Correct approach for Raycast
const response = await fetch(url); // Works in Node.js

// Incorrect approach
// window.fetch() // Not available in Raycast
```

## Data Storage Issues

### LocalStorage Not Persisting

**Symptom:** Data lost between sessions

**Diagnosis:**
```typescript
// Check if data is being saved
await LocalStorage.setItem("key", "value");
console.log("Saved:", await LocalStorage.getItem("key"));

// Check for errors
try {
  await LocalStorage.setItem("key", JSON.stringify(data));
} catch (error) {
  console.error("Storage error:", error);
}
```

**Solutions:**
```typescript
// Ensure proper serialization
// LocalStorage only stores strings
await LocalStorage.setItem("data", JSON.stringify(complexObject));

// Retrieve and parse
const stored = await LocalStorage.getItem("data");
const data = stored ? JSON.parse(stored) : defaultValue;

// Handle parse errors
try {
  const data = JSON.parse(stored);
} catch (error) {
  console.error("Failed to parse stored data:", error);
  // Use default value
  const data = defaultValue;
}

// Check storage limits
// Avoid storing extremely large data
const dataSize = new Blob([stored]).size;
if (dataSize > 1000000) { // 1MB
  console.warn("Stored data is very large:", dataSize);
}
```

### Cache Not Working

**Symptom:** Cache data not retrieved correctly

**Solutions:**
```typescript
// Create cache instance properly
import { Cache } from "@raycast/api";

const cache = new Cache();

// Store data
cache.set("key", JSON.stringify(data));

// Retrieve data
const cached = cache.get("key");
if (cached) {
  const data = JSON.parse(cached);
}

// Check if key exists
if (cache.has("key")) {
  const data = JSON.parse(cache.get("key"));
}

// Clear specific key
cache.remove("key");

// Clear all cache
cache.clear();

// Note: Cache is temporary and cleared between sessions
// Use LocalStorage for persistent data
```

## UI Component Issues

### List Items Not Rendering

**Symptom:** List appears empty despite having data

**Diagnosis:**
```typescript
// Add debug logging
console.log("Items:", items);
console.log("Items length:", items.length);

// Check if items is array
console.log("Is array:", Array.isArray(items));

// Check for rendering errors
// Look at error overlay or terminal
```

**Solutions:**
```typescript
// Ensure items is array
const [items, setItems] = useState<Item[]>([]);

// Add fallback for empty state
<List>
  {items.length === 0 ? (
    <List.EmptyView
      title="No items found"
      description="Try adjusting your search"
    />
  ) : (
    items.map((item) => (
      <List.Item key={item.id} title={item.name} />
    ))
  )}
</List>

// Add key prop to items
items.map((item) => (
  <List.Item key={item.id} title={item.name} />
))

// Check data structure
interface Item {
  id: string;
  name: string;
}
```

### Form Validation Not Working

**Symptom:** Form submits with invalid data

**Solutions:**
```typescript
// Add proper validation
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

// Use onBlur for validation
<Form.TextField
  id="name"
  title="Name"
  error={nameError}
  onChange={validateName}
  onBlur={(event) => validateName(event.target.value)}
/>

// Prevent submission if invalid
async function handleSubmit(values: FormValues) {
  if (nameError) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Validation failed",
      message: nameError,
    });
    return;
  }
  // Process valid data
}
```

### Actions Not Triggering

**Symptom:** Clicking action does nothing

**Solutions:**
```typescript
// Use correct action syntax
<ActionPanel>
  <Action
    title="My Action"
    onAction={async () => {
      console.log("Action triggered");
      await performAction();
    }}
  />
</ActionPanel>

// Add error handling in actions
<Action
  title="Delete"
  onAction={async () => {
    try {
      await deleteItem();
      await showToast({
        style: Toast.Style.Success,
        title: "Deleted",
      });
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Error",
        message: String(error),
      });
    }
  }}
/>

// Check for async issues
// Always use async/await for actions
<Action
  onAction={async () => {
    await someAsyncOperation();
  }}
/>
```

## Publishing Issues

### Publish Command Fails

**Symptom:** `pnpm publish` fails with error

**Common Errors:**

**Error: "Missing README.md"**
```bash
# Solution: Add README.md
cat > README.md << 'EOF'
# Extension Name

Description of what this extension does.

## Features

- Feature 1
- Feature 2
EOF
```

**Error: "Missing screenshots"**
```bash
# Solution: Add screenshots to assets/
# Take screenshots of each command
# Save as PNG in assets/ directory
# Must have at least 1 screenshot

ls assets/
# Should contain:
# - icon.png (required)
# - screenshot-1.png (required)
# - screenshot-2.png (optional)
```

**Error: "Invalid metadata"**
```bash
# Solution: Verify package.json
cat package.json | jq .

# Check required fields:
# - name (lowercase, no spaces)
# - title (display name)
# - description (clear description)
# - icon (points to assets/icon.png)
# - author (your name or username)
# - commands (at least one command)
```

**Error: "Build failed"**
```bash
# Solution: Fix build errors first
pnpm build
# Resolve all errors

# Then publish
pnpm publish
```

### Authentication Issues

**Symptom:** Cannot authenticate for publishing

**Solutions:**
```bash
# For public extensions
# Authenticate with GitHub
# Follow prompts in terminal

# For private extensions
# Ensure you're member of organization
# Contact organization admin if needed

# Check authentication status
# Try publishing again
pnpm publish
```

### Pull Request Not Created

**Symptom:** Publish succeeds but no PR created

**Solutions:**
```bash
# Check GitHub authentication
# Re-run publish command
pnpm publish

# Manually create PR
# 1. Fork raycast/extensions on GitHub
# 2. Clone your fork
# 3. Copy extension to extensions/ directory
# 4. Commit and push
# 5. Create PR from your fork

# Check for automated checks
# Wait for CI/CD to complete
# Fix any failing checks
```

## Performance Issues

### Extension Slow to Load

**Symptom:** Extension takes long time to open

**Solutions:**
```typescript
// Optimize data loading
// Load data asynchronously
useEffect(() => {
  async function loadData() {
    const data = await fetchData();
    setData(data);
  }
  loadData();
}, []);

// Use pagination for large datasets
const [items, setItems] = useState<Item[]>([]);
const [page, setPage] = useState(1);
const ITEMS_PER_PAGE = 50;

// Load only visible items
const visibleItems = items.slice(0, page * ITEMS_PER_PAGE);

// Use debouncing for search
import { useDebounce } from "./utils";

const [searchText, setSearchText] = useState("");
const debouncedSearch = useDebounce(searchText, 300);

useEffect(() => {
  if (debouncedSearch) {
    performSearch(debouncedSearch);
  }
}, [debouncedSearch]);

// Cache expensive computations
import { Cache } from "@raycast/api";

const cache = new Cache();

async function getData() {
  const cached = cache.get("data");
  if (cached) {
    return JSON.parse(cached);
  }

  const data = await fetchData();
  cache.set("data", JSON.stringify(data));
  return data;
}
```

### Search Performance Issues

**Symptom:** Search is slow or unresponsive

**Solutions:**
```typescript
// Implement debouncing
function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => clearTimeout(handler);
  }, [value, delay]);

  return debouncedValue;
}

// Use in search
const [searchText, setSearchText] = useState("");
const debouncedSearch = useDebounce(searchText, 300);

// Index data for faster search
const searchIndex = useMemo(() => {
  return items.map(item => ({
    id: item.id,
    searchableText: `${item.name} ${item.description}`.toLowerCase(),
  }));
}, [items]);

// Filter using index
const filtered = useMemo(() => {
  const query = debouncedSearch.toLowerCase();
  return searchIndex
    .filter(item => item.searchableText.includes(query))
    .map(item => items.find(i => i.id === item.id))
    .filter(Boolean);
}, [debouncedSearch, searchIndex]);
```

## Debugging Tips

### Enable Detailed Logging

```typescript
// Log to terminal (visible in pnpm dev)
console.log("Debug info:", data);
console.error("Error:", error);
console.warn("Warning:", warning);

// Conditional logging
if (environment.isDevelopment) {
  console.log("Development mode:", data);
}

// Log with context
console.log(`[${environment.commandName}] Processing:`, data);
```

### Use Error Boundaries

```typescript
// Wrap components in try-catch
export default function Command() {
  const [error, setError] = useState<Error | null>(null);

  if (error) {
    return (
      <Detail
        markdown={`# Error\n\n${error.message}\n\n\`\`\`\n${error.stack}\`\`\``}
      />
    );
  }

  try {
    return <MainView />;
  } catch (err) {
    setError(err as Error);
    return null;
  }
}
```

### Inspect Extension State

```typescript
// Log environment
console.log("Environment:", environment);

// Log preferences
const prefs = getPreferenceValues();
console.log("Preferences:", prefs);

// Log cache state
console.log("Cache has data:", cache.has("key"));

// Log localStorage
const stored = await LocalStorage.allItems();
console.log("LocalStorage:", stored);
```

## Getting Help

### Resources

```bash
# Official documentation
open https://developers.raycast.com

# API reference
open https://developers.raycast.com/api-reference

# Community examples
open https://github.com/raycast/extensions

# Community forum
open https://raycast.com/community

# Report bugs
open https://github.com/raycast/extensions/issues
```

### Common Debug Commands

```bash
# View extension logs
pnpm dev
# Watch terminal output

# Clear Raycast cache
# Raycast → Settings → Advanced → Clear Cache

# Restart Raycast
# Cmd+Q to quit
# Reopen Raycast

# Check Node.js version
node --version
# Should be 22.14 or higher

# Check Raycast version
# Raycast → About Raycast
# Should be 1.26.0 or higher

# Reinstall dependencies
rm -rf node_modules package-lock.json
pnpm install
```
