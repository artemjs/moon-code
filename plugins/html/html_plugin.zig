// HTML syntax highlighting plugin for Moon-code
// Compiles to WASM

const std = @import("std");

// Token types (must match host)
const TokenType = enum(u8) {
    normal = 0,
    keyword = 1, // tag names
    type_name = 2, // attribute names
    builtin = 3, // DOCTYPE, entities
    string = 4, // attribute values
    number = 5,
    comment = 6,
    function = 7,
    operator = 8, // < > / =
    punctuation = 9,
    field = 10,
    error_tok = 11, // syntax errors (red)
};

const Token = extern struct {
    start: u32,
    len: u16,
    kind: u8,
    _pad: u8 = 0,
};

// Plugin info
const plugin_name: []const u8 = "HTML";
const plugin_version: []const u8 = "1.0.0";
const plugin_author: []const u8 = "Moon-code Team";
const plugin_description: []const u8 = "HTML/XML syntax highlighting with tag, attribute, and comment support.";
const plugin_extensions: []const u8 = ".html,.htm,.xml,.xhtml,.svg";

// HTML5 logo SVG
const plugin_icon: []const u8 =
    \\<svg viewBox="0 0 24 24">
    \\<path fill="#E44D26" d="M4.5 3l1.4 15.5L12 21l6.1-2.5L19.5 3H4.5zm12.3 5H8.3l.2 2h8.1l-.6 6.5-4 1.3-4-1.3-.3-3h2l.1 1.5 2.2.6 2.2-.6.2-2.5H7.9l-.5-6h9.2l.2-2z"/>
    \\</svg>
;

// Self-closing HTML tags
const void_tags = [_][]const u8{
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
};

fn isVoidTag(tag: []const u8) bool {
    for (void_tags) |vt| {
        if (std.mem.eql(u8, tag, vt)) return true;
    }
    return false;
}

fn isIdentChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or ch == '-' or ch == ':';
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
}

fn toLower(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}

// Export functions
export fn get_name() [*]const u8 {
    return plugin_name.ptr;
}

export fn get_version() [*]const u8 {
    return plugin_version.ptr;
}

export fn get_author() [*]const u8 {
    return plugin_author.ptr;
}

export fn get_description() [*]const u8 {
    return plugin_description.ptr;
}

export fn get_icon() [*]const u8 {
    return plugin_icon.ptr;
}

export fn get_icon_len() u32 {
    return @intCast(plugin_icon.len);
}

export fn get_extensions() [*]const u8 {
    return plugin_extensions.ptr;
}

