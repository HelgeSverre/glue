---
name: profiling-native
description: Use when profiling Rust or Go applications — finding CPU hotspots, diagnosing memory issues, reading flamegraphs, or optimizing compiled code. Triggers on requests to profile, optimize, find bottlenecks, reduce allocations, or analyze performance of Rust or Go programs.
---

# Native Application Profiling (Rust & Go)

## The Workflow (Both Languages)

Every profiling task follows this loop:

```
1. Identify hotspot → Profile under realistic workload
2. Understand why → Read the flamegraph / profile, trace the call stack
3. Propose fix → Change one thing at a time
4. Benchmark before/after → Verify improvement is real (not noise)
5. Verify no regression → Run full test suite
```

Never optimize without profiling first. Never claim improvement without benchmarking.

## Decision Tree

```
Performance problem → What language?
│
├─ Rust
│  ├─ CPU-bound (slow computation)
│  │  ├─ Quick look → cargo flamegraph
│  │  └─ Detailed analysis → samply
│  │
│  ├─ Memory-heavy (high RSS, OOM)
│  │  ├─ Allocation patterns → DHAT
│  │  └─ Heap over time → heaptrack
│  │
│  └─ Not sure what's slow
│     └─ Start with cargo flamegraph, then look at allocations
│
└─ Go
   ├─ CPU-bound
   │  └─ pprof CPU profile
   │
   ├─ Memory-heavy / GC pressure
   │  └─ pprof heap profile + GOGC tuning
   │
   ├─ Goroutine issues (deadlocks, leaks)
   │  └─ pprof goroutine profile
   │
   ├─ Contention (lock/channel bottlenecks)
   │  └─ pprof mutex + block profiles
   │
   └─ Concurrency bugs (ordering, races)
      └─ go tool trace
```

---

## Rust Profiling

### CPU Profiling with cargo flamegraph

```bash
# Install
cargo install flamegraph

# Profile your binary (release mode — always profile optimized builds)
cargo flamegraph --root -- <args>

# Profile a specific binary in a workspace
cargo flamegraph --root --bin my-binary -- <args>

# Profile benchmarks
cargo flamegraph --root --bench my_benchmark
```

**Reading the flamegraph:**

- Width = time spent (wider = more time)
- Y-axis = call stack depth (bottom = entry point, top = leaf functions)
- Look for **wide plateaus** at the top — these are the hot functions
- Narrow deep stacks are fine — they're just call chain overhead

### CPU Profiling with samply

More detailed than flamegraph, gives an interactive Firefox Profiler view:

```bash
# Install
cargo install samply

# Profile (release mode)
cargo build --release
samply record ./target/release/my-binary <args>

# Opens Firefox Profiler in browser — interactive flamegraph, timeline, markers
```

### Memory Profiling with DHAT

DHAT shows allocation patterns: where memory is allocated, how much, how long it lives.

```rust
// Cargo.toml
// [dependencies]
// dhat = "0.3"
//
// [profile.release]
// debug = true  # Need debug info for useful stack traces

// main.rs — add at the very top
#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();

    // ... your code ...
}
```

```bash
# Run with DHAT enabled
cargo run --release --features dhat-heap

# Opens dhat-viewer in browser showing:
# - Total bytes allocated
# - Allocation sites ranked by total bytes
# - Allocation lifetime analysis (short-lived = GC pressure equivalent)
```

### Memory Profiling with heaptrack

For tracking heap usage over time (Linux):

```bash
# Install (Linux)
sudo apt install heaptrack heaptrack-gui

# Profile
heaptrack ./target/release/my-binary <args>

# Analyze
heaptrack_gui heaptrack.my-binary.*.zst
```

### Common Rust Hotspots & Fixes

