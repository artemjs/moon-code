// Python syntax highlighting plugin for Moon-code
// Compiles to WASM

const std = @import("std");

// Token types (must match host)
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

const Token = extern struct {
    start: u32,
    len: u16,
    kind: u8,
    _pad: u8 = 0,
};

// Plugin info strings (in WASM memory)
const plugin_name: []const u8 = "Python";
const plugin_version: []const u8 = "0.0.2";
const plugin_author: []const u8 = "Moon-code Team";
const plugin_description: []const u8 = "Python language support with syntax highlighting, LSP (pyright), autocomplete, diagnostics, and go-to-definition.";
const plugin_extensions: []const u8 = ".py,.pyw";
// Python logo SVG (simplified)
const plugin_icon: []const u8 =
    \\<svg viewBox="0 0 24 24">
    \\<path fill="#3572A5" d="M12 2c-1.5 0-2.9.3-4 .8C6.5 3.5 6 4.5 6 5.5v2h6v1H5c-1.7 0-3.2 1.3-3.7 3-.6 2-.6 4 0 6 .5 1.7 1.7 3 3.4 3h2.3v-2.7c0-1.9 1.6-3.5 3.5-3.5h6c1.4 0 2.5-1.1 2.5-2.5v-5c0-1.4-.8-2.6-2-3.2-1.1-.5-2.5-.8-4-.8zm-3.5 2c.6 0 1 .4 1 1s-.4 1-1 1-1-.4-1-1 .4-1 1-1z"/>
    \\<path fill="#FFD43B" d="M19 8.3v2.7c0 1.9-1.6 3.5-3.5 3.5h-6c-1.4 0-2.5 1.1-2.5 2.5v5c0 1.4.8 2.6 2 3.2 1.1.5 2.5.8 4 .8 1.5 0 2.9-.3 4-.8 1.5-.7 2-1.7 2-2.7v-2h-6v-1h9c1.7 0 2.4-1.2 3-3 .6-2 .6-4 0-6-.4-1.4-1.2-3-3-3h-3zm-3.5 12c.6 0 1 .4 1 1s-.4 1-1 1-1-.4-1-1 .4-1 1-1z"/>
    \\</svg>
;

// Python keywords
const keywords = [_][]const u8{
    "False", "None", "True", "and", "as", "assert", "async", "await",
    "break", "class", "continue", "def", "del", "elif", "else", "except",
    "finally", "for", "from", "global", "if", "import", "in", "is",
    "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
    "try", "while", "with", "yield",
};