// Tokenize HTML source code
export fn tokenize(src_ptr: [*]const u8, src_len: u32, out_ptr: [*]Token, max_tokens: u32) u32 {
    const source = src_ptr[0..src_len];
    const tokens = out_ptr[0..max_tokens];

    var count: u32 = 0;
    var i: u32 = 0;

    while (i < src_len and count < max_tokens) {
        // Skip whitespace
        if (isWhitespace(source[i])) {
            i += 1;
            continue;
        }

        // HTML Comment <!-- ... -->
        if (i + 3 < src_len and source[i] == '<' and source[i + 1] == '!' and
            source[i + 2] == '-' and source[i + 3] == '-')
        {
            const start = i;
            i += 4;
            var found_end = false;
            while (i + 2 < src_len) {
                if (source[i] == '-' and source[i + 1] == '-' and source[i + 2] == '>') {
                    i += 3;
                    found_end = true;
                    break;
                }
                i += 1;
            }
            if (!found_end) {
                // Unclosed comment - mark as error
                i = src_len;
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.error_tok) };
            } else {
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.comment) };
            }
            count += 1;
            continue;
        }

        // DOCTYPE
        if (i + 8 < src_len and source[i] == '<' and source[i + 1] == '!') {
            // Check for DOCTYPE (case insensitive)
            if ((source[i + 2] == 'D' or source[i + 2] == 'd') and
                (source[i + 3] == 'O' or source[i + 3] == 'o') and
                (source[i + 4] == 'C' or source[i + 4] == 'c') and
                (source[i + 5] == 'T' or source[i + 5] == 't') and
                (source[i + 6] == 'Y' or source[i + 6] == 'y') and
                (source[i + 7] == 'P' or source[i + 7] == 'p') and
                (source[i + 8] == 'E' or source[i + 8] == 'e'))
            {
                const start = i;
                while (i < src_len and source[i] != '>') : (i += 1) {}
                if (i < src_len) i += 1;
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.builtin) };
                count += 1;
                continue;
            }
        }

        // CDATA section
        if (i + 8 < src_len and source[i] == '<' and source[i + 1] == '!' and
            source[i + 2] == '[' and source[i + 3] == 'C' and source[i + 4] == 'D' and
            source[i + 5] == 'A' and source[i + 6] == 'T' and source[i + 7] == 'A' and
            source[i + 8] == '[')
        {
            const start = i;
            i += 9;
            var found_end = false;
            while (i + 2 < src_len) {
                if (source[i] == ']' and source[i + 1] == ']' and source[i + 2] == '>') {
                    i += 3;
                    found_end = true;
                    break;
                }
                i += 1;
            }
            if (!found_end) {
                i = src_len;
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.error_tok) };
            } else {
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.string) };
            }
            count += 1;
            continue;
        }

        // Opening or closing tag
        if (source[i] == '<') {
            // Tag start <
            tokens[count] = .{ .start = i, .len = 1, .kind = @intFromEnum(TokenType.operator) };
            count += 1;
            i += 1;
            if (count >= max_tokens) break;

            // Check for closing tag /
            if (i < src_len and source[i] == '/') {
                tokens[count] = .{ .start = i, .len = 1, .kind = @intFromEnum(TokenType.operator) };
                count += 1;
                i += 1;
                if (count >= max_tokens) break;
            }

            // Tag name
            if (i < src_len and (isIdentChar(source[i]) or source[i] == '!')) {
                const tag_start = i;
                while (i < src_len and isIdentChar(source[i])) : (i += 1) {}
                tokens[count] = .{ .start = tag_start, .len = @intCast(i - tag_start), .kind = @intFromEnum(TokenType.keyword) };
                count += 1;
                if (count >= max_tokens) break;
            }

            // Parse attributes until >
            while (i < src_len and source[i] != '>' and count < max_tokens) {
                // Skip whitespace
                while (i < src_len and isWhitespace(source[i])) : (i += 1) {}
                if (i >= src_len or source[i] == '>') break;

                // Self-closing /
                if (source[i] == '/') {
                    tokens[count] = .{ .start = i, .len = 1, .kind = @intFromEnum(TokenType.operator) };
                    count += 1;
                    i += 1;
                    continue;
                }

                // Attribute name
                if (isIdentChar(source[i])) {
                    const attr_start = i;
                    while (i < src_len and isIdentChar(source[i])) : (i += 1) {}
                    tokens[count] = .{ .start = attr_start, .len = @intCast(i - attr_start), .kind = @intFromEnum(TokenType.type_name) };
                    count += 1;
                    if (count >= max_tokens) break;

                    // Skip whitespace
                    while (i < src_len and isWhitespace(source[i])) : (i += 1) {}

                    // = sign
                    if (i < src_len and source[i] == '=') {
                        tokens[count] = .{ .start = i, .len = 1, .kind = @intFromEnum(TokenType.operator) };
                        count += 1;
                        i += 1;
                        if (count >= max_tokens) break;

                        // Skip whitespace
                        while (i < src_len and isWhitespace(source[i])) : (i += 1) {}

                        // Attribute value
                        if (i < src_len and (source[i] == '"' or source[i] == '\'')) {
                            const quote = source[i];
                            const val_start = i;
                            i += 1;
                            while (i < src_len and source[i] != quote and source[i] != '\n') : (i += 1) {}
                            if (i < src_len and source[i] == quote) {
                                i += 1;
                                tokens[count] = .{ .start = val_start, .len = @intCast(i - val_start), .kind = @intFromEnum(TokenType.string) };
                            } else {
                                // Unclosed string - mark as error
                                tokens[count] = .{ .start = val_start, .len = @intCast(i - val_start), .kind = @intFromEnum(TokenType.error_tok) };
                            }
                            count += 1;
                        } else if (i < src_len and !isWhitespace(source[i]) and source[i] != '>') {
                            // Unquoted value
                            const val_start = i;
                            while (i < src_len and !isWhitespace(source[i]) and source[i] != '>' and source[i] != '/') : (i += 1) {}
                            tokens[count] = .{ .start = val_start, .len = @intCast(i - val_start), .kind = @intFromEnum(TokenType.string) };
                            count += 1;
                        }
                    }
                    continue;
                }

                // Unknown character in tag, skip
                i += 1;
            }

            // Tag end >
            if (i < src_len and source[i] == '>') {
                tokens[count] = .{ .start = i, .len = 1, .kind = @intFromEnum(TokenType.operator) };
                count += 1;
                i += 1;
            }
            continue;
        }

        // Entity reference &...;
        if (source[i] == '&') {
            const start = i;
            i += 1;
            // Check if it looks like an entity (alphanumeric or # for numeric)
            var has_content = false;
            while (i < src_len and source[i] != ';' and source[i] != ' ' and source[i] != '<' and source[i] != '\n' and i - start < 12) : (i += 1) {
                has_content = true;
            }
            if (i < src_len and source[i] == ';' and has_content) {
                i += 1;
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.builtin) };
                count += 1;
                continue;
            }
            // Invalid entity - mark as error
            if (has_content) {
                tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.error_tok) };
                count += 1;
                continue;
            }
            // Just a lone &
            tokens[count] = .{ .start = start, .len = 1, .kind = @intFromEnum(TokenType.punctuation) };
            count += 1;
            i = start + 1;
            continue;
        }

        // Regular text - skip to next < or &
        const start = i;
        while (i < src_len and source[i] != '<' and source[i] != '&' and !isWhitespace(source[i])) : (i += 1) {}
        if (i > start) {
            tokens[count] = .{ .start = start, .len = @intCast(i - start), .kind = @intFromEnum(TokenType.normal) };
            count += 1;
        }
    }

    return count;
}