| Hotspot Pattern            | What You'll See                                       | Fix                                                                                              |
| -------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Unnecessary `.clone()`     | `clone` in flamegraph, high allocation count in DHAT  | Borrow instead: `&str` instead of `String`, `&[T]` instead of `Vec<T>`                           |
| `String` vs `&str`         | `alloc::string::String::from` taking significant time | Accept `&str` in function signatures, use `Cow<str>` when sometimes owned                        |
| Excessive `Vec` allocation | Many small `Vec::new()` / `Vec::push`                 | Pre-allocate with `Vec::with_capacity()`, use `SmallVec` for small collections                   |
| Lock contention            | `Mutex::lock` or `RwLock` wide in flamegraph          | Reduce critical section scope, use `parking_lot` mutex, consider lock-free structures            |
| `Arc<Mutex<>>` everywhere  | Widespread locking, thread contention                 | Restructure to avoid shared state, use channels, or `dashmap` for concurrent maps                |
| Serialization (serde)      | `serde_json::to_string` / `from_str` hot              | Use `simd-json`, or `serde_json::to_writer` (avoid intermediate String), consider binary formats |
| Hash map overhead          | `HashMap::insert` / `get` hot                         | Use `FxHashMap` (faster hash), or `IndexMap` if iteration order matters                          |
| Regex compilation          | `Regex::new` called repeatedly                        | Compile once with `lazy_static!` or `std::sync::OnceLock`                                        |

### Rust Optimization Patterns

```rust
// BEFORE: Allocates on every call
fn process(items: Vec<String>) -> Vec<String> {
    items.iter().map(|s| s.to_uppercase()).collect()
}

// AFTER: Borrows input, pre-allocates output
fn process(items: &[String]) -> Vec<String> {
    let mut result = Vec::with_capacity(items.len());
    for s in items {
        result.push(s.to_uppercase());
    }
    result
}

// BEFORE: Clone because borrow checker complains
let data = expensive_data.clone();
process(data);

// AFTER: Restructure to avoid the clone
process(&expensive_data);

// Parallelism with rayon (when CPU-bound)
use rayon::prelude::*;
let results: Vec<_> = items.par_iter().map(|item| process(item)).collect();
```

---

## Go Profiling

### pprof Setup

```go
import (
    "net/http"
    _ "net/http/pprof"  // Import for side effects — registers /debug/pprof/
)

func main() {
    // For servers: pprof is already available at /debug/pprof/
    // For CLI tools: start a background HTTP server
    go func() {
        http.ListenAndServe("localhost:6060", nil)
    }()

    // ... your code ...
}
```

### CPU Profiling

```bash
# Capture 30-second CPU profile from running server
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# For CLI tools: programmatic profiling
```

```go
import "runtime/pprof"

f, _ := os.Create("cpu.prof")
pprof.StartCPUProfile(f)
defer pprof.StopCPUProfile()
// ... code to profile ...
```

```bash
# Analyze
go tool pprof cpu.prof

# Interactive commands:
# top        — show top functions by CPU time
# top -cum   — show top functions by cumulative time (including callees)
# list func  — show source code annotated with time
# web        — open flamegraph in browser (requires graphviz)

# Web UI (recommended)
go tool pprof -http=:8080 cpu.prof
```

**Reading pprof output:**

- **Flat time**: time spent in the function itself (excluding callees)
- **Cumulative time**: time spent in the function + all functions it calls
- High flat time = the function itself is slow → optimize its code
- High cumulative but low flat = it calls something slow → look at callees

### Memory Profiling

```bash
# Heap profile from running server
go tool pprof http://localhost:6060/debug/pprof/heap

# Allocs profile (all allocations, not just live objects)
go tool pprof http://localhost:6060/debug/pprof/allocs
```

```bash
# Interactive commands:
# top        — show top allocation sites
# top -cum   — cumulative allocations
# list func  — source-annotated allocation counts

# Key metrics:
# -inuse_space  — currently live bytes (default, shows memory usage)
# -inuse_objects — currently live objects
# -alloc_space  — total bytes allocated (shows allocation pressure)
# -alloc_objects — total objects allocated
go tool pprof -alloc_space http://localhost:6060/debug/pprof/heap
```

### Goroutine Profiling

```bash
# See all goroutines and what they're doing
go tool pprof http://localhost:6060/debug/pprof/goroutine

# Goroutine count growing over time = goroutine leak
curl http://localhost:6060/debug/pprof/goroutine?debug=1 | head -5
# "goroutine profile: total 1234" — if this grows, you have a leak
```

### Mutex & Block Profiling

```go
// Enable in code (not enabled by default)
runtime.SetMutexProfileFraction(1)  // Mutex contention
runtime.SetBlockProfileRate(1)       // Channel/select blocking
```

```bash
go tool pprof http://localhost:6060/debug/pprof/mutex
go tool pprof http://localhost:6060/debug/pprof/block
```

