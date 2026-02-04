// Moon-code Plugin API v2.0
// Full-featured plugin system for syntax highlighting, LSP, commands, and UI

const std = @import("std");
const loader = @import("loader.zig");

// ============================================================================
// PLUGIN CAPABILITIES
// ============================================================================

/// Plugin capabilities flags
pub const PluginCapabilities = packed struct(u16) {
    syntax_highlighting: bool = false,
    lsp_support: bool = false,
    formatter: bool = false,
    linter: bool = false,
    debugger: bool = false,
    run_command: bool = false,
    build_command: bool = false,
    test_command: bool = false,
    custom_commands: bool = false,
    snippets: bool = false,
    code_actions: bool = false,
    outline: bool = false,
    folding: bool = false,
    hover_info: bool = false,
    signature_help: bool = false,
    _padding: u1 = 0,
};

// ============================================================================
// SYNTAX HIGHLIGHTING
// ============================================================================

/// Token types for syntax highlighting
pub const TokenType = enum(u8) {
    // Basic
    text = 0,
    whitespace = 1,

    // Comments
    comment = 10,
    comment_line = 11,
    comment_block = 12,
    comment_doc = 13,

    // Strings
    string = 20,
    string_single = 21,
    string_double = 22,
    string_template = 23,
    string_regex = 24,
    string_escape = 25,
    string_interpolation = 26,

    // Numbers
    number = 30,
    number_integer = 31,
    number_float = 32,
    number_hex = 33,
    number_binary = 34,
    number_octal = 35,

    // Keywords
    keyword = 40,
    keyword_control = 41, // if, else, for, while, return
    keyword_operator = 42, // and, or, not, in, is
    keyword_declaration = 43, // fn, const, var, let, class, struct
    keyword_modifier = 44, // pub, async, static, mut
    keyword_type = 45, // type keywords
    keyword_other = 46,

    // Identifiers
    identifier = 50,
    variable = 51,
    variable_parameter = 52,
    variable_readonly = 53,
    constant = 54,
    function = 55,
    function_builtin = 56,
    method = 57,
    class = 58,
    struct_name = 59,
    enum_name = 60,
    enum_member = 61,
    interface = 62,
    type_name = 63,
    type_parameter = 64,
    namespace = 65,
    module = 66,
    property = 67,
    field = 68,
    label = 69,

    // Built-ins
    builtin = 70,
    builtin_function = 71,
    builtin_type = 72,
    builtin_constant = 73,

    // Operators & Punctuation
    operator = 80,
    operator_arithmetic = 81,
    operator_comparison = 82,
    operator_logical = 83,
    operator_bitwise = 84,
    operator_assignment = 85,
    punctuation = 86,
    punctuation_bracket = 87,
    punctuation_delimiter = 88,
    punctuation_accessor = 89,

    // Special
    decorator = 90,
    attribute = 91,
    annotation = 92,
    macro = 93,
    preprocessor = 94,
    tag = 95, // HTML/XML tags
    tag_attribute = 96,

    // Errors/Warnings (for inline diagnostics)
    error_token = 100,
    warning_token = 101,
    info_token = 102,
    hint_token = 103,

    // Invalid
    invalid = 255,
};

/// Token structure for WASM communication
pub const SyntaxToken = extern struct {
    start: u32, // Byte offset in source
    len: u16, // Length in bytes
    kind: u8, // TokenType
    flags: u8 = 0, // Reserved for future use
};

/// Syntax state for multi-line constructs
pub const SyntaxState = extern struct {
    in_multiline_string: bool = false,
    in_multiline_comment: bool = false,
    string_delimiter: u8 = 0,
    nesting_depth: u8 = 0,
    reserved: [4]u8 = [_]u8{0} ** 4,
};

// ============================================================================
// LSP TYPES
// ============================================================================