// ============================================
// Auto-insert and Smart Enter
// ============================================

// Output buffer for on_char/on_enter results
var g_output_buf: [256]u8 = undefined;

// Check if position is inside an HTML comment
fn isInsideComment(source: []const u8, pos: u32) bool {
    if (pos < 4) return false;

    // Search backwards for <!-- or -->
    var i: u32 = pos;
    while (i >= 4) {
        i -= 1;
        // Check for -->
        if (i >= 2 and source[i] == '>' and source[i - 1] == '-' and source[i - 2] == '-') {
            return false; // Comment was closed before this position
        }
        // Check for <!--
        if (i >= 3 and source[i - 3] == '<' and source[i - 2] == '!' and source[i - 1] == '-' and source[i] == '-') {
            return true; // We're inside an unclosed comment
        }
    }
    return false;
}

// Check if position is inside a quoted string (within a tag)
fn isInsideString(source: []const u8, pos: u32) bool {
    if (pos == 0) return false;

    // Find the last < before pos to determine tag context
    var tag_start: u32 = pos;
    while (tag_start > 0) {
        tag_start -= 1;
        if (source[tag_start] == '<') break;
        if (source[tag_start] == '>') return false; // Outside any tag
    }

    // Count quotes between tag_start and pos
    var in_double_quote = false;
    var in_single_quote = false;
    var i: u32 = tag_start;
    while (i < pos) : (i += 1) {
        if (source[i] == '"' and !in_single_quote) {
            in_double_quote = !in_double_quote;
        } else if (source[i] == '\'' and !in_double_quote) {
            in_single_quote = !in_single_quote;
        }
    }

    return in_double_quote or in_single_quote;
}

