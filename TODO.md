# Moon-code TODO List

## Completed
- [x] Create src/core/logger.zig - logging module (3 tests)
- [x] Create src/core/errors.zig - error handling module (3 tests)
- [x] Add test infrastructure to build.zig
- [x] Add unit tests to buffer.zig (14 tests)
- [x] Add unit tests to lazy_loader.zig (9 tests)
- [x] Create src/ui/state.zig - UIState & SearchState structs (9 tests)
- [x] Create src/editor/tab_manager.zig - TabManager (12 tests)
- [x] Create src/editor/cache.zig - BufferCache with CursorCache, LineIndex, DirtyTracking, TokenCache (8 tests)

## Pending
- [ ] Replace 50+ catch {} with proper error handling (see files below)
- [ ] Add auto-save functionality (use TabManager.shouldAutoSave)
- [ ] Add LSP retry logic (src/lsp/client.zig)

## Files with catch {} to fix
| File | Count | Priority |
|------|-------|----------|
| src/main.zig | ~36 | High |
| src/plugins/loader.zig | ~8 | Medium |
| src/editor/buffer.zig | ~5 | Medium |
| src/lsp/client.zig | ~4 | Medium |
| src/terminal/shell.zig | ~3 | Low |

## Future Improvements
- [ ] Create src/file/manager.zig - FileManager (line 419-476 in main.zig)
- [ ] Create src/search/state.zig - integrate with ui/state.zig SearchState
- [ ] Refactor main() function (3010 lines → ~200 lines)
- [ ] Add plugin timeout mechanism (5 sec)
- [ ] Extend WasmError types in wasm_runtime.zig

## Test Summary
| Module | Tests | Status |
|--------|-------|--------|
| core/logger.zig | 3 | ✅ Passing |
| core/errors.zig | 3 | ✅ Passing |
| editor/buffer.zig | 14 | ✅ Passing |
| editor/lazy_loader.zig | 9 | ✅ Passing |
| ui/state.zig | 9 | ✅ Passing |
| editor/tab_manager.zig | 12 | ✅ Passing |
| editor/cache.zig | 8 | ✅ Passing |
| **Total** | **58** | ✅ All Passing |

## New Files Created
```
src/
├── core/
│   ├── logger.zig      ✅ Logging with file output and levels
│   └── errors.zig      ✅ Error handling with retry support
├── editor/
│   ├── tab_manager.zig ✅ Tab management with auto-save tracking
│   └── cache.zig       ✅ Buffer caching and dirty tracking
└── ui/
    └── state.zig       ✅ UI state and search state
```

## Run Tests
```bash
zig build test
```
