---
name: benchmark-infra
description: Use when the user needs to set up benchmarking infrastructure, compare performance before/after changes, or establish reliable measurement methodology. Triggers on requests to benchmark, compare performance, measure latency/throughput, or set up CI performance gates.
---

# Benchmarking Infrastructure & Reliable Comparison

## Core Principle

A benchmark that doesn't control for noise is not a benchmark — it's a random number generator. Every measurement must account for warm-up, statistical variance, and environment isolation.

## Decision Tree

```
Task → What needs benchmarking?
│
├─ CLI tool / command-line program
│  └─ Use hyperfine (any language)
│
├─ Library function / micro-benchmark
│  ├─ Rust → criterion or divan
│  ├─ Go → testing.B + benchstat
│  ├─ JavaScript/TypeScript → vitest bench or mitata
│  ├─ Python → pytest-benchmark or pyperf
│  └─ Other → language-specific framework, or wrap in CLI + hyperfine
│
├─ HTTP API / web server
│  └─ wrk, oha, or k6 (load testing)
│
├─ Database query
│  └─ EXPLAIN ANALYZE + pg_stat_statements (Postgres)
│     or equivalent for your database
│
└─ Full application / integration
   └─ Custom harness with hyperfine or k6
```

## Measurement Methodology

### Mandatory Controls

Every benchmark run must include:

1. **Warm-up runs** — Discard the first N iterations to eliminate cold-start effects (JIT compilation, cache warming, lazy initialization)
2. **Multiple samples** — Minimum 10 runs, ideally 30+ for statistical significance
3. **Statistical summary** — Report min, max, median, mean, stddev, and p95/p99 where relevant
4. **Environment documentation** — Record: OS, CPU model, RAM, thermal state, background load

### What to Report

```
| Metric     | Value   |
|------------|---------|
| Median     | 42.3ms  |
| Mean       | 44.1ms  |
| Stddev     | 3.2ms   |
| Min        | 38.1ms  |
| Max        | 62.4ms  |
| p95        | 51.2ms  |
| p99        | 58.7ms  |
| Runs       | 100     |
| Warm-up    | 5       |
| CV         | 7.3%    |
```

**Coefficient of Variation (CV)** = stddev / mean. If CV > 10%, the measurement is noisy — investigate and reduce variance before drawing conclusions.

## Tool-Specific Setup

### hyperfine (CLI benchmarks, any language)

The best general-purpose CLI benchmarking tool. Use it for anything that can be run as a command.

```bash
# Install
brew install hyperfine  # macOS
cargo install hyperfine  # or via Rust

# Basic benchmark
hyperfine 'your-command'

# With warm-up and minimum runs
hyperfine --warmup 3 --min-runs 20 'your-command'

# A/B comparison (the most useful pattern)
hyperfine --warmup 3 \
  'git stash && ./build-baseline && git stash pop' \
  './build-current' \
  --prepare 'make clean'

# Export results as JSON for CI comparison
hyperfine --warmup 3 --export-json bench-results.json 'your-command'

# Parameterized benchmark
hyperfine --parameter-scan threads 1 8 './program --threads {threads}'
```

### criterion (Rust micro-benchmarks)

```rust
// Cargo.toml
// [dev-dependencies]
// criterion = { version = "0.5", features = ["html_reports"] }
//
// [[bench]]
// name = "my_benchmark"
// harness = false

use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_function(c: &mut Criterion) {
    c.bench_function("my_function", |b| {
        b.iter(|| {
            my_function(black_box(input))  // black_box prevents dead code elimination
        })
    });
}

// Comparison group
fn bench_comparison(c: &mut Criterion) {
    let mut group = c.benchmark_group("implementations");
    group.bench_function("v1", |b| b.iter(|| v1_impl(black_box(input))));
    group.bench_function("v2", |b| b.iter(|| v2_impl(black_box(input))));
    group.finish();
}

criterion_group!(benches, bench_function, bench_comparison);
criterion_main!(benches);
```

```bash
# Run benchmarks
cargo bench

# Compare against baseline
cargo bench -- --save-baseline before
# ... make changes ...
cargo bench -- --baseline before
```

### divan (Rust, simpler alternative to criterion)

```rust
// Cargo.toml
// [dev-dependencies]
// divan = "0.1"
//
// [[bench]]
// name = "my_benchmark"
// harness = false

fn main() {
    divan::main();
}

#[divan::bench]
fn bench_function() -> Vec<u8> {
    my_function(divan::black_box(input))
}

#[divan::bench(args = [10, 100, 1000])]
fn bench_with_sizes(n: usize) -> Vec<u8> {
    my_function_sized(divan::black_box(n))
}
```

### Go benchmarks (testing.B + benchstat)

```go
// my_test.go
func BenchmarkMyFunction(b *testing.B) {
    input := setupTestData()
    b.ResetTimer()  // Exclude setup from measurement
    for i := 0; i < b.N; i++ {
        MyFunction(input)
    }
}

// With memory allocation tracking
func BenchmarkMyFunction(b *testing.B) {
    b.ReportAllocs()
    for i := 0; i < b.N; i++ {
        MyFunction(input)
    }
}

// Sub-benchmarks for comparison
func BenchmarkImplementations(b *testing.B) {
    b.Run("v1", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            V1Impl(input)
        }
    })
    b.Run("v2", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            V2Impl(input)
        }
    })
}
```