/// Completion item kind
pub const CompletionKind = enum(u8) {
    text = 1,
    method = 2,
    function = 3,
    constructor = 4,
    field = 5,
    variable = 6,
    class = 7,
    interface = 8,
    module = 9,
    property = 10,
    unit = 11,
    value = 12,
    enum_item = 13,
    keyword = 14,
    snippet = 15,
    color = 16,
    file = 17,
    reference = 18,
    folder = 19,
    enum_member = 20,
    constant = 21,
    struct_item = 22,
    event = 23,
    operator = 24,
    type_parameter = 25,
};

/// Diagnostic severity
pub const DiagnosticSeverity = enum(u8) {
    error_sev = 1,
    warning_sev = 2,
    info_sev = 3,
    hint_sev = 4,
};

/// Symbol kind for outline/workspace symbols
pub const SymbolKind = enum(u8) {
    file = 1,
    module = 2,
    namespace = 3,
    package = 4,
    class = 5,
    method = 6,
    property = 7,
    field = 8,
    constructor = 9,
    enum_kind = 10,
    interface = 11,
    function = 12,
    variable = 13,
    constant = 14,
    string_kind = 15,
    number_kind = 16,
    boolean_kind = 17,
    array = 18,
    object = 19,
    key = 20,
    null_kind = 21,
    enum_member = 22,
    struct_kind = 23,
    event = 24,
    operator = 25,
    type_parameter = 26,
};

/// Code action kind
pub const CodeActionKind = enum(u8) {
    quickfix = 1,
    refactor = 2,
    refactor_extract = 3,
    refactor_inline = 4,
    refactor_rewrite = 5,
    source = 6,
    source_organize_imports = 7,
    source_fix_all = 8,
};

/// Completion item (WASM-friendly)
pub const CompletionItem = extern struct {
    label: [64]u8 = [_]u8{0} ** 64,
    label_len: u8 = 0,
    kind: u8 = 1, // CompletionKind
    detail: [128]u8 = [_]u8{0} ** 128,
    detail_len: u8 = 0,
    insert_text: [128]u8 = [_]u8{0} ** 128,
    insert_text_len: u8 = 0,
    sort_priority: u16 = 0,
    deprecated: bool = false,
    _pad: [2]u8 = [_]u8{0} ** 2,
};

/// Diagnostic (WASM-friendly)
pub const Diagnostic = extern struct {
    start_line: u32 = 0,
    start_col: u16 = 0,
    end_line: u32 = 0,
    end_col: u16 = 0,
    severity: u8 = 1, // DiagnosticSeverity
    _pad: u8 = 0,
    message: [256]u8 = [_]u8{0} ** 256,
    message_len: u16 = 0,
    code: [16]u8 = [_]u8{0} ** 16,
    code_len: u8 = 0,
    source: [32]u8 = [_]u8{0} ** 32,
    source_len: u8 = 0,
};

/// Location (for goto definition, references)
pub const Location = extern struct {
    file_path: [256]u8 = [_]u8{0} ** 256,
    file_path_len: u16 = 0,
    start_line: u32 = 0,
    start_col: u16 = 0,
    end_line: u32 = 0,
    end_col: u16 = 0,
};

/// Symbol information
pub const SymbolInfo = extern struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: u8 = 0,
    kind: u8 = 0, // SymbolKind
    container: [64]u8 = [_]u8{0} ** 64,
    container_len: u8 = 0,
    start_line: u32 = 0,
    start_col: u16 = 0,
    end_line: u32 = 0,
    end_col: u16 = 0,
    deprecated: bool = false,
    _pad: u8 = 0,
};

/// Hover information
pub const HoverInfo = extern struct {
    content: [2048]u8 = [_]u8{0} ** 2048,
    content_len: u16 = 0,
    is_markdown: bool = false,
    _pad: u8 = 0,
    range_start_line: u32 = 0,
    range_start_col: u16 = 0,
    range_end_line: u32 = 0,
    range_end_col: u16 = 0,
};

/// Code action
pub const CodeAction = extern struct {
    title: [64]u8 = [_]u8{0} ** 64,
    title_len: u8 = 0,
    kind: u8 = 1, // CodeActionKind
    is_preferred: bool = false,
    _pad: u8 = 0,
    // Edit is returned via callback
};