// Find tag name for auto-closing when > is typed
// Returns null if should not auto-close
fn findTagToClose(source: []const u8, cursor: u32) ?[]const u8 {
    if (cursor < 2) return null;

    // The > should be at cursor - 1 (just typed)
    if (source[cursor - 1] != '>') return null;

    // Check if we're inside a comment
    if (isInsideComment(source, cursor)) return null;

    // Check if we're inside a string
    if (isInsideString(source, cursor - 1)) return null;

    // Scan backwards to find the opening <
    var i: u32 = cursor - 2;
    while (i > 0 and source[i] != '<' and source[i] != '>') : (i -= 1) {}

    // Handle i = 0 case
    if (source[i] != '<') {
        if (i == 0 and source[0] == '<') {
            // OK, found < at position 0
        } else {
            return null; // Found > or didn't find <
        }
    }

    const tag_open_pos = i;
    const after_open = tag_open_pos + 1;

    if (after_open >= cursor - 1) return null; // Empty tag <>

    // Check for special cases that should NOT auto-close:
    // 1. Closing tag: </tag>
    if (source[after_open] == '/') return null;

    // 2. DOCTYPE, CDATA, etc: <!...>
    if (source[after_open] == '!') return null;

    // 3. Processing instruction: <?...?>
    if (source[after_open] == '?') return null;

    // 4. Self-closing tag: <tag/>
    if (cursor >= 2 and source[cursor - 2] == '/') return null;

    // Extract tag name (first identifier after <)
    const name_start = after_open;
    var name_end = name_start;

    while (name_end < cursor - 1 and isIdentChar(source[name_end])) : (name_end += 1) {}

    if (name_end == name_start) return null; // No tag name

    const tag_name = source[name_start..name_end];

    // Check if it's a void tag
    if (isVoidTag(tag_name)) return null;

    // Check lowercase version for void tags too
    var lower_buf: [32]u8 = undefined;
    if (tag_name.len <= 32) {
        for (tag_name, 0..) |ch, idx| {
            lower_buf[idx] = toLower(ch);
        }
        if (isVoidTag(lower_buf[0..tag_name.len])) return null;
    }

    return tag_name;
}

// Get current line indentation
fn getLineIndent(source: []const u8, cursor: u32) []const u8 {
    if (cursor == 0) return "";

    // Find start of current line
    var line_start: u32 = cursor;
    while (line_start > 0 and source[line_start - 1] != '\n') {
        line_start -= 1;
    }

    // Count leading whitespace
    var indent_end = line_start;
    while (indent_end < cursor and (source[indent_end] == ' ' or source[indent_end] == '\t')) {
        indent_end += 1;
    }

    return source[line_start..indent_end];
}

// Check if cursor is between > and </ (e.g., <div>|</div>)
fn isBetweenOpenAndClose(source: []const u8, cursor: u32, len: u32) bool {
    if (cursor == 0 or cursor >= len) return false;

    // Check if previous char is >
    if (source[cursor - 1] != '>') return false;

    // Check if next chars are </
    if (cursor + 1 < len and source[cursor] == '<' and source[cursor + 1] == '/') {
        return true;
    }

    return false;
}

// Find existing closing tag after position, returns length to delete (including </>)
fn findExistingCloseTag(source: []const u8, pos: u32, len: u32) u16 {
    if (pos >= len) return 0;

    // Must start with </
    if (pos + 1 >= len or source[pos] != '<' or source[pos + 1] != '/') return 0;

    // Find the >
    var end_pos: u32 = pos + 2;
    while (end_pos < len and source[end_pos] != '>' and source[end_pos] != '\n' and source[end_pos] != '<') {
        end_pos += 1;
    }

    if (end_pos < len and source[end_pos] == '>') {
        return @intCast(end_pos - pos + 1); // Include the >
    }

    return 0;
}