### Execution Tracing

For concurrency analysis — see goroutine scheduling, GC pauses, syscalls:

```bash
# Capture 5-second trace
curl -o trace.out http://localhost:6060/debug/pprof/trace?seconds=5

# Analyze
go tool trace trace.out
# Opens browser with timeline view
```

### Go Benchmarks with Statistical Comparison

```bash
# Run benchmarks with enough iterations for statistics
go test -bench=. -benchmem -count=10 ./... > old.txt

# Make changes

go test -bench=. -benchmem -count=10 ./... > new.txt

# Compare with benchstat
benchstat old.txt new.txt
```

benchstat output shows whether the difference is statistically significant (p-value < 0.05).

### Common Go Hotspots & Fixes

| Hotspot Pattern                    | What You'll See in pprof                      | Fix                                                                                   |
| ---------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------- |
| GC pressure from small allocations | `runtime.mallocgc` high in CPU profile        | Pre-allocate slices, use `sync.Pool`, reduce pointer-heavy structures                 |
| String concatenation in loops      | `runtime.growslice` or `runtime.stringconcat` | Use `strings.Builder`                                                                 |
| Goroutine leaks                    | Goroutine count grows, never decreases        | Ensure goroutines have exit conditions, use `context.Context` for cancellation        |
| Channel contention                 | Block profile shows channel operations        | Buffer channels, restructure to avoid contention, use `sync.Mutex` for simple cases   |
| Interface boxing                   | `runtime.convT` or `runtime.convTslice`       | Avoid interface{}/any in hot paths, use generics                                      |
| Excessive reflection               | `reflect.Value` methods in profile            | Use code generation or generics instead                                               |
| Map access contention              | `runtime.mapaccess` with mutex                | Use `sync.Map` for read-heavy workloads, or shard the map                             |
| JSON marshal/unmarshal             | `encoding/json` hot                           | Use `github.com/bytedance/sonic` or `github.com/goccy/go-json`, or switch to protobuf |

### Go Optimization Patterns

```go
// BEFORE: Allocates on every append
var result []string
for _, item := range items {
    result = append(result, process(item))
}

// AFTER: Pre-allocate
result := make([]string, 0, len(items))
for _, item := range items {
    result = append(result, process(item))
}

// BEFORE: String concatenation in loop
var s string
for _, part := range parts {
    s += part  // O(n²) — copies entire string each time
}

// AFTER: strings.Builder
var b strings.Builder
for _, part := range parts {
    b.WriteString(part)
}
s := b.String()

// BEFORE: Goroutine leak — no exit condition
go func() {
    for msg := range ch {
        process(msg)
    }
}()

// AFTER: Cancellable goroutine
go func() {
    for {
        select {
        case msg, ok := <-ch:
            if !ok { return }
            process(msg)
        case <-ctx.Done():
            return
        }
    }
}()

// Pool reusable objects to reduce GC pressure
var bufPool = sync.Pool{
    New: func() interface{} { return new(bytes.Buffer) },
}
buf := bufPool.Get().(*bytes.Buffer)
buf.Reset()
defer bufPool.Put(buf)
```

---

## Shared: Before/After Verification

After any optimization, always verify:

```bash
# 1. Tests still pass
cargo test           # Rust
go test ./...        # Go

# 2. Benchmark shows improvement
cargo bench          # Rust — criterion auto-compares if baseline saved
benchstat old.txt new.txt  # Go

# 3. Profile confirms the hotspot is gone
cargo flamegraph     # Rust — the wide plateau should be narrower/gone
go tool pprof ...    # Go — the function should have less flat time
```

**Warning signs that "improvement" is noise:**

- Improvement < 5% on a measurement with CV > 5%
- benchstat shows p-value > 0.05
- Improvement disappears on a different machine or after reboot

## Verification Checklist

Before reporting profiling results:

- [ ] Profiled in release/optimized mode (not debug builds)
- [ ] Used a realistic workload (not a trivial test case)
- [ ] Identified specific hot functions with file:line references
- [ ] Proposed fix changes one thing at a time (not a shotgun optimization)
- [ ] Benchmarked before AND after with statistical rigor
- [ ] Tests pass after the change
- [ ] Flamegraph/profile confirms the hotspot is actually reduced