```bash
# Run benchmarks with count for statistical significance
go test -bench=. -benchmem -count=10 ./... > bench-new.txt

# Compare with benchstat
go install golang.org/x/perf/cmd/benchstat@latest
benchstat bench-old.txt bench-new.txt
```

### JavaScript/TypeScript benchmarks

```typescript
// With vitest
import { bench, describe } from "vitest";

describe("string processing", () => {
  bench("regex approach", () => {
    processWithRegex(input);
  });

  bench("manual parsing", () => {
    processManually(input);
  });
});
```

```bash
vitest bench
```

```typescript
// With mitata (standalone, no test framework)
import { run, bench, group, baseline } from "mitata";

group("string processing", () => {
  baseline("regex", () => processWithRegex(input));
  bench("manual", () => processManually(input));
});

await run();
```

## A/B Comparison Workflow

The most common and useful pattern: measuring before vs. after a change.

### Step 1: Baseline

```bash
# Save current work
git stash  # or commit to a feature branch

# Checkout baseline
git checkout main

# Run benchmark, save results
hyperfine --warmup 3 --export-json baseline.json './your-command'
# or: cargo bench -- --save-baseline before
# or: go test -bench=. -count=10 > baseline.txt

# Return to feature branch
git checkout feature-branch
git stash pop  # if needed
```

### Step 2: Measure Change

```bash
# Run same benchmark on changed code
hyperfine --warmup 3 --export-json feature.json './your-command'
# or: cargo bench -- --baseline before
# or: go test -bench=. -count=10 > feature.txt
```

### Step 3: Compare

```bash
# hyperfine: compare side by side
hyperfine --warmup 3 'git stash && ./baseline-cmd && git stash pop' './feature-cmd'

# Go: use benchstat
benchstat baseline.txt feature.txt

# Rust criterion: automatic HTML report in target/criterion/
```

### Step 4: Validate

Before claiming "X is Y% faster":

- Is the CV < 10% for both measurements? If not, the difference might be noise.
- Did you run enough samples? (10 minimum, 30+ preferred)
- Is the improvement consistent across multiple runs?
- Did you control for background processes, thermal throttling, CPU frequency scaling?

## Environment Normalization

For reliable results, especially on laptops:

```bash
# Linux: Set CPU governor to performance
sudo cpupower frequency-set -g performance

# macOS: Close all other apps, disable Spotlight indexing temporarily
sudo mdutil -a -i off

# Both: Check system load before benchmarking
uptime  # Load average should be < 0.5
```

**Thermal throttling**: Laptops throttle under sustained load. If your benchmark runs > 30 seconds, results will include thermal effects. Either:
- Use a desktop/server for benchmarks
- Add cooling-off periods between runs
- Monitor CPU frequency during the run

## CI Integration

### GitHub Actions: Benchmark on PRs

```yaml
name: Benchmark
on:
  pull_request:
    branches: [main]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Benchmark baseline
        run: |
          git checkout ${{ github.event.pull_request.base.sha }}
          # Run your benchmark, save results
          hyperfine --warmup 3 --export-json baseline.json './your-command'

      - name: Benchmark PR
        run: |
          git checkout ${{ github.sha }}
          hyperfine --warmup 3 --export-json pr.json './your-command'

      - name: Compare
        run: |
          # Parse JSON and compare
          python3 -c "
          import json
          baseline = json.load(open('baseline.json'))['results'][0]
          pr = json.load(open('pr.json'))['results'][0]
          base_median = baseline['median']
          pr_median = pr['median']
          change = ((pr_median - base_median) / base_median) * 100
          print(f'Baseline: {base_median*1000:.1f}ms')
          print(f'PR:       {pr_median*1000:.1f}ms')
          print(f'Change:   {change:+.1f}%')
          if change > 10:
              print('WARNING: >10% regression detected')
              exit(1)
          "
```

### Storing Benchmark History

Save benchmark results as JSON artifacts, keyed by commit SHA:

```bash
# After each benchmark run
mkdir -p bench-history
cp bench-results.json "bench-history/$(git rev-parse HEAD).json"
```

## Micro vs. Macro Benchmarks

| Type | Measures | When to Use | Watch Out For |
| --- | --- | --- | --- |
| **Micro** | Single function, tight loop | Comparing algorithms, data structures | Dead code elimination, unrealistic inputs |
| **Macro** | End-to-end workflow | Real-world performance, system bottlenecks | Too many variables, hard to isolate changes |

**Rule**: Start with macro benchmarks to identify bottlenecks, then use micro benchmarks to validate specific optimizations.

## Verification Checklist

Before reporting benchmark results:

- [ ] Warm-up runs included (minimum 3)
- [ ] Sufficient samples (minimum 10 runs)
- [ ] CV < 10% (measurement is not just noise)
- [ ] Environment documented (OS, CPU, load)
- [ ] Background processes controlled
- [ ] `black_box` or equivalent used to prevent dead code elimination
- [ ] Before/after comparison uses the same machine, same conditions
- [ ] Results include median, not just mean (median is more robust to outliers)