/// Folding range
pub const FoldingRange = extern struct {
    start_line: u32 = 0,
    end_line: u32 = 0,
    kind: u8 = 3, // 1=comment, 2=imports, 3=region
    _pad: [3]u8 = [_]u8{0} ** 3,
};

/// Signature help
pub const SignatureInfo = extern struct {
    label: [256]u8 = [_]u8{0} ** 256,
    label_len: u16 = 0,
    documentation: [512]u8 = [_]u8{0} ** 512,
    documentation_len: u16 = 0,
    active_parameter: u8 = 0,
    param_count: u8 = 0,
    // Parameters stored separately
};

/// Parameter info for signature help
pub const ParameterInfo = extern struct {
    label: [64]u8 = [_]u8{0} ** 64,
    label_len: u8 = 0,
    documentation: [256]u8 = [_]u8{0} ** 256,
    documentation_len: u16 = 0,
    _pad: u8 = 0,
};

// ============================================================================
// COMMANDS
// ============================================================================

/// Command category
pub const CommandCategory = enum(u8) {
    file = 1,
    edit = 2,
    view = 3,
    search = 4,
    run = 5,
    debug = 6,
    build = 7,
    test_cat = 8,
    refactor = 9,
    tools = 10,
    other = 255,
};

/// Command definition
pub const CommandDef = extern struct {
    id: [32]u8 = [_]u8{0} ** 32,
    id_len: u8 = 0,
    title: [64]u8 = [_]u8{0} ** 64,
    title_len: u8 = 0,
    description: [128]u8 = [_]u8{0} ** 128,
    description_len: u8 = 0,
    category: u8 = 255, // CommandCategory
    shortcut: [16]u8 = [_]u8{0} ** 16, // "Ctrl+Shift+R"
    shortcut_len: u8 = 0,
    requires_file: bool = false,
    requires_selection: bool = false,
    _pad: u8 = 0,
};

/// Command result
pub const CommandResult = extern struct {
    success: bool = false,
    _pad1: [3]u8 = [_]u8{0} ** 3,
    exit_code: i32 = 0,
    output: [4096]u8 = [_]u8{0} ** 4096,
    output_len: u16 = 0,
    error_msg: [256]u8 = [_]u8{0} ** 256,
    error_msg_len: u16 = 0,
    open_file: [256]u8 = [_]u8{0} ** 256,
    open_file_len: u16 = 0,
    goto_line: u32 = 0,
    goto_col: u16 = 0,
    _pad2: [2]u8 = [_]u8{0} ** 2,
};

// ============================================================================
// SNIPPETS
// ============================================================================

pub const Snippet = extern struct {
    prefix: [16]u8 = [_]u8{0} ** 16,
    prefix_len: u8 = 0,
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: u8 = 0,
    description: [128]u8 = [_]u8{0} ** 128,
    description_len: u8 = 0,
    body: [1024]u8 = [_]u8{0} ** 1024, // With placeholders: ${1:name}, $0
    body_len: u16 = 0,
    _pad: u8 = 0,
};

// ============================================================================
// DEFAULT COLORS (VS Code Dark+ inspired)
// ============================================================================

