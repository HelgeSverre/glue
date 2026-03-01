---
name: sema-scripting
description: Write and execute Sema code (a Scheme-like Lisp with built-in LLM primitives). Use when tasks involve LLM orchestration, data extraction, multi-step pipelines, or building agent workflows. Requires `sema` CLI to be installed.
allowed-tools: Bash Read
---

# Sema Scripting

Sema is a Scheme-like Lisp with first-class LLM primitives. Run sema code with the `bash` tool:

```bash
# One-liner
sema -e '(+ 1 2)'

# Multi-line: write to a file, then run it
sema script.sema
```

For multi-line scripts, write a `.sema` file first, then execute it with `sema <file>`.

## LLM Providers

Sema auto-detects providers from environment variables. No imports needed — LLM functions are built-in.

| Env var | Provider |
|---------|----------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `GOOGLE_API_KEY` | Google Gemini |
| `OLLAMA_HOST` | Ollama (local) |

Override the default model: `{:model "claude-haiku-4-5-20251001"}`

## Core LLM Functions

### Completion

```scheme
; Simple prompt
(llm/complete "Say hello in 5 words" {:max-tokens 50})

; With system prompt and model override
(llm/complete "Explain monads"
  {:model "claude-haiku-4-5-20251001"
   :max-tokens 200
   :temperature 0.3
   :system "You are a Haskell expert."})
```

### Chat (multi-message)

```scheme
(llm/chat
  (list (message :system "You are a helpful assistant.")
        (message :user "What is Lisp? One sentence."))
  {:max-tokens 100})
```

### Streaming

```scheme
(llm/stream "Tell me a story" {:max-tokens 200})

; With callback
(llm/stream "Tell me a story"
  (fn (chunk) (display chunk))
  {:max-tokens 200})
```

### Structured prompt composition

```scheme
(define review-prompt
  (prompt
    (system "You are a code reviewer. Be concise.")
    (user "Review this function.")))

(llm/send review-prompt {:max-tokens 200})
```

## Structured Extraction

```scheme
; Extract structured data from text
(llm/extract
  {:vendor {:type :string}
   :amount {:type :number}
   :date   {:type :string}}
  "I bought coffee for $4.50 at Blue Bottle on Jan 15, 2025")
; => {:amount 4.5 :date "2025-01-15" :vendor "Blue Bottle"}

; With validation and retries
(llm/extract
  {:name {:type :string} :age {:type :number}}
  some-text
  {:validate true :retries 2})
```

## Classification

```scheme
(llm/classify '(:positive :negative :neutral)
              "This product is amazing!")
; => :positive
```

## Tools and Agents

### Define a tool

```scheme
(deftool lookup-capital
  "Look up the capital of a country"
  {:country {:type :string :description "Country name"}}
  (lambda (country)
    (cond
      ((= country "Norway") "Oslo")
      ((= country "France") "Paris")
      (else "Unknown"))))
```

### Define an agent with tools

```scheme
(deftool get-weather
  "Get weather for a city"
  {:city {:type :string}}
  (lambda (city)
    (format "~a: 22C, sunny" city)))

(defagent weather-bot
  {:system "You are a weather assistant. Use get-weather."
   :tools [get-weather]
   :model "claude-haiku-4-5-20251001"
   :max-turns 3})

(agent/run weather-bot "What's the weather in Oslo?")
```

## Conversations (multi-turn)

```scheme
(define conv (conversation/new {:model "claude-haiku-4-5-20251001"}))
(define conv (conversation/say conv "Remember: the secret number is 7"))
(define conv (conversation/say conv "What is the secret number?"))
(println (conversation/last-reply conv))
```

## Embeddings and Vector Search

```scheme
(define store (vector-store/create "my-store"))
(vector-store/add store "id1" "Sema is a Lisp" (llm/embed "Sema is a Lisp"))
(vector-store/add store "id2" "Rust is fast" (llm/embed "Rust is fast"))
(vector-store/search store (llm/embed "What is Sema?") 1)
```

## Common Stdlib

```scheme
; File I/O
(file/read "config.json")
(file/write "out.txt" "hello")
(file/exists? "path")

; JSON
(json/decode "{\"a\":1}")
(json/encode {:a 1})

; HTTP
(http/get "https://api.example.com/data")
(http/post "https://api.example.com" {:body (json/encode data)})

; String operations
(string/split "a,b,c" ",")
(string/join ["a" "b"] "-")
(string/replace "hello world" "world" "sema")
(format "Hello ~a, you have ~a items" name count)

; Shell
(shell "ls -la")
(shell "git status")

; Regex
(regex/match "\\d+" "abc123def")
(regex/find-all "\\w+" "hello world")

; Math
(+ 1 2) (- 5 3) (* 2 4) (/ 10 3)
(sqrt 16) (abs -5)

; Lists and maps
(map (fn (x) (* x 2)) [1 2 3])
(filter (fn (x) (> x 2)) [1 2 3 4])
(reduce + [1 2 3 4])
(get {:a 1 :b 2} :a)
(assoc {:a 1} :b 2)
```

## Options Map Reference

All LLM functions accept these keys in their options map:

| Key | Type | Description |
|-----|------|-------------|
| `:model` | string | Model identifier |
| `:max-tokens` | integer | Maximum response tokens |
| `:temperature` | float | Sampling temperature (0.0-1.0) |
| `:system` | string | System prompt (for `llm/complete`) |
| `:tools` | list | Tool definitions |

## Tips

- Use keywords (`:foo`) for map keys and enum-like values
- Vectors `[1 2 3]` are like arrays, lists `'(1 2 3)` are linked lists
- `define` creates bindings, `lambda` or `fn` creates functions
- Use `println` for debug output, `display` for raw output
- `let` for local bindings: `(let ((x 1) (y 2)) (+ x y))`
- Pipe data: `(-> data (map transform) (filter pred) (reduce combine))`