// Check if cursor is inside an opening tag <tagname|> (between < and >)
// Returns tag start position if true, null otherwise
fn getCursorTagContext(source: []const u8, cursor: u32, len: u32) ?struct { tag_start: u32, tag_end: u32 } {
    if (cursor == 0 or cursor >= len) return null;

    // Find < before cursor
    var tag_start: u32 = cursor;
    while (tag_start > 0) {
        tag_start -= 1;
        if (source[tag_start] == '<') break;
        if (source[tag_start] == '>') return null; // Cursor is outside tags
    }

    if (source[tag_start] != '<') return null;

    // Check it's not a closing tag </
    if (tag_start + 1 < len and source[tag_start + 1] == '/') return null;

    // Check it's not a comment <!--
    if (tag_start + 3 < len and source[tag_start + 1] == '!' and
        source[tag_start + 2] == '-' and source[tag_start + 3] == '-') return null;

    // Check it's not DOCTYPE <!
    if (tag_start + 1 < len and source[tag_start + 1] == '!') return null;

    // Check it's not processing instruction <?
    if (tag_start + 1 < len and source[tag_start + 1] == '?') return null;

    // Find > after cursor
    var tag_end: u32 = cursor;
    while (tag_end < len and source[tag_end] != '>') {
        if (source[tag_end] == '<') return null; // Another tag started
        tag_end += 1;
    }

    if (tag_end >= len or source[tag_end] != '>') return null;

    return .{ .tag_start = tag_start, .tag_end = tag_end };
}

// Extract tag name from <tagname ...>
fn extractTagName(source: []const u8, tag_start: u32, tag_end: u32) ?[]const u8 {
    const name_start = tag_start + 1;
    if (name_start >= tag_end) return null;

    var name_end = name_start;
    while (name_end < tag_end and isIdentChar(source[name_end])) {
        name_end += 1;
    }

    if (name_end == name_start) return null;
    return source[name_start..name_end];
}

/// Called when user types a character
/// Returns: (delete_after << 16) | insert_len
/// delete_after: number of chars to delete after cursor before inserting
/// insert_len: length of text to insert (written to out_ptr)
export fn on_char(src_ptr: [*]const u8, src_len: u32, cursor: u32, char: u8, out_ptr: [*]u8) u32 {
    const source = src_ptr[0..src_len];

    // Case 1: Typing > to close a tag - standard auto-close
    if (char == '>') {
        if (findTagToClose(source, cursor)) |tag_name| {
            // Check if void tag
            if (isVoidTag(tag_name)) return 0;

            // Check lowercase version
            var lower_buf: [32]u8 = undefined;
            if (tag_name.len <= 32) {
                for (tag_name, 0..) |ch, idx| {
                    lower_buf[idx] = toLower(ch);
                }
                if (isVoidTag(lower_buf[0..tag_name.len])) return 0;
            }

            // Build closing tag: </tagname>
            var out_len: u32 = 0;

            out_ptr[out_len] = '<';
            out_len += 1;
            out_ptr[out_len] = '/';
            out_len += 1;

            for (tag_name) |c| {
                if (out_len < 200) {
                    out_ptr[out_len] = c;
                    out_len += 1;
                }
            }

            out_ptr[out_len] = '>';
            out_len += 1;

            return out_len; // Just insert, no delete
        }
        return 0;
    }

    // Case 2: Typing inside <tagname|> - real-time update of closing tag
    // This happens when user types <>, then fills in tag name
    if (isIdentChar(char)) {
        // Check if we're inside an opening tag
        if (getCursorTagContext(source, cursor, src_len)) |ctx| {
            // Get current tag name (after the char is inserted, it's in source already)
            if (extractTagName(source, ctx.tag_start, ctx.tag_end)) |tag_name| {
                // Check if void tag - don't auto-close
                if (isVoidTag(tag_name)) return 0;

                var lower_buf: [32]u8 = undefined;
                if (tag_name.len <= 32) {
                    for (tag_name, 0..) |ch, idx| {
                        lower_buf[idx] = toLower(ch);
                    }
                    if (isVoidTag(lower_buf[0..tag_name.len])) return 0;
                }

                // Calculate what to delete:
                // 1. Characters from cursor to > (inclusive)
                // 2. Any existing closing tag after >
                const chars_to_end: u32 = ctx.tag_end - cursor + 1;
                const after_tag = ctx.tag_end + 1;
                const existing_close_len = findExistingCloseTag(source, after_tag, src_len);
                const total_delete: u32 = chars_to_end + existing_close_len;

                // Build output: chars from cursor to > + new closing tag
                var out_len: u32 = 0;

                // First, copy chars from cursor to tag_end (inclusive)
                var skip_i = cursor;
                while (skip_i <= ctx.tag_end and out_len < 200) {
                    out_ptr[out_len] = source[skip_i];
                    out_len += 1;
                    skip_i += 1;
                }

                // Then add closing tag </tagname>
                out_ptr[out_len] = '<';
                out_len += 1;
                out_ptr[out_len] = '/';
                out_len += 1;

                for (tag_name) |c| {
                    if (out_len < 200) {
                        out_ptr[out_len] = c;
                        out_len += 1;
                    }
                }

                out_ptr[out_len] = '>';
                out_len += 1;

                // Return: (delete_after << 16) | insert_len
                return (total_delete << 16) | out_len;
            }
        }
    }

    return 0;
}