pub const DefaultColors = struct {
    // Basic
    pub const text: u32 = 0xFFe8e8e8;
    pub const whitespace: u32 = 0xFF404040;

    // Comments
    pub const comment: u32 = 0xFF6a9955;
    pub const comment_doc: u32 = 0xFF608b4e;

    // Strings
    pub const string: u32 = 0xFFce9178;
    pub const string_escape: u32 = 0xFFd7ba7d;
    pub const string_regex: u32 = 0xFFd16969;

    // Numbers
    pub const number: u32 = 0xFFb5cea8;

    // Keywords
    pub const keyword: u32 = 0xFFc586c0;
    pub const keyword_control: u32 = 0xFFc586c0;
    pub const keyword_operator: u32 = 0xFFc586c0;
    pub const keyword_declaration: u32 = 0xFF569cd6;

    // Identifiers
    pub const variable: u32 = 0xFF9cdcfe;
    pub const variable_readonly: u32 = 0xFF4fc1ff;
    pub const constant: u32 = 0xFF4fc1ff;
    pub const function: u32 = 0xFFdcdcaa;
    pub const function_builtin: u32 = 0xFFdcdcaa;
    pub const method: u32 = 0xFFdcdcaa;
    pub const class: u32 = 0xFF4ec9b0;
    pub const type_name: u32 = 0xFF4ec9b0;
    pub const enum_name: u32 = 0xFF4ec9b0;
    pub const enum_member: u32 = 0xFF4fc1ff;
    pub const namespace: u32 = 0xFF4ec9b0;
    pub const property: u32 = 0xFF9cdcfe;
    pub const field: u32 = 0xFF9cdcfe;
    pub const parameter: u32 = 0xFF9cdcfe;

    // Built-ins
    pub const builtin: u32 = 0xFF4fc1ff;

    // Operators
    pub const operator: u32 = 0xFFd4d4d4;
    pub const punctuation: u32 = 0xFFd4d4d4;

    // Special
    pub const decorator: u32 = 0xFFdcdcaa;
    pub const macro: u32 = 0xFF569cd6;
    pub const preprocessor: u32 = 0xFF9b9b9b;
    pub const tag: u32 = 0xFF569cd6;
    pub const tag_attribute: u32 = 0xFF9cdcfe;

    // Errors
    pub const error_tok: u32 = 0xFFf44747;
    pub const warning_tok: u32 = 0xFFcca700;
    pub const info_tok: u32 = 0xFF3794ff;
    pub const hint_tok: u32 = 0xFF6a9955;
};

/// Map simple plugin token values (0-10) to full TokenType
/// Used for backward compatibility with simple plugins like Python
/// Plugin values:
///   0 = normal/text
///   1 = keyword
///   2 = type_name
///   3 = builtin
///   4 = string
///   5 = number
///   6 = comment
///   7 = function
///   8 = operator
///   9 = punctuation
///   10 = field
pub fn mapSimpleToken(kind: u8) TokenType {
    return switch (kind) {
        0 => .text,
        1 => .keyword,
        2 => .type_name,
        3 => .builtin,
        4 => .string,
        5 => .number,
        6 => .comment,
        7 => .function,
        8 => .operator,
        9 => .punctuation,
        10 => .field,
        else => .text,
    };
}

/// Get default color for token type
pub fn getDefaultTokenColor(token_type: TokenType) u32 {
    return switch (token_type) {
        .text => DefaultColors.text,
        .whitespace => DefaultColors.whitespace,
        .comment, .comment_line, .comment_block => DefaultColors.comment,
        .comment_doc => DefaultColors.comment_doc,
        .string, .string_single, .string_double, .string_template => DefaultColors.string,
        .string_escape, .string_interpolation => DefaultColors.string_escape,
        .string_regex => DefaultColors.string_regex,
        .number, .number_integer, .number_float, .number_hex, .number_binary, .number_octal => DefaultColors.number,
        .keyword, .keyword_other => DefaultColors.keyword,
        .keyword_control => DefaultColors.keyword_control,
        .keyword_operator => DefaultColors.keyword_operator,
        .keyword_declaration, .keyword_modifier, .keyword_type => DefaultColors.keyword_declaration,
        .identifier, .variable => DefaultColors.variable,
        .variable_parameter => DefaultColors.parameter,
        .variable_readonly, .constant => DefaultColors.constant,
        .function, .method => DefaultColors.function,
        .function_builtin => DefaultColors.function_builtin,
        .class, .struct_name, .interface => DefaultColors.class,
        .type_name, .type_parameter => DefaultColors.type_name,
        .enum_name => DefaultColors.enum_name,
        .enum_member => DefaultColors.enum_member,
        .namespace, .module => DefaultColors.namespace,
        .property, .field => DefaultColors.field,
        .label => DefaultColors.variable,
        .builtin, .builtin_function, .builtin_type, .builtin_constant => DefaultColors.builtin,
        .operator, .operator_arithmetic, .operator_comparison, .operator_logical, .operator_bitwise, .operator_assignment => DefaultColors.operator,
        .punctuation, .punctuation_bracket, .punctuation_delimiter, .punctuation_accessor => DefaultColors.punctuation,
        .decorator, .attribute, .annotation => DefaultColors.decorator,
        .macro => DefaultColors.macro,
        .preprocessor => DefaultColors.preprocessor,
        .tag => DefaultColors.tag,
        .tag_attribute => DefaultColors.tag_attribute,
        .error_token => DefaultColors.error_tok,
        .warning_token => DefaultColors.warning_tok,
        .info_token => DefaultColors.info_tok,
        .hint_token => DefaultColors.hint_tok,
        .invalid => DefaultColors.error_tok,
    };
}

