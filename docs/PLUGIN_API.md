# Moon-code Plugin API v2.0

## Overview

Moon-code supports WebAssembly (WASM) plugins for syntax highlighting, LSP integration, and running code.

**Currently implemented:**
- Syntax Highlighting (tokenization)
- Run Commands (execute file)
- Custom icons (SVG)
- **LSP Integration** (autocomplete, diagnostics, go-to-definition)

---

## Quick Start

### Minimal Plugin (Zig)

```zig
const std = @import("std");

// Plugin metadata
const plugin_name: []const u8 = "MyLanguage";
const plugin_version: []const u8 = "1.0.0";
const plugin_extensions: []const u8 = ".mylang,.ml";

// Required exports
export fn get_name() [*]const u8 { return plugin_name.ptr; }
export fn get_version() [*]const u8 { return plugin_version.ptr; }
export fn get_extensions() [*]const u8 { return plugin_extensions.ptr; }

// Token structure
const Token = extern struct {
    start: u32,
    len: u16,
    kind: u8,
    _pad: u8 = 0,
};

// Syntax highlighting
export fn tokenize(src_ptr: [*]const u8, src_len: u32, out_ptr: [*]Token, max_tokens: u32) u32 {
    // Your tokenization logic
    return 0; // token count
}
```

### Building

```bash
zig build-lib \
    -target wasm32-freestanding \
    -O ReleaseSmall \
    -fno-entry \
    --export=get_name --export=get_version --export=get_extensions \
    --export=tokenize \
    -femit-bin=myplugin.wasm \
    myplugin.zig
```

### Installation

Copy `.wasm` file to `~/.mncode/plugins/`

---

## Plugin Exports

### Required

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_name` | `() -> [*]const u8` | Plugin name pointer |
| `get_version` | `() -> [*]const u8` | Version string pointer |
| `get_extensions` | `() -> [*]const u8` | File extensions (comma-separated: `.py,.pyw`) |

### Optional Metadata

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_author` | `() -> [*]const u8` | Author name |
| `get_description` | `() -> [*]const u8` | Plugin description |
| `get_icon` | `() -> [*]const u8` | SVG icon data |
| `get_icon_len` | `() -> u32` | SVG icon length |

### Syntax Highlighting

| Function | Signature | Description |
|----------|-----------|-------------|
| `tokenize` | `(src_ptr, src_len, out_ptr, max_tokens) -> u32` | Tokenize source, returns token count |

### Run Command

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_run_command` | `() -> [*]const u8` | Command(s) to run file |
| `get_run_command_len` | `() -> u32` | Command length |

### LSP Integration

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_lsp_command` | `() -> [*]const u8` | LSP server command (e.g., `pyright-langserver`) |
| `get_lsp_command_len` | `() -> u32` | Command length |
| `get_lsp_args` | `() -> [*]const u8` | LSP server arguments (e.g., `--stdio`) |
| `get_lsp_args_len` | `() -> u32` | Arguments length |
| `get_language_id` | `() -> [*]const u8` | LSP language identifier (e.g., `python`) |
| `get_language_id_len` | `() -> u32` | Language ID length |

---

## Token Structure

```zig
const Token = extern struct {
    start: u32,  // Byte offset in source
    len: u16,    // Token length in bytes
    kind: u8,    // Token type (see below)
    _pad: u8,    // Padding (set to 0)
};
```

### Token Types

| Value | Name | Color | Description |
|-------|------|-------|-------------|
| 0 | `normal` | #e8e8e8 | Default text |
| 1 | `keyword` | #c586c0 | Language keywords |
| 2 | `type_name` | #4ec9b0 | Type names |
| 3 | `builtin` | #dcdcaa | Built-in functions |
| 4 | `string` | #ce9178 | String literals |
| 5 | `number` | #b5cea8 | Numeric literals |
| 6 | `comment` | #6a9955 | Comments |
| 7 | `function` | #dcdcaa | Function names |
| 8 | `operator` | #d4d4d4 | Operators |
| 9 | `punctuation` | #d4d4d4 | Brackets, commas |
| 10 | `field` | #9cdcfe | Object fields |

---

## SVG Icon

Plugins can provide custom icons displayed in the sidebar.