/// Called when user presses Enter
/// Returns length of text to insert (written to out_ptr), 0 for default behavior
export fn on_enter(src_ptr: [*]const u8, src_len: u32, cursor: u32, out_ptr: [*]u8) u32 {
    const source = src_ptr[0..src_len];

    // Check if cursor is between > and </ (e.g., <div>|</div>)
    if (isBetweenOpenAndClose(source, cursor, src_len)) {
        const indent = getLineIndent(source, cursor);
        var out_len: u32 = 0;

        // Insert: \n + indent + 4 spaces + \n + indent
        out_ptr[out_len] = '\n';
        out_len += 1;

        // Copy existing indent
        for (indent) |c| {
            if (out_len < 200) {
                out_ptr[out_len] = c;
                out_len += 1;
            }
        }

        // Add extra indent (4 spaces)
        var spaces: u32 = 0;
        while (spaces < 4 and out_len < 200) : (spaces += 1) {
            out_ptr[out_len] = ' ';
            out_len += 1;
        }

        // Add cursor marker position (editor will place cursor here)
        const cursor_pos = out_len;
        _ = cursor_pos;

        // Add newline for closing tag
        out_ptr[out_len] = '\n';
        out_len += 1;

        // Copy original indent for closing tag
        for (indent) |c| {
            if (out_len < 200) {
                out_ptr[out_len] = c;
                out_len += 1;
            }
        }

        return out_len;
    }

    // Check if previous char is > (after opening tag)
    if (cursor > 0 and source[cursor - 1] == '>') {
        const indent = getLineIndent(source, cursor);
        var out_len: u32 = 0;

        // Insert: \n + indent + 4 spaces
        out_ptr[out_len] = '\n';
        out_len += 1;

        // Copy existing indent
        for (indent) |c| {
            if (out_len < 200) {
                out_ptr[out_len] = c;
                out_len += 1;
            }
        }

        // Add extra indent (4 spaces)
        var spaces: u32 = 0;
        while (spaces < 4 and out_len < 200) : (spaces += 1) {
            out_ptr[out_len] = ' ';
            out_len += 1;
        }

        return out_len;
    }

    // Check if next char is < (before closing tag)
    if (cursor < src_len and source[cursor] == '<') {
        // Check if it's a closing tag
        if (cursor + 1 < src_len and source[cursor + 1] == '/') {
            const indent = getLineIndent(source, cursor);
            var out_len: u32 = 0;

            // Insert: \n + indent (same level as closing tag)
            out_ptr[out_len] = '\n';
            out_len += 1;

            // Copy existing indent
            for (indent) |c| {
                if (out_len < 200) {
                    out_ptr[out_len] = c;
                    out_len += 1;
                }
            }

            return out_len;
        }
    }

    return 0; // Use default Enter behavior
}