// ============================================================================
// WASM MEMORY LAYOUT
// ============================================================================

pub const WasmMemory = struct {
    pub const INPUT_BUFFER: u32 = 0x10000; // 64KB offset for input
    pub const INPUT_MAX: u32 = 0x10000; // 64KB max input
    pub const OUTPUT_BUFFER: u32 = 0x20000; // 128KB offset for output
    pub const OUTPUT_MAX: u32 = 0x20000; // 128KB max output
    pub const SCRATCH_BUFFER: u32 = 0x40000; // 256KB offset for scratch
    pub const SCRATCH_MAX: u32 = 0x10000; // 64KB max scratch
};

// ============================================================================
// HOST API (functions host provides to plugins)
// ============================================================================

// Buffer API
pub export fn host_get_buffer_len() u32 {
    return 0; // TODO
}

pub export fn host_get_buffer(dst_ptr: [*]u8, dst_len: u32) u32 {
    _ = dst_ptr;
    _ = dst_len;
    return 0; // TODO
}

pub export fn host_get_line(line_num: u32, dst_ptr: [*]u8, dst_len: u32) i32 {
    _ = line_num;
    _ = dst_ptr;
    _ = dst_len;
    return -1; // TODO
}

pub export fn host_get_line_count() u32 {
    return 1; // TODO
}

pub export fn host_get_cursor() u32 {
    return 0; // TODO
}

pub export fn host_get_cursor_pos(out_line: *u32, out_col: *u32) void {
    out_line.* = 0;
    out_col.* = 0;
}

pub export fn host_get_selection(start_line: *u32, start_col: *u32, end_line: *u32, end_col: *u32) bool {
    start_line.* = 0;
    start_col.* = 0;
    end_line.* = 0;
    end_col.* = 0;
    return false; // TODO
}

// Edit API
pub export fn host_insert_text(src_ptr: [*]const u8, src_len: u32) void {
    _ = src_ptr;
    _ = src_len;
}

pub export fn host_delete_range(start: u32, end: u32) void {
    _ = start;
    _ = end;
}

pub export fn host_replace_range(start: u32, end: u32, text_ptr: [*]const u8, text_len: u32) void {
    _ = start;
    _ = end;
    _ = text_ptr;
    _ = text_len;
}

pub export fn host_set_cursor(pos: u32) void {
    _ = pos;
}

pub export fn host_set_cursor_pos(line: u32, col: u32) void {
    _ = line;
    _ = col;
}

pub export fn host_set_selection(start_line: u32, start_col: u32, end_line: u32, end_col: u32) void {
    _ = start_line;
    _ = start_col;
    _ = end_line;
    _ = end_col;
}

// File API
pub export fn host_get_file_path(dst_ptr: [*]u8, dst_len: u32) u32 {
    _ = dst_ptr;
    _ = dst_len;
    return 0;
}

pub export fn host_get_file_extension(dst_ptr: [*]u8, dst_len: u32) u32 {
    _ = dst_ptr;
    _ = dst_len;
    return 0;
}