```zig
const plugin_icon: []const u8 =
    \\<svg viewBox="0 0 24 24">
    \\<path fill="#3572A5" d="M12 2..."/>
    \\</svg>
;

export fn get_icon() [*]const u8 { return plugin_icon.ptr; }
export fn get_icon_len() u32 { return @intCast(plugin_icon.len); }
```

**Requirements:**
- Must have `viewBox` attribute
- Single color fills work best
- Keep SVG simple (renders at 16-24px)

---

## Run Command

Specify command(s) to run files of this type. Multiple commands separated by comma are tried in order.

```zig
// Try python3 first, fallback to python
const run_commands: []const u8 = "python3,python";

export fn get_run_command() [*]const u8 { return run_commands.ptr; }
export fn get_run_command_len() u32 { return @intCast(run_commands.len); }
```

The editor appends the file path when running: `python3 /path/to/file.py`

---

## LSP Support

Plugins can provide LSP (Language Server Protocol) support by specifying the LSP server command.

```zig
// LSP server command
const lsp_command: []const u8 = "pyright-langserver";
const lsp_args: []const u8 = "--stdio";
const language_id: []const u8 = "python";

export fn get_lsp_command() [*]const u8 { return lsp_command.ptr; }
export fn get_lsp_command_len() u32 { return @intCast(lsp_command.len); }
export fn get_lsp_args() [*]const u8 { return lsp_args.ptr; }
export fn get_lsp_args_len() u32 { return @intCast(lsp_args.len); }
export fn get_language_id() [*]const u8 { return language_id.ptr; }
export fn get_language_id_len() u32 { return @intCast(language_id.len); }
```

### Common LSP Servers

| Language | Command | Args |
|----------|---------|------|
| Python | `pyright-langserver` | `--stdio` |
| Python | `pylsp` | (none) |
| JavaScript/TypeScript | `typescript-language-server` | `--stdio` |
| Rust | `rust-analyzer` | (none) |
| Go | `gopls` | (none) |
| C/C++ | `clangd` | (none) |
| Zig | `zls` | (none) |

### Features

When LSP is configured, the editor provides:
- **Ctrl+Space** - Trigger autocomplete
- **↑/↓** - Navigate completion list
- **Enter/Tab** - Insert completion
- **Escape** - Close popup
- Automatic diagnostics (errors/warnings)

---

## Complete Example: Python Plugin