// Python builtins
const builtins = [_][]const u8{
    "abs", "all", "any", "bin", "bool", "bytearray", "bytes", "callable",
    "chr", "classmethod", "compile", "complex", "delattr", "dict", "dir",
    "divmod", "enumerate", "eval", "exec", "filter", "float", "format",
    "frozenset", "getattr", "globals", "hasattr", "hash", "help", "hex",
    "id", "input", "int", "isinstance", "issubclass", "iter", "len",
    "list", "locals", "map", "max", "memoryview", "min", "next", "object",
    "oct", "open", "ord", "pow", "print", "property", "range", "repr",
    "reversed", "round", "set", "setattr", "slice", "sorted", "staticmethod",
    "str", "sum", "super", "tuple", "type", "vars", "zip", "__import__",
    "self", "cls",
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
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_';
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

// Export: get plugin name
export fn get_name() [*]const u8 {
    return plugin_name.ptr;
}

// Export: get plugin version
export fn get_version() [*]const u8 {
    return plugin_version.ptr;
}

// Export: get plugin author
export fn get_author() [*]const u8 {
    return plugin_author.ptr;
}

// Export: get plugin description
export fn get_description() [*]const u8 {
    return plugin_description.ptr;
}

// Export: get plugin SVG icon
export fn get_icon() [*]const u8 {
    return plugin_icon.ptr;
}

// Export: get icon length (needed for SVG parsing)
export fn get_icon_len() u32 {
    return @intCast(plugin_icon.len);
}

// Export: get supported extensions
export fn get_extensions() [*]const u8 {
    return plugin_extensions.ptr;
}

// Run commands for this language (comma-separated, tried in order)
const run_commands: []const u8 = "python3,python";

// Export: get run commands (comma-separated fallbacks)
export fn get_run_command() [*]const u8 {
    return run_commands.ptr;
}

// Export: get run commands length
export fn get_run_command_len() u32 {
    return @intCast(run_commands.len);
}

// ============================================================================
// LSP SUPPORT
// ============================================================================

// LSP server command (pyright-langserver or pylsp)
// Tries pyright first (faster), falls back to pylsp
const lsp_command: []const u8 = "pyright-langserver";

// LSP server arguments
const lsp_args: []const u8 = "--stdio";

// Language ID for LSP protocol
const language_id: []const u8 = "python";

// Export: get LSP command
export fn get_lsp_command() [*]const u8 {
    return lsp_command.ptr;
}

// Export: get LSP command length
export fn get_lsp_command_len() u32 {
    return @intCast(lsp_command.len);
}

// Export: get LSP args
export fn get_lsp_args() [*]const u8 {
    return lsp_args.ptr;
}

// Export: get LSP args length
export fn get_lsp_args_len() u32 {
    return @intCast(lsp_args.len);
}

// Export: get language ID
export fn get_language_id() [*]const u8 {
    return language_id.ptr;
}

// Export: get language ID length
export fn get_language_id_len() u32 {
    return @intCast(language_id.len);
}

// Export: tokenize source code
// src_ptr: pointer to source text in WASM memory
// src_len: length of source text
// out_ptr: pointer to output token array in WASM memory
// max_tokens: maximum number of tokens to output
// returns: number of tokens written
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

        // String literals
        if (source[i] == '"' or source[i] == '\'') {
            const quote = source[i];
            const start = i;

            // Check for triple-quoted string
            if (i + 2 < src_len and source[i + 1] == quote and source[i + 2] == quote) {
                i += 3;
                while (i + 2 < src_len) {
                    if (source[i] == quote and source[i + 1] == quote and source[i + 2] == quote) {
                        i += 3;
                        break;
                    }
                    i += 1;
                }
            } else {
                i += 1;
                while (i < src_len and source[i] != quote and source[i] != '\n') {
                    if (source[i] == '\\' and i + 1 < src_len) i += 1;
                    i += 1;
                }
                if (i < src_len and source[i] == quote) i += 1;
            }

            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.string) };
            count += 1;
            continue;
        }

        // f-string, r-string, b-string prefix
        if ((source[i] == 'f' or source[i] == 'r' or source[i] == 'b' or source[i] == 'F' or source[i] == 'R' or source[i] == 'B') and
            i + 1 < src_len and (source[i + 1] == '"' or source[i + 1] == '\''))
        {
            const start = i;
            const quote = source[i + 1];
            i += 2;
            while (i < src_len and source[i] != quote and source[i] != '\n') {
                if (source[i] == '\\' and i + 1 < src_len) i += 1;
                i += 1;
            }
            if (i < src_len and source[i] == quote) i += 1;
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.string) };
            count += 1;
            continue;
        }

        // Numbers
        if (isDigit(source[i])) {
            const start = i;
            while (i < src_len and (isDigit(source[i]) or source[i] == '.' or source[i] == 'e' or
                source[i] == 'E' or source[i] == 'x' or source[i] == 'X' or source[i] == '_' or
                source[i] == 'j' or source[i] == 'J' or
                (source[i] >= 'a' and source[i] <= 'f') or (source[i] >= 'A' and source[i] <= 'F'))) : (i += 1)
            {}
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.number) };
            count += 1;
            continue;
        }

        // Identifier / keyword / builtin
        if (isIdentChar(source[i]) and !isDigit(source[i])) {
            const start = i;
            while (i < src_len and isIdentChar(source[i])) : (i += 1) {}
            const word = source[start..i];

            var kind: TokenType = .normal;
            if (isKeyword(word)) {
                kind = .keyword;
            } else if (isBuiltin(word)) {
                kind = .builtin;
            } else if (i < src_len and source[i] == '(') {
                kind = .function;
            } else if (start > 0 and source[start - 1] == '.') {
                kind = .field;
            }

            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(kind) };
            count += 1;
            continue;
        }

        // Decorator
        if (source[i] == '@') {
            const start = i;
            i += 1;
            while (i < src_len and isIdentChar(source[i])) : (i += 1) {}
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.builtin) };
            count += 1;
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        tokens[count] = .{ .start = start, .len = 1, .kind = @intFromEnum(TokenType.punctuation) };
        count += 1;
    }

    return count;
}