pub export fn host_save_file() bool {
    return false;
}

pub export fn host_open_file(path_ptr: [*]const u8, path_len: u32) bool {
    _ = path_ptr;
    _ = path_len;
    return false;
}

// UI API
pub export fn host_show_message(msg_ptr: [*]const u8, msg_len: u32, severity: u8) void {
    _ = msg_ptr;
    _ = msg_len;
    _ = severity;
}

pub export fn host_write_output(text_ptr: [*]const u8, text_len: u32) void {
    _ = text_ptr;
    _ = text_len;
}

pub export fn host_clear_output() void {}

pub export fn host_show_quickpick(items_ptr: [*]const u8, items_len: u32, callback_id: u32) void {
    _ = items_ptr;
    _ = items_len;
    _ = callback_id;
}

pub export fn host_show_input(prompt_ptr: [*]const u8, prompt_len: u32, callback_id: u32) void {
    _ = prompt_ptr;
    _ = prompt_len;
    _ = callback_id;
}

// Diagnostics API
pub export fn host_add_diagnostic(diag_ptr: [*]const u8) void {
    _ = diag_ptr;
}

pub export fn host_clear_diagnostics() void {}

pub export fn host_clear_diagnostics_for_file(path_ptr: [*]const u8, path_len: u32) void {
    _ = path_ptr;
    _ = path_len;
}

// Execution API
pub export fn host_execute_command(cmd_ptr: [*]const u8, cmd_len: u32, result_ptr: [*]u8) i32 {
    _ = cmd_ptr;
    _ = cmd_len;
    _ = result_ptr;
    return -1;
}

pub export fn host_spawn_process(cmd_ptr: [*]const u8, cmd_len: u32, args_ptr: [*]const u8, args_len: u32) i32 {
    _ = cmd_ptr;
    _ = cmd_len;
    _ = args_ptr;
    _ = args_len;
    return -1;
}

pub export fn host_kill_process(pid: i32) void {
    _ = pid;
}

pub export fn host_is_process_running(pid: i32) bool {
    _ = pid;
    return false;
}

// LSP API
pub export fn host_lsp_start(cmd_ptr: [*]const u8, cmd_len: u32, args_ptr: [*]const u8, args_len: u32) i32 {
    _ = cmd_ptr;
    _ = cmd_len;
    _ = args_ptr;
    _ = args_len;
    return -1;
}

pub export fn host_lsp_send(conn_id: i32, msg_ptr: [*]const u8, msg_len: u32) void {
    _ = conn_id;
    _ = msg_ptr;
    _ = msg_len;
}

pub export fn host_lsp_stop(conn_id: i32) void {
    _ = conn_id;
}

// Logging API
pub export fn host_log_debug(msg_ptr: [*]const u8, msg_len: u32) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[Plugin Debug] {s}\n", .{msg});
}

pub export fn host_log_info(msg_ptr: [*]const u8, msg_len: u32) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[Plugin Info] {s}\n", .{msg});
}

pub export fn host_log_error(msg_ptr: [*]const u8, msg_len: u32) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[Plugin Error] {s}\n", .{msg});
}

// Completions API
pub export fn host_add_completion(item_ptr: [*]const u8) void {
    _ = item_ptr;
}

pub export fn host_clear_completions() void {}

// Hover API
pub export fn host_show_hover(info_ptr: [*]const u8) void {
    _ = info_ptr;
}

// Goto API
pub export fn host_goto_definition(loc_ptr: [*]const u8) void {
    _ = loc_ptr;
}

pub export fn host_show_references(locs_ptr: [*]const u8, count: u32) void {
    _ = locs_ptr;
    _ = count;
}

// Registration API
pub export fn host_register_command(cmd_ptr: [*]const u8) i32 {
    _ = cmd_ptr;
    return -1;
}

pub export fn host_register_keybinding(key_ptr: [*]const u8, key_len: u32, cmd_id: i32) bool {
    _ = key_ptr;
    _ = key_len;
    _ = cmd_id;
    return false;
}