```zig
const std = @import("std");

// ============================================
// Metadata
// ============================================

const plugin_name: []const u8 = "Python";
const plugin_version: []const u8 = "0.0.2";
const plugin_author: []const u8 = "Moon-code Team";
const plugin_description: []const u8 = "Python language support with syntax highlighting, LSP (pyright), autocomplete, diagnostics, and go-to-definition.";
const plugin_extensions: []const u8 = ".py,.pyw";
const run_commands: []const u8 = "python3,python";

const plugin_icon: []const u8 =
    \\<svg viewBox="0 0 24 24">
    \\<path fill="#3572A5" d="M12 2c-1.5 0-2.9.3-4 .8..."/>
    \\</svg>
;

// ============================================
// LSP Configuration
// ============================================

const lsp_command: []const u8 = "pyright-langserver";
const lsp_args: []const u8 = "--stdio";
const language_id: []const u8 = "python";

// Metadata exports
export fn get_name() [*]const u8 { return plugin_name.ptr; }
export fn get_version() [*]const u8 { return plugin_version.ptr; }
export fn get_author() [*]const u8 { return plugin_author.ptr; }
export fn get_description() [*]const u8 { return plugin_description.ptr; }
export fn get_extensions() [*]const u8 { return plugin_extensions.ptr; }
export fn get_icon() [*]const u8 { return plugin_icon.ptr; }
export fn get_icon_len() u32 { return @intCast(plugin_icon.len); }
export fn get_run_command() [*]const u8 { return run_commands.ptr; }
export fn get_run_command_len() u32 { return @intCast(run_commands.len); }

// LSP exports
export fn get_lsp_command() [*]const u8 { return lsp_command.ptr; }
export fn get_lsp_command_len() u32 { return @intCast(lsp_command.len); }
export fn get_lsp_args() [*]const u8 { return lsp_args.ptr; }
export fn get_lsp_args_len() u32 { return @intCast(lsp_args.len); }
export fn get_language_id() [*]const u8 { return language_id.ptr; }
export fn get_language_id_len() u32 { return @intCast(language_id.len); }

// ============================================
// Syntax Highlighting
// ============================================

const Token = extern struct {
    start: u32,
    len: u16,
    kind: u8,
    _pad: u8 = 0,
};

const TokenType = enum(u8) {
    normal = 0,
    keyword = 1,
    type_name = 2,
    builtin = 3,
    string = 4,
    number = 5,
    comment = 6,
    function = 7,
    operator = 8,
    punctuation = 9,
    field = 10,
};

const keywords = [_][]const u8{
    "False", "None", "True", "and", "as", "assert", "async", "await",
    "break", "class", "continue", "def", "del", "elif", "else", "except",
    "finally", "for", "from", "global", "if", "import", "in", "is",
    "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
    "try", "while", "with", "yield",
};

const builtins = [_][]const u8{
    "abs", "all", "any", "bool", "dict", "enumerate", "filter", "float",
    "int", "len", "list", "map", "max", "min", "open", "print", "range",
    "set", "sorted", "str", "sum", "tuple", "type", "zip",
};

fn isKeyword(word: []const u8) bool {
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isBuiltin(word: []const u8) bool {
    for (builtins) |b| {
        if (std.mem.eql(u8, word, b)) return true;
    }
    return false;
}

fn isIdentChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
           (ch >= '0' and ch <= '9') or ch == '_';
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

export fn tokenize(src_ptr: [*]const u8, src_len: u32, out_ptr: [*]Token, max_tokens: u32) u32 {
    const source = src_ptr[0..src_len];
    const tokens = out_ptr[0..max_tokens];
    var count: u32 = 0;
    var i: u32 = 0;

    while (i < src_len and count < max_tokens) {
        // Skip whitespace
        if (source[i] == ' ' or source[i] == '\t' or source[i] == '\n' or source[i] == '\r') {
            i += 1;
            continue;
        }

        // Comment
        if (source[i] == '#') {
            const start = i;
            while (i < src_len and source[i] != '\n') : (i += 1) {}
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.comment) };
            count += 1;
            continue;
        }

        // String
        if (source[i] == '"' or source[i] == '\'') {
            const quote = source[i];
            const start = i;
            i += 1;
            while (i < src_len and source[i] != quote and source[i] != '\n') {
                if (source[i] == '\\' and i + 1 < src_len) i += 1;
                i += 1;
            }
            if (i < src_len and source[i] == quote) i += 1;
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.string) };
            count += 1;
            continue;
        }

        // Number
        if (isDigit(source[i])) {
            const start = i;
            while (i < src_len and (isDigit(source[i]) or source[i] == '.')) : (i += 1) {}
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.number) };
            count += 1;
            continue;
        }

        // Identifier / keyword / builtin
        if (isIdentChar(source[i]) and !isDigit(source[i])) {
            const start = i;
            while (i < src_len and isIdentChar(source[i])) : (i += 1) {}
            const word = source[start..i];

            var kind = TokenType.normal;
            if (isKeyword(word)) {
                kind = .keyword;
            } else if (isBuiltin(word)) {
                kind = .builtin;
            } else if (i < src_len and source[i] == '(') {
                kind = .function;
            }

            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(kind) };
            count += 1;
            continue;
        }

        // Operator/punctuation
        const start = i;
        i += 1;
        tokens[count] = .{ .start = start, .len = 1, .kind = @intFromEnum(TokenType.punctuation) };
        count += 1;
    }

    return count;
}
```

---

## Plugin Management

### Enable/Disable

Plugins can be disabled without uninstalling:
- Click plugin in sidebar
- Click "Disable" button
- Disabled plugins appear in separate section

Disabled plugins are stored in `~/.mncode/config/disabled.txt`

### Uninstall

Click "Uninstall" to completely remove the plugin WASM file.

### Auto-reload

The editor watches `~/.mncode/plugins/` directory:
- New `.wasm` files are loaded automatically
- Removed files are unloaded
- No restart required

---

## Debugging

Run editor from terminal to see plugin loading messages:

```bash
./moon-code 2>&1 | grep -i plugin
```

---

## Tips

1. **Keep WASM small** - Use `-O ReleaseSmall`
2. **No allocations** - Use fixed buffers
3. **Test tokenization** - Edge cases matter
4. **Simple SVG icons** - Complex paths may not render

---

## Future API (Planned)

These features are documented but not yet implemented:

- Custom Commands
- Snippets
- Formatters/Linters
- Host API callbacks
