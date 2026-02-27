# Magic Values Refactoring Summary

**Status**: ✅ Complete — All tests pass, zero analyzer warnings

## What Was Done

Extracted **15+ hardcoded magic values** from the codebase into centralized, named constants across two new files:

### 1. **AppConstants** (`lib/src/config/constants.dart`)
Application-wide configuration and limits:
- `maxConversationBlocks = 200` — Max conversation history blocks
- `ctrlCDoubleTapWindow = Duration(seconds: 2)` — Double-tap Ctrl+C window
- `bashTimeoutSeconds = 30` — Default bash command timeout
- `grepTimeoutSeconds = 15` — Grep tool timeout
- `defaultOllamaBaseUrl = 'http://localhost:11434'` — Local Ollama server
- `maxVisibleDropdownItems = 8` — UI dropdown height
- `atFileHintCacheTtlSeconds = 2` — File hint cache expiry
- `atFileHintMaxTreeEntries = 2000` — Max files in tree view
- `atFileHintMaxTreeDepth = 3` — Max folder recursion depth
- `globMaxEntries = 1000` — Max directory listing results
- `maxFileExpansionBytes = 100 * 1024` — Max file size for inline expansion
- `debugLogBodySizeLimit = 1000` — Max HTTP body logged
- `inputAreaDivisor = 3` — Input zone height ratio (rows / 3)

### 2. **Physics Constants** (`lib/src/rendering/mascot_physics.dart`)
Tunable animation parameters:

**LiquidSimPhysics**:
- `damping = 0.92` — Wave dampening
- `activeThreshold = 0.01` — Minimum displacement to keep simulating
- `explodeThreshold = 60.0` — Disturbance needed to trigger explosion

**MascotParticles**:
- `samplingRate = 0.4` — Fraction of pixels rendered
- `dripSpawnChance = 0.3` — Probability of drip from landed particle
- `dripStopChance = 0.15` — Probability of drip stopping per frame
- `maxDripLength = 6` — Max cells in drip trail
- `gravity = 0.15`, `drag = 0.96` — Physics parameters
- `baseSpeed = 1.5`, `speedVariance = 2.5` — Initial particle velocity
- `impulseStrength = 6.0`, `impulseRadius = 3` — Ripple parameters
- `settleFrames = 10` — Frames before explosion is considered "done"

**GooChar Enum**:
- Replaced `[46, 44, 59, 111]` char code list with semantic enum:
  ```dart
  enum GooChar {
    dot(46, '.'),
    comma(44, ','),
    semicolon(59, ';'),
    orb(111, 'o');
  }
  ```

## Files Modified

| File | Changes |
|------|---------|
| `lib/src/config/constants.dart` | **NEW** — Central constants class |
| `lib/src/rendering/mascot_physics.dart` | **NEW** — Physics constants & GooChar enum |
| `lib/src/rendering/mascot.dart` | 12 magic values → constants |
| `lib/src/config/glue_config.dart` | 3 default values → constants |
| `lib/src/agent/tools.dart` | 3 timeout/limit values → constants |
| `lib/src/storage/debug_logger.dart` | 1 size limit → constant |
| `lib/src/input/file_expander.dart` | 1 file size limit → constant |
| `lib/src/app.dart` | 2 UI/behavior limits → constants |
| `lib/src/terminal/layout.dart` | 1 layout ratio → constant |
| `lib/src/ui/at_file_hint.dart` | 5 hint limits → constants |
| `lib/src/ui/slash_autocomplete.dart` | 1 UI limit → constant |

## Benefits

✅ **Maintainability**: All magic values in one place — easy to find and adjust  
✅ **Testability**: Physics constants now tunable for animation tweaking  
✅ **Documentation**: Named constants self-document purpose (e.g., `samplingRate` vs bare `0.4`)  
✅ **Type Safety**: `GooChar` enum prevents char code typos  
✅ **Consistency**: Eliminates duplicate defaults (4 copies of Ollama URL → 1)  
✅ **Discoverability**: IDE autocomplete reveals all available constants  

## Verification

```bash
$ dart analyze
No issues found!

$ dart test
All tests passed! (394 tests)
```
