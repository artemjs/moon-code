const std = @import("std");
const builtin = @import("builtin");

// Platform abstraction
const platform = if (builtin.os.tag == .windows)
    @import("render/windows.zig")
else
    @import("render/wayland.zig");

const Platform = if (builtin.os.tag == .windows)
    platform.Windows
else
    platform.Wayland;

// Aliases for compatibility
const Wayland = Platform;
const wl = platform;
const GpuRenderer = @import("render/gpu.zig").GpuRenderer;
const GapBuffer = @import("editor/buffer.zig").GapBuffer;
const widgets = @import("ui/widgets.zig");
const icons = @import("render/icons.zig");
const c = @import("c.zig").c;
const text_input = @import("input/text_input.zig");
const plugins = @import("plugins/loader.zig");
const plugin_api = @import("plugins/api.zig");
const shell = @import("terminal/shell.zig");
const lsp = @import("lsp/client.zig");
const LazyLoader = @import("editor/lazy_loader.zig").LazyLoader;

// New modular components
const logger = @import("core/logger.zig");
const errors = @import("core/errors.zig");
const UIState = @import("ui/state.zig").UIState;
const SearchState = @import("ui/state.zig").SearchState;
const TabManager = @import("editor/tab_manager.zig").TabManager;
const BufferCache = @import("editor/cache.zig").BufferCache;

// Embedded fonts (compiled into binary)
const EMBEDDED_FONT = @embedFile("assets/fonts/DejaVuSansMono.ttf");
const EMBEDDED_UI_FONT = @embedFile("assets/fonts/Ubuntu-Light.ttf");
const FONT_SIZE: f32 = 20.0;
const UI_FONT_SIZE: f32 = 16.0;

// Color scheme: dark with pastel peach accent
const COLOR_BG: u32 = 0xFF1a1a1a; // Main background
const COLOR_SURFACE: u32 = 0xFF242424; // Surface (titlebar, gutter)
const COLOR_TEXT: u32 = 0xFFe8e8e8; // Main text
const COLOR_TEXT_DIM: u32 = 0xFF707070; // Dimmed text (line numbers)
const COLOR_ACCENT: u32 = 0xFFffb4a2; // Pastel peach - accent
const COLOR_ACCENT_DIM: u32 = 0xFF8b6b5d; // Dimmed peach
const COLOR_CURSOR: u32 = 0xFFffb4a2; // Cursor = accent
const COLOR_SELECTION: u32 = 0xFF3d3530; // Selection (warm tint)
const COLOR_GUTTER: u32 = 0xFF1f1f1f; // Line numbers area
const COLOR_BTN_HOVER: u32 = 0xFF3a3a3a; // Button hover

// Syntax Highlighting Colors (VS Code Dark+ inspired)
const SYN_KEYWORD: u32 = 0xFFc586c0; // Purple - keywords (fn, const, var, if, etc.)
const SYN_TYPE: u32 = 0xFF4ec9b0; // Teal - types (u32, bool, etc.)
const SYN_BUILTIN: u32 = 0xFF4fc1ff; // Light blue - @import, @intCast, etc.
const SYN_STRING: u32 = 0xFFce9178; // Orange - strings
const SYN_NUMBER: u32 = 0xFFb5cea8; // Light green - numbers
const SYN_COMMENT: u32 = 0xFF6a9955; // Green - comments
const SYN_FUNCTION: u32 = 0xFFdcdcaa; // Yellow - function names
const SYN_OPERATOR: u32 = 0xFFd4d4d4; // Light gray - operators
const SYN_PUNCTUATION: u32 = 0xFFd4d4d4; // Punctuation
const SYN_FIELD: u32 = 0xFF9cdcfe; // Light blue - struct fields

// File Icons (using Unicode symbols)
const ICON_FOLDER: []const u8 = "📁";
const ICON_FOLDER_OPEN: []const u8 = "📂";
const ICON_FILE: []const u8 = "📄";
const ICON_ZIG: []const u8 = "⚡"; // Lightning bolt for Zig

// Window controls - unified block
const COLOR_BTN_CLOSE: u32 = 0xFFff6b6b; // Red for close
const COLOR_BTN_MAXIMIZE: u32 = 0xFF6bff6b; // Green for maximize
const COLOR_BTN_MINIMIZE: u32 = 0xFFffdb6b; // Yellow for minimize

// Layout constants (default values at 100% zoom)
const TITLEBAR_HEIGHT: u32 = 38;
const TAB_BAR_HEIGHT: u32 = 44;
const SIDEBAR_WIDTH: u32 = 200;
const CORNER_RADIUS: u32 = 8;
const BTN_RADIUS: u32 = 6;
const GUTTER_WIDTH: u32 = 48;
const EDITOR_MARGIN: u32 = 14;
const EDITOR_PADDING: u32 = 16;
const ICON_SIZE: u32 = 20;

// UI Zoom helpers
fn scaleUI(base: u32, zoom: f32) u32 {
    return @max(1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(base)) * zoom)));
}

fn scaleI(base: i32, zoom: f32) i32 {
    return @intFromFloat(@as(f32, @floatFromInt(base)) * zoom);
}

fn scaleF(base: f32, zoom: f32) f32 {
    return base * zoom;
}

// Project info
const PROJECT_NAME = "Moon Code";
const PROJECT_VERSION = "0.1.0";

// Global cache for fast rendering
var g_cached_line: usize = 0;
var g_cached_offset: usize = 0;
var g_cached_buf_len: usize = 0;
var g_cached_line_count: usize = 1;
var g_cached_max_line_len: usize = 0;

// Cursor position cache (line, col)
var g_cursor_cache_pos: usize = 0; // Cursor position for which cache is valid
var g_cursor_cache_line: usize = 0;
var g_cursor_cache_col: usize = 0;
var g_cursor_cache_valid: bool = false;

// Line index for O(1) access to line offset
const MAX_LINE_INDEX = 100000; // Support up to 100k lines
var g_line_index: [MAX_LINE_INDEX]usize = [_]usize{0} ** MAX_LINE_INDEX;
var g_line_index_count: usize = 0;
var g_line_index_valid: bool = false;
var g_line_index_buf_len: usize = 0;

// Lazy file loader
var g_lazy_loader: LazyLoader = LazyLoader.init();

// === Dirty Region Tracking ===
// Change type for redraw optimization
const DirtyType = enum {
    none, // Nothing changed
    cursor_only, // Only cursor moved
    line_range, // Line range changed
    full, // Full redraw needed
};
var g_dirty_type: DirtyType = .full;
var g_dirty_line_start: usize = 0;
var g_dirty_line_end: usize = 0;
var g_prev_scroll_y: i32 = 0;
var g_prev_cursor_line: usize = 0;
var g_prev_selection_start: ?usize = null;
var g_prev_selection_end: ?usize = null;

// Last frame time for delta time
var g_last_frame_time: i64 = 0;

// === Per-line token cache ===
const MAX_CACHED_LINES = 10000;
const MAX_TOKENS_PER_LINE = 128;

const CachedLineTokens = struct {
    tokens: [MAX_TOKENS_PER_LINE]Token = undefined,
    plugin_tokens: [MAX_TOKENS_PER_LINE]plugins.WasmToken = undefined,
    count: u16 = 0,
    is_plugin: bool = false,
    line_hash: u32 = 0, // Line content hash for invalidation
    in_multiline_comment: bool = false, // State at line start
};

var g_token_cache: [MAX_CACHED_LINES]CachedLineTokens = [_]CachedLineTokens{.{}} ** MAX_CACHED_LINES;
var g_token_cache_valid: bool = false;
var g_token_cache_file_hash: u64 = 0; // For invalidation when file changes

fn simpleHash(data: []const u8) u32 {
    var hash: u32 = 5381;
    for (data) |byte| {
        hash = ((hash << 5) +% hash) +% byte;
    }
    return hash;
}

/// Update cursor position cache (line, col)
/// Recalculates only if cursor changed
fn updateCursorCache(text_buffer: *GapBuffer) void {
    const cursor = text_buffer.cursor();

    // If cache is valid and position is the same - do nothing
    if (g_cursor_cache_valid and g_cursor_cache_pos == cursor) {
        return;
    }

    // Recalculate
    const pos = text_buffer.cursorPosition();
    g_cursor_cache_pos = cursor;
    g_cursor_cache_line = pos.line;
    g_cursor_cache_col = pos.col;
    g_cursor_cache_valid = true;
}

fn invalidateCursorCache() void {
    g_cursor_cache_valid = false;
}

/// Sync line index count from buffer (O(1) - just reads count)
fn buildLineIndex(text_buffer: *GapBuffer) void {
    g_line_index_count = text_buffer.lineCount();
    g_line_index_buf_len = text_buffer.len();
    g_line_index_valid = true;
}

/// Get line offset in O(1) using buffer's fast lookup
fn getLineOffset(line: usize) usize {
    // This function is called from rendering, we need a reference to text_buffer
    // For now return from global index if valid
    if (g_line_index_valid and line < g_line_index_count) {
        return g_line_index[line];
    }
    return 0;
}

/// Get line offset directly from buffer (preferred)
fn getLineOffsetFromBuffer(text_buffer: *const GapBuffer, line: usize) usize {
    return text_buffer.getLineOffsetFast(line);
}

fn invalidateLineIndex() void {
    g_line_index_valid = false;
}

// === Dirty Region Functions ===
fn markFullRedraw() void {
    g_dirty_type = .full;
}

fn markCursorDirty() void {
    if (g_dirty_type == .none) {
        g_dirty_type = .cursor_only;
    }
}

fn markLinesDirty(start: usize, end: usize) void {
    if (g_dirty_type == .full) return;

    if (g_dirty_type == .none or g_dirty_type == .cursor_only) {
        g_dirty_type = .line_range;
        g_dirty_line_start = start;
        g_dirty_line_end = end;
    } else {
        // Extend existing range
        g_dirty_line_start = @min(g_dirty_line_start, start);
        g_dirty_line_end = @max(g_dirty_line_end, end);
    }
}

fn clearDirty() void {
    g_dirty_type = .none;
}

fn shouldRenderLine(line: usize, first_visible: usize, last_visible: usize) bool {
    // Always render if full redraw
    if (g_dirty_type == .full) return true;

    // Not in visible area - don't render
    if (line < first_visible or line > last_visible) return false;

    // For cursor_only - render only cursor line and previous
    if (g_dirty_type == .cursor_only) {
        return line == g_cursor_cache_line or line == g_prev_cursor_line;
    }

    // For line_range - render only dirty lines
    if (g_dirty_type == .line_range) {
        return line >= g_dirty_line_start and line <= g_dirty_line_end;
    }

    return true;
}

fn invalidateTokenCache() void {
    g_token_cache_valid = false;
    for (&g_token_cache) |*entry| {
        entry.count = 0;
        entry.line_hash = 0;
    }
}

fn invalidateTokenCacheFromLine(line: usize) void {
    // Invalidate from specified line onwards (due to multiline comments)
    var i = line;
    while (i < MAX_CACHED_LINES) : (i += 1) {
        g_token_cache[i].count = 0;
        g_token_cache[i].line_hash = 0;
    }
}

// Global settings (saved in ~/.mncode)
var g_scroll_inertia: bool = false;
var g_scroll_speed: f32 = 1.0; // Scroll speed 0.1x - 10x

// Slider Widget for settings
const Slider = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 200,
    height: i32 = 20,
    handle_width: i32 = 16,
    min_value: f32 = 0.0,
    max_value: f32 = 1.0,
    value: f32 = 0.5,
    is_dragging: bool = false,
    is_hovered: bool = false,
    is_percent: bool = true, // true = 0-100%, false = numeric

    const Self = @This();

    pub fn init(min: f32, max: f32, initial: f32, is_percent: bool) Self {
        return .{
            .min_value = min,
            .max_value = max,
            .value = @max(min, @min(max, initial)),
            .is_percent = is_percent,
        };
    }

    pub fn setPosition(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        self.x = x;
        self.y = y;
        self.width = width;
        self.height = height;
        self.handle_width = @max(12, @divTrunc(height, 2) + 4);
    }

    pub fn getHandleX(self: *const Self) i32 {
        const track_width = self.width - self.handle_width;
        const normalized = (self.value - self.min_value) / (self.max_value - self.min_value);
        return self.x + @as(i32, @intFromFloat(normalized * @as(f32, @floatFromInt(track_width))));
    }

    pub fn update(self: *Self, mouse_x: i32, mouse_y: i32, mouse_pressed: bool) bool {
        const handle_x = self.getHandleX();
        const in_handle = mouse_x >= handle_x and mouse_x < handle_x + self.handle_width and
            mouse_y >= self.y and mouse_y < self.y + self.height;
        const in_track = mouse_x >= self.x and mouse_x < self.x + self.width and
            mouse_y >= self.y and mouse_y < self.y + self.height;

        self.is_hovered = in_handle or (in_track and self.is_dragging);

        if (mouse_pressed and (in_track or self.is_dragging)) {
            self.is_dragging = true;
            // Calculate new value
            const track_width = self.width - self.handle_width;
            const relative_x = @as(f32, @floatFromInt(@max(0, @min(track_width, mouse_x - self.x - @divTrunc(self.handle_width, 2)))));
            const normalized = relative_x / @as(f32, @floatFromInt(@max(1, track_width)));
            self.value = self.min_value + normalized * (self.max_value - self.min_value);
            self.value = @max(self.min_value, @min(self.max_value, self.value));
            return true; // Value changed
        } else {
            self.is_dragging = false;
        }
        return false;
    }

    pub fn render(self: *const Self, gpu: *GpuRenderer, label: []const u8) void {
        const handle_x = self.getHandleX();

        // Track background (dark)
        gpu.drawRoundedRect(self.x, self.y + 6, @intCast(self.width), @intCast(self.height - 12), 4, 0xFF2a2a2a);

        // Filled part (accent)
        const filled_width: u32 = @intCast(@max(0, handle_x - self.x + @divTrunc(self.handle_width, 2)));
        if (filled_width > 4) {
            gpu.drawRoundedRect(self.x, self.y + 6, filled_width, @intCast(self.height - 12), 4, COLOR_ACCENT_DIM);
        }

        // Slider handle
        const handle_color: u32 = if (self.is_dragging) COLOR_ACCENT else if (self.is_hovered) 0xFFdddddd else 0xFFaaaaaa;
        gpu.drawRoundedRect(handle_x, self.y, @intCast(self.handle_width), @intCast(self.height), 4, handle_color);

        // Label on the left
        gpu.drawUIText(label, self.x - 100, self.y + 2, COLOR_TEXT);

        // Value on the right
        var value_buf: [16]u8 = undefined;
        const value_str = if (self.is_percent)
            std.fmt.bufPrint(&value_buf, "{d:.0}%", .{self.value * 100}) catch "?"
        else
            std.fmt.bufPrint(&value_buf, "{d:.1}x", .{self.value}) catch "?";
        gpu.drawUIText(value_str, self.x + self.width + 10, self.y + 2, COLOR_TEXT);
    }
};

// Global sliders for settings
var g_scroll_speed_slider: Slider = Slider.init(0.1, 10.0, 1.0, false);
var g_line_visibility_slider: Slider = Slider.init(0.0, 1.0, 0.0, true); // 0 = no lines, 1 = full lines
var g_line_visibility: f32 = 0.0; // Line separator visibility (0-1)

// Tab Bar Height (resizable)
var g_tab_bar_height: i32 = 40; // Minimum 30, maximum 80

// Bottom Panel State (global for render access)
var g_bottom_panel_visible: bool = false;
var g_bottom_panel_height: i32 = 150;
var g_bottom_panel_tab: u8 = 0; // 0 = Output, 1 = Problems, 2 = Terminal
var g_terminal_input_buf: [256]u8 = [_]u8{0} ** 256;
var g_terminal_field: text_input.TextFieldBuffer = text_input.TextFieldBuffer.init(&g_terminal_input_buf);
var g_terminal_focused: bool = false;
var g_terminal_key_repeat: text_input.KeyRepeatState = .{};
var g_terminal_scroll_y: i32 = 0; // Scroll position for terminal
var g_terminal_max_scroll: i32 = 0; // Max scroll value
var g_run_btn_hovered: bool = false;
var g_panel_btn_hovered: bool = false;
var g_output_lines: [256][256]u8 = undefined;
var g_output_line_lens: [256]usize = [_]usize{0} ** 256;
var g_output_line_types: [256]u8 = [_]u8{0} ** 256; // 0=normal, 1=warning, 2=error
var g_output_line_colors: [256]u32 = [_]u32{0xFFe8e8e8} ** 256; // ANSI parsed colors
var g_output_line_count: usize = 0;
var g_run_exit_code: u32 = 0;
var g_close_btn_hovered: bool = false; // For close button highlight
var g_terminal_running: bool = false; // Process is running

// Plugin management buttons state
var g_plugin_disable_btn_hovered: bool = false;
var g_plugin_uninstall_btn_hovered: bool = false;
var g_disabled_plugin_hovered: i32 = -1;
var g_plugin_disable_btn_rect: struct { x: i32, y: i32, w: i32, h: i32 } = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
var g_plugin_uninstall_btn_rect: struct { x: i32, y: i32, w: i32, h: i32 } = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

// Confirm dialog for plugin actions
var g_confirm_dialog: widgets.ConfirmDialog = .{};
const PluginAction = enum { none, disable, enable, uninstall };
var g_pending_plugin_action: PluginAction = .none;
var g_pending_plugin_path: [512]u8 = [_]u8{0} ** 512;
var g_pending_plugin_path_len: usize = 0;
var g_pending_plugin_tab: usize = 0;

// File manager state
var g_fm_add_file_btn_hovered: bool = false;
var g_fm_add_folder_btn_hovered: bool = false;
var g_fm_delete_btn_hovered: bool = false;
var g_pending_delete_idx: usize = 0;
var g_pending_delete_action: bool = false;
var g_new_file_counter: u32 = 1;
var g_new_folder_counter: u32 = 1;

// Double-click and rename state
var g_last_click_time: i64 = 0;
var g_last_click_idx: i32 = -1;
var g_rename_mode: bool = false;
var g_rename_idx: usize = 0;
var g_rename_buf: [256]u8 = [_]u8{0} ** 256;
var g_rename_field: text_input.TextFieldBuffer = text_input.TextFieldBuffer.init(&g_rename_buf);

// Global search state
var g_search_query: [256]u8 = [_]u8{0} ** 256;
var g_search_field: text_input.TextFieldBuffer = text_input.TextFieldBuffer.init(&g_search_query);
var g_search_active: bool = false; // Is search input focused
var g_search_results: [512]SearchResult = undefined;
var g_search_result_count: usize = 0;
var g_search_result_hovered: i32 = -1;
var g_search_result_scroll: i32 = 0;

const SearchResult = struct {
    file_path: [512]u8,
    file_path_len: usize,
    line_num: u32,
    line_content: [256]u8,
    line_content_len: usize,
    match_start: usize,
    match_len: usize,
};

// Global folder state (needed for search)
var g_current_folder: [1024]u8 = [_]u8{0} ** 1024;
var g_current_folder_len: usize = 0;

// LSP state
var g_lsp_conn_id: i32 = -1; // Current LSP connection ID (-1 = not connected)
var g_lsp_file_version: i32 = 1; // Document version for LSP
var g_lsp_completion_visible: bool = false;
var g_lsp_completion_selected: i32 = 0;
var g_lsp_completion_x: i32 = 0; // Position for completion popup
var g_lsp_completion_y: i32 = 0;
var g_lsp_hover_visible: bool = false;
var g_lsp_hover_x: i32 = 0;
var g_lsp_hover_y: i32 = 0;
var g_lsp_diagnostics_visible: bool = true; // Show diagnostics underlines
var g_folder_files: [256][256]u8 = undefined;
var g_folder_names: [256][64]u8 = undefined;
var g_folder_file_lens: [256]usize = undefined;
var g_folder_name_lens: [256]usize = undefined;
var g_folder_is_dir: [256]bool = undefined;
var g_folder_indent: [256]u8 = undefined;
var g_folder_expanded: [256]bool = undefined;
var g_folder_file_count: usize = 0;

/// Detect output line type (error/warning/normal)
fn detectOutputLineType(line: []const u8) u8 {
    // Look for error patterns
    const lower = blk: {
        var buf: [256]u8 = undefined;
        const len = @min(line.len, 255);
        for (line[0..len], 0..) |ch, i| {
            buf[i] = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
        }
        break :blk buf[0..len];
    };

    // Error patterns
    if (std.mem.indexOf(u8, lower, "error") != null) return 2;
    if (std.mem.indexOf(u8, lower, "traceback") != null) return 2;
    if (std.mem.indexOf(u8, lower, "exception") != null) return 2;
    if (std.mem.indexOf(u8, lower, "failed") != null) return 2;
    if (std.mem.indexOf(u8, lower, "fatal") != null) return 2;
    if (std.mem.startsWith(u8, lower, "  file \"")) return 2; // Python traceback

    // Warning patterns
    if (std.mem.indexOf(u8, lower, "warning") != null) return 1;
    if (std.mem.indexOf(u8, lower, "deprecated") != null) return 1;

    return 0; // normal
}

/// Search a single file for query matches
fn searchFileForQuery(file_path: []const u8, query: []const u8) void {
    const file = std.fs.openFileAbsolute(file_path, .{}) catch return;
    defer file.close();

    // Read file content (limit to 256KB)
    var buf: [256 * 1024]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return;
    if (bytes_read == 0) return;

    const content = buf[0..bytes_read];
    var line_num: u32 = 1;
    var line_start: usize = 0;

    for (content, 0..) |ch, pos| {
        if (ch == '\n' or pos == bytes_read - 1) {
            const line_end = if (ch == '\n') pos else pos + 1;
            const line = content[line_start..line_end];

            // Search for query in line (case-insensitive)
            var i: usize = 0;
            while (i + query.len <= line.len) {
                var match = true;
                for (0..query.len) |qi| {
                    const lc = if (line[i + qi] >= 'A' and line[i + qi] <= 'Z') line[i + qi] + 32 else line[i + qi];
                    const qc = if (query[qi] >= 'A' and query[qi] <= 'Z') query[qi] + 32 else query[qi];
                    if (lc != qc) {
                        match = false;
                        break;
                    }
                }
                if (match) {
                    // Found match, add to results
                    if (g_search_result_count < g_search_results.len) {
                        var result = &g_search_results[g_search_result_count];
                        const path_len = @min(file_path.len, result.file_path.len);
                        @memcpy(result.file_path[0..path_len], file_path[0..path_len]);
                        result.file_path_len = path_len;
                        result.line_num = line_num;
                        const content_len = @min(line.len, result.line_content.len);
                        @memcpy(result.line_content[0..content_len], line[0..content_len]);
                        result.line_content_len = content_len;
                        result.match_start = i;
                        result.match_len = query.len;
                        g_search_result_count += 1;
                    }
                    break; // One match per line
                }
                i += 1;
            }

            line_num += 1;
            line_start = pos + 1;
            if (g_search_result_count >= g_search_results.len) return;
        }
    }
}

/// Recursively search directory for query
fn searchDirectoryRecursive(dir_path: []const u8, query: []const u8, depth: u32) void {
    if (depth > 10 or g_search_result_count >= g_search_results.len) return;

    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (g_search_result_count >= g_search_results.len) break;

        // Skip hidden files/dirs
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        // Skip common non-text directories
        if (std.mem.eql(u8, entry.name, "node_modules")) continue;
        if (std.mem.eql(u8, entry.name, "zig-cache")) continue;
        if (std.mem.eql(u8, entry.name, ".zig-cache")) continue;
        if (std.mem.eql(u8, entry.name, "target")) continue;
        if (std.mem.eql(u8, entry.name, ".git")) continue;

        var full_path: [1024]u8 = undefined;
        const path = std.fmt.bufPrint(&full_path, "{s}/{s}", .{ dir_path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            searchDirectoryRecursive(path, query, depth + 1);
        } else if (entry.kind == .file) {
            // Only search text files
            const is_text = std.mem.endsWith(u8, entry.name, ".zig") or
                std.mem.endsWith(u8, entry.name, ".py") or
                std.mem.endsWith(u8, entry.name, ".js") or
                std.mem.endsWith(u8, entry.name, ".ts") or
                std.mem.endsWith(u8, entry.name, ".c") or
                std.mem.endsWith(u8, entry.name, ".h") or
                std.mem.endsWith(u8, entry.name, ".cpp") or
                std.mem.endsWith(u8, entry.name, ".hpp") or
                std.mem.endsWith(u8, entry.name, ".rs") or
                std.mem.endsWith(u8, entry.name, ".go") or
                std.mem.endsWith(u8, entry.name, ".java") or
                std.mem.endsWith(u8, entry.name, ".json") or
                std.mem.endsWith(u8, entry.name, ".md") or
                std.mem.endsWith(u8, entry.name, ".txt") or
                std.mem.endsWith(u8, entry.name, ".toml") or
                std.mem.endsWith(u8, entry.name, ".yaml") or
                std.mem.endsWith(u8, entry.name, ".yml") or
                std.mem.endsWith(u8, entry.name, ".xml") or
                std.mem.endsWith(u8, entry.name, ".html") or
                std.mem.endsWith(u8, entry.name, ".css");
            if (is_text) {
                searchFileForQuery(path, query);
            }
        }
    }
}

/// Perform global search across all files in folder
fn performGlobalSearch(query: []const u8) void {
    g_search_result_count = 0;
    g_search_result_scroll = 0;

    if (query.len == 0 or g_current_folder_len == 0) return;

    const folder_path = g_current_folder[0..g_current_folder_len];
    searchDirectoryRecursive(folder_path, query, 0);
}

// Statically allocated home dir buffer for Windows
var g_home_dir_buf: [512]u8 = undefined;
var g_home_dir_len: usize = 0;
var g_home_dir_initialized: bool = false;

fn getHomeDir() ?[]const u8 {
    if (builtin.os.tag == .windows) {
        if (g_home_dir_initialized) {
            return if (g_home_dir_len > 0) g_home_dir_buf[0..g_home_dir_len] else null;
        }
        g_home_dir_initialized = true;

        // On Windows, use USERPROFILE env var
        const key = std.unicode.utf8ToUtf16LeStringLiteral("USERPROFILE");
        if (std.process.getenvW(key)) |value| {
            // Convert UTF-16 to UTF-8
            var i: usize = 0;
            for (value) |wchar| {
                if (wchar == 0) break;
                if (i >= g_home_dir_buf.len) break;
                if (wchar < 128) {
                    g_home_dir_buf[i] = @intCast(wchar);
                    i += 1;
                }
            }
            g_home_dir_len = i;
            return g_home_dir_buf[0..g_home_dir_len];
        }
        return null;
    } else {
        return std.posix.getenv("HOME");
    }
}

fn getConfigDir(buf: []u8) ?[]const u8 {
    const home = getHomeDir() orelse return null;
    const path = std.fmt.bufPrint(buf, "{s}/.mncode", .{home}) catch return null;
    return path;
}

fn getSettingsPath(buf: []u8) ?[]const u8 {
    const home = getHomeDir() orelse return null;
    const path = std.fmt.bufPrint(buf, "{s}/.mncode/settings.conf", .{home}) catch return null;
    return path;
}

fn ensureConfigDir() void {
    var dir_buf: [512]u8 = undefined;
    const dir_path = getConfigDir(&dir_buf) orelse return;

    // Create directory if it doesn't exist (ignore if already exists)
    std.fs.makeDirAbsolute(dir_path) catch |e| logger.warn("Operation failed: {}", .{e});
}

fn saveSettings() void {
    // Ensure config directory exists
    ensureConfigDir();

    var path_buf: [512]u8 = undefined;
    const path = getSettingsPath(&path_buf) orelse return;

    const file = std.fs.createFileAbsolute(path, .{}) catch return;
    defer file.close();

    // Write settings
    const inertia_data = if (g_scroll_inertia) "scroll_inertia=1\n" else "scroll_inertia=0\n";
    file.writeAll(inertia_data) catch |e| logger.warn("Operation failed: {}", .{e});

    // Scroll speed
    var speed_buf: [32]u8 = undefined;
    const speed_str = std.fmt.bufPrint(&speed_buf, "scroll_speed={d:.2}\n", .{g_scroll_speed}) catch return;
    file.writeAll(speed_str) catch |e| logger.warn("Operation failed: {}", .{e});

    // Line visibility
    var line_vis_buf: [32]u8 = undefined;
    const line_vis_str = std.fmt.bufPrint(&line_vis_buf, "line_visibility={d:.2}\n", .{g_line_visibility}) catch return;
    file.writeAll(line_vis_str) catch |e| logger.warn("Operation failed: {}", .{e});
}

fn loadSettings() void {
    var path_buf: [512]u8 = undefined;
    const path = getSettingsPath(&path_buf) orelse return;

    const file = std.fs.openFileAbsolute(path, .{}) catch return;
    defer file.close();

    var buf: [512]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return;
    const content = buf[0..bytes_read];

    // Parse scroll_inertia
    if (std.mem.indexOf(u8, content, "scroll_inertia=1")) |_| {
        g_scroll_inertia = true;
    } else {
        g_scroll_inertia = false;
    }

    // Parse scroll_speed
    if (std.mem.indexOf(u8, content, "scroll_speed=")) |start| {
        const value_start = start + "scroll_speed=".len;
        var end = value_start;
        while (end < content.len and content[end] != '\n' and content[end] != '\r') : (end += 1) {}
        if (end > value_start) {
            const value_str = content[value_start..end];
            g_scroll_speed = std.fmt.parseFloat(f32, value_str) catch 1.0;
            g_scroll_speed = @max(0.1, @min(10.0, g_scroll_speed));
            g_scroll_speed_slider.value = g_scroll_speed;
        }
    }

    // Parse line_visibility
    if (std.mem.indexOf(u8, content, "line_visibility=")) |start| {
        const value_start = start + "line_visibility=".len;
        var end = value_start;
        while (end < content.len and content[end] != '\n' and content[end] != '\r') : (end += 1) {}
        if (end > value_start) {
            const value_str = content[value_start..end];
            g_line_visibility = std.fmt.parseFloat(f32, value_str) catch 0.0;
            g_line_visibility = @max(0.0, @min(1.0, g_line_visibility));
            g_line_visibility_slider.value = g_line_visibility;
        }
    }
}

// Key repeat settings
const REPEAT_DELAY_MS: i64 = 400; // Initial delay
const REPEAT_RATE_MS: i64 = 50; // Repeat interval
const ACCEL_START_MS: i64 = 8000; // After 8 sec start skipping lines
const ACCEL_INTERVAL_MS: i64 = 3000; // Double every 3 sec

const KeyRepeatState = struct {
    held_key: ?u32 = null,
    held_char: ?u8 = null,
    press_time_ms: i64 = 0,
    last_repeat_ms: i64 = 0,
    skip_lines: u32 = 1,
    last_accel_ms: i64 = 0,
};

// Simple internal clipboard buffer
var clipboard_buffer: [64 * 1024]u8 = undefined;
var clipboard_len: usize = 0;

const SelectionState = struct {
    anchor: ?usize = null, // Selection start (null = no selection)
    dragging: bool = false, // Is mouse dragging

    pub fn hasSelection(self: *const SelectionState, cursor: usize) bool {
        if (self.anchor) |a| {
            return a != cursor;
        }
        return false;
    }

    pub fn getRange(self: *const SelectionState, cursor: usize) ?struct { start: usize, end: usize } {
        if (self.anchor) |a| {
            if (a != cursor) {
                return .{
                    .start = @min(a, cursor),
                    .end = @max(a, cursor),
                };
            }
        }
        return null;
    }

    pub fn clear(self: *SelectionState) void {
        self.anchor = null;
        self.dragging = false;
    }

    pub fn startAt(self: *SelectionState, pos: usize) void {
        self.anchor = pos;
    }
};

// === File Types & Icons ===
const FileType = enum {
    unknown,
    zig,
    c,
    cpp,
    python,
    javascript,
    json,
    markdown,
    text,
};

fn detectFileType(name: []const u8) FileType {
    // By extension
    if (name.len >= 4) {
        if (std.mem.eql(u8, name[name.len - 4 ..], ".zig")) return .zig;
        if (std.mem.eql(u8, name[name.len - 4 ..], ".txt")) return .text;
    }
    if (name.len >= 3) {
        if (std.mem.eql(u8, name[name.len - 3 ..], ".py")) return .python;
        if (std.mem.eql(u8, name[name.len - 3 ..], ".js")) return .javascript;
        if (std.mem.eql(u8, name[name.len - 3 ..], ".md")) return .markdown;
    }
    if (name.len >= 2) {
        if (std.mem.eql(u8, name[name.len - 2 ..], ".c")) return .c;
        if (std.mem.eql(u8, name[name.len - 2 ..], ".h")) return .c;
    }
    if (name.len >= 5) {
        if (std.mem.eql(u8, name[name.len - 5 ..], ".json")) return .json;
    }
    if (name.len >= 4) {
        if (std.mem.eql(u8, name[name.len - 4 ..], ".cpp")) return .cpp;
        if (std.mem.eql(u8, name[name.len - 4 ..], ".hpp")) return .cpp;
    }
    return .unknown;
}

fn getFileIcon(name: []const u8, is_dir: bool, is_expanded: bool) []const u8 {
    if (is_dir) {
        return if (is_expanded) "v " else "> ";
    }
    const ft = detectFileType(name);
    return switch (ft) {
        .zig => "Z ",
        .c, .cpp => "C ",
        .python => "P ",
        .javascript => "J ",
        .json => "{ ",
        .markdown => "M ",
        else => "  ",
    };
}

// === Language-aware editing helpers ===

/// Get current line indentation (number of spaces/tabs at the beginning)
fn getCurrentLineIndent(text_buffer: *const GapBuffer) []const u8 {
    const cursor = text_buffer.cursor();

    // Find the start of current line
    var line_start: usize = cursor;
    while (line_start > 0) {
        if (text_buffer.charAtConst(line_start - 1) == '\n') break;
        line_start -= 1;
    }

    // Count indentation
    var indent_end: usize = line_start;
    while (indent_end < text_buffer.len()) {
        const ch = text_buffer.charAtConst(indent_end) orelse break;
        if (ch != ' ' and ch != '\t') break;
        indent_end += 1;
    }

    // Return static buffer with indentation
    const indent_len = indent_end - line_start;
    if (indent_len == 0) return "";
    if (indent_len > 64) return "                                                                "; // 64 spaces max

    // Use static buffer
    const spaces = "                                                                "; // 64 spaces
    return spaces[0..indent_len];
}

/// Check if current line ends with a character that requires extra indentation
/// For C/Zig/JS: { ( [
/// For Python: :
fn shouldAddExtraIndent(text_buffer: *const GapBuffer, file_type: FileType) bool {
    const cursor = text_buffer.cursor();
    if (cursor == 0) return false;

    // Find last non-whitespace character before cursor on this line
    var pos: usize = cursor;
    while (pos > 0) {
        pos -= 1;
        const ch = text_buffer.charAtConst(pos) orelse continue;
        if (ch == '\n') break;
        if (ch != ' ' and ch != '\t') {
            // Python: indent after colon
            if (file_type == .python) {
                return ch == ':' or ch == '{' or ch == '(' or ch == '[';
            }
            // Other languages: indent after brackets
            return ch == '{' or ch == '(' or ch == '[';
        }
    }
    return false;
}

/// Get closing bracket for opening one
fn getClosingBracket(open: u8) ?u8 {
    return switch (open) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        '"' => '"',
        '\'' => '\'',
        else => null,
    };
}

/// Find matching bracket position
fn findMatchingBracket(text_buffer: *const GapBuffer, pos: usize) ?usize {
    const ch = text_buffer.charAtConst(pos) orelse return null;

    const is_open = ch == '(' or ch == '[' or ch == '{';
    const is_close = ch == ')' or ch == ']' or ch == '}';

    if (!is_open and !is_close) return null;

    const target: u8 = if (is_open)
        getClosingBracket(ch) orelse return null
    else switch (ch) {
        ')' => '(',
        ']' => '[',
        '}' => '{',
        else => return null,
    };

    var depth: i32 = 1;
    var search_pos: usize = pos;

    if (is_open) {
        // Search forward
        while (search_pos + 1 < text_buffer.len()) {
            search_pos += 1;
            const sc = text_buffer.charAtConst(search_pos) orelse continue;
            if (sc == ch) depth += 1
            else if (sc == target) {
                depth -= 1;
                if (depth == 0) return search_pos;
            }
        }
    } else {
        // Search backward
        while (search_pos > 0) {
            search_pos -= 1;
            const sc = text_buffer.charAtConst(search_pos) orelse continue;
            if (sc == ch) depth += 1
            else if (sc == target) {
                depth -= 1;
                if (depth == 0) return search_pos;
            }
        }
    }

    return null;
}

/// Get line and column for byte position
fn getByteLineCol(text_buffer: *const GapBuffer, byte_pos: usize) struct { line: usize, col: usize } {
    var line: usize = 0;
    var col: usize = 0;
    var i: usize = 0;

    while (i < byte_pos and i < text_buffer.len()) : (i += 1) {
        if (text_buffer.charAtConst(i) == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    }

    return .{ .line = line, .col = col };
}

fn getFileIconColor(name: []const u8, is_dir: bool) u32 {
    if (is_dir) return COLOR_ACCENT;
    const ft = detectFileType(name);
    return switch (ft) {
        .zig => 0xFFf7a41d, // Zig orange
        .c, .cpp => 0xFF519aba, // C blue
        .python => 0xFF3572a5, // Python blue
        .javascript => 0xFFf7df1e, // JS yellow
        .json => 0xFFcbcb41, // JSON yellow
        .markdown => 0xFF519aba, // Markdown blue
        else => COLOR_TEXT_DIM,
    };
}

// === Zig Syntax Highlighting ===
const TokenType = enum {
    text,
    keyword,
    type_name,
    builtin,
    string,
    char_literal,
    number,
    comment,
    function,
    operator,
    punctuation,
    field,
};

const Token = struct {
    start: usize,
    len: usize,
    token_type: TokenType,
};

// Zig keywords
const zig_keywords = [_][]const u8{
    "addrspace", "align", "allowzero", "and", "anyframe", "anytype",
    "asm", "async", "await", "break", "catch", "comptime",
    "const", "continue", "defer", "else", "enum", "errdefer",
    "error", "export", "extern", "fn", "for", "if",
    "inline", "linksection", "noalias", "nosuspend", "opaque", "or",
    "orelse", "packed", "pub", "resume", "return", "struct",
    "suspend", "switch", "test", "threadlocal", "try", "union",
    "unreachable", "usingnamespace", "var", "volatile", "while",
    "undefined", "null", "true", "false",
};

// Zig types
const zig_types = [_][]const u8{
    "i8", "i16", "i32", "i64", "i128", "isize",
    "u8", "u16", "u32", "u64", "u128", "usize",
    "f16", "f32", "f64", "f80", "f128",
    "bool", "void", "noreturn", "type", "anyerror", "anyopaque",
    "comptime_int", "comptime_float",
};

fn isZigKeyword(word: []const u8) bool {
    for (zig_keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isZigType(word: []const u8) bool {
    for (zig_types) |t| {
        if (std.mem.eql(u8, word, t)) return true;
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

fn tokenizeLine(line: []const u8, tokens: []Token, in_multiline_comment: bool) struct { count: usize, still_in_comment: bool } {
    var count: usize = 0;
    var i: usize = 0;
    var in_comment = in_multiline_comment;

    while (i < line.len and count < tokens.len) {
        // Skip whitespace
        if (line[i] == ' ' or line[i] == '\t') {
            i += 1;
            continue;
        }

        // Multi-line comment continuation
        if (in_comment) {
            const start = i;
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    i += 2;
                    in_comment = false;
                    break;
                }
                i += 1;
            }
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .comment };
            count += 1;
            continue;
        }

        // Single-line comment
        if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '/') {
            tokens[count] = .{ .start = i, .len = line.len - i, .token_type = .comment };
            count += 1;
            break;
        }

        // Multi-line comment start
        if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*') {
            const start = i;
            i += 2;
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    i += 2;
                    break;
                }
                i += 1;
            } else {
                in_comment = true;
            }
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .comment };
            count += 1;
            continue;
        }

        // String literal
        if (line[i] == '"') {
            const start = i;
            i += 1;
            while (i < line.len) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2;
                } else if (line[i] == '"') {
                    i += 1;
                    break;
                } else {
                    i += 1;
                }
            }
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .string };
            count += 1;
            continue;
        }

        // Character literal
        if (line[i] == '\'') {
            const start = i;
            i += 1;
            while (i < line.len and line[i] != '\'') {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2;
                } else {
                    i += 1;
                }
            }
            if (i < line.len) i += 1;
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .char_literal };
            count += 1;
            continue;
        }

        // Builtin (@identifier)
        if (line[i] == '@') {
            const start = i;
            i += 1;
            while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .builtin };
            count += 1;
            continue;
        }

        // Number
        if (isDigit(line[i]) or (line[i] == '.' and i + 1 < line.len and isDigit(line[i + 1]))) {
            const start = i;
            // Hex
            if (line[i] == '0' and i + 1 < line.len and (line[i + 1] == 'x' or line[i + 1] == 'X')) {
                i += 2;
                while (i < line.len and (isDigit(line[i]) or
                    (line[i] >= 'a' and line[i] <= 'f') or
                    (line[i] >= 'A' and line[i] <= 'F') or line[i] == '_')) : (i += 1)
                {}
            } else {
                // Decimal/float
                while (i < line.len and (isDigit(line[i]) or line[i] == '.' or line[i] == '_' or line[i] == 'e' or line[i] == 'E')) : (i += 1) {}
            }
            tokens[count] = .{ .start = start, .len = i - start, .token_type = .number };
            count += 1;
            continue;
        }

        // Identifier / keyword / type
        if (isIdentChar(line[i]) and !isDigit(line[i])) {
            const start = i;
            while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
            const word = line[start..i];

            var tt: TokenType = .text;
            if (isZigKeyword(word)) {
                tt = .keyword;
            } else if (isZigType(word)) {
                tt = .type_name;
            } else if (i < line.len and line[i] == '(') {
                tt = .function;
            } else if (start > 0 and line[start - 1] == '.') {
                tt = .field;
            }

            tokens[count] = .{ .start = start, .len = i - start, .token_type = tt };
            count += 1;
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        tokens[count] = .{ .start = start, .len = 1, .token_type = .punctuation };
        count += 1;
    }

    return .{ .count = count, .still_in_comment = in_comment };
}

fn getTokenColor(tt: TokenType) u32 {
    return switch (tt) {
        .keyword => SYN_KEYWORD,
        .type_name => SYN_TYPE,
        .builtin => SYN_BUILTIN,
        .string, .char_literal => SYN_STRING,
        .number => SYN_NUMBER,
        .comment => SYN_COMMENT,
        .function => SYN_FUNCTION,
        .operator => SYN_OPERATOR,
        .punctuation => SYN_PUNCTUATION,
        .field => SYN_FIELD,
        .text => COLOR_TEXT,
    };
}

fn getTimeMs() i64 {
    const ts = std.time.nanoTimestamp();
    return @intCast(@divTrunc(ts, 1_000_000));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load settings from ~/.mncode
    loadSettings();

    // Initialize logger
    logger.initDefault();

    // Plugins are loaded later (after GPU initialization)

    // Use embedded fonts (compiled into binary)
    const font_data = EMBEDDED_FONT;
    const ui_font_data = EMBEDDED_UI_FONT;

    // Create empty text buffer
    var text_buffer = try GapBuffer.init(allocator);
    defer text_buffer.deinit();

    // Platform initialization
    var wayland: Wayland = if (builtin.os.tag == .windows)
        .{}
    else
        .{
            .display = undefined,
            .registry = undefined,
        };
    try wayland.init();
    defer wayland.deinit();

    // Wait for window configuration
    while (!wayland.configured) {
        if (!wayland.dispatch()) break;
    }

    // Create GPU renderer (platform-specific)
    var gpu = if (builtin.os.tag == .windows)
        try GpuRenderer.initWindows(&wayland, wayland.width, wayland.height)
    else
        try GpuRenderer.init(wayland.surface.?, wayland.display, wayland.width, wayland.height);
    defer gpu.deinit();

    // Initialize icons
    icons.init();
    defer icons.deinit(&gpu);

    // Initialize font atlas for GPU
    try gpu.initFontAtlas(font_data, FONT_SIZE);
    // Initialize UI font
    try gpu.initUIFontAtlas(ui_font_data, UI_FONT_SIZE);
    var current_width = wayland.width;
    var current_height = wayland.height;

    var key_repeat = KeyRepeatState{};
    var selection = SelectionState{};
    var needs_redraw = true;
    var scroll_x: i32 = 0; // Horizontal scroll
    var scroll_y: i32 = 0; // Vertical scroll
    var just_navigated = false; // Navigation flag (for scroll)


    // UI zoom level (1.0 = 100%)
    var zoom_level: f32 = 1.0;
    const ZOOM_MIN: f32 = 0.5;  // 50%
    const ZOOM_MAX: f32 = 2.0;  // 200%
    const ZOOM_STEP: f32 = 0.1; // 10% step

    // Text zoom level (1.0 = 100%)
    var text_zoom: f32 = 1.0;
    const TEXT_ZOOM_MIN: f32 = 0.5;  // 50%
    const TEXT_ZOOM_MAX: f32 = 3.0;  // 300%
    const TEXT_ZOOM_STEP: f32 = 0.1; // 10% step

    // UI State (using modular UIState)
    var ui = UIState.init();

    // === Search state ===
    var search_visible = false;
    var search_query_buf: [256]u8 = [_]u8{0} ** 256;
    var search_field = text_input.TextFieldBuffer.init(&search_query_buf);
    var search_matches: [4096]usize = undefined; // Match positions
    var search_match_count: usize = 0;
    var search_current_match: usize = 0;
    var search_key_repeat = text_input.KeyRepeatState{}; // Key repeat for search

    // === Editor focus state ===
    var editor_focused: bool = true; // Cursor visible only when editor is focused

    // File/Folder state
    var current_folder_path: [1024]u8 = [_]u8{0} ** 1024;
    var current_folder_len: usize = 0;

    // === Tab System ===
    const MAX_TABS = 16;
    var tab_buffers: [MAX_TABS]?*GapBuffer = [_]?*GapBuffer{null} ** MAX_TABS;
    var tab_paths: [MAX_TABS][512]u8 = undefined;
    var tab_path_lens: [MAX_TABS]usize = [_]usize{0} ** MAX_TABS;
    var tab_names: [MAX_TABS][64]u8 = undefined; // Display name (file name)
    var tab_name_lens: [MAX_TABS]usize = [_]usize{0} ** MAX_TABS;
    var tab_modified: [MAX_TABS]bool = [_]bool{false} ** MAX_TABS;
    var tab_scroll_x: [MAX_TABS]i32 = [_]i32{0} ** MAX_TABS;
    var tab_scroll_y: [MAX_TABS]i32 = [_]i32{0} ** MAX_TABS;
    var tab_is_plugin: [MAX_TABS]bool = [_]bool{false} ** MAX_TABS; // true = plugin details tab
    var tab_plugin_idx: [MAX_TABS]usize = [_]usize{0} ** MAX_TABS; // which plugin
    var tab_count: usize = 0;
    var active_tab: usize = 0;
    var tab_hovered: i32 = -1;
    var tab_close_hovered: i32 = -1;

    // Create first tab (Untitled)
    tab_buffers[0] = &text_buffer;
    const untitled = "Untitled";
    @memcpy(tab_names[0][0..untitled.len], untitled);
    tab_name_lens[0] = untitled.len;
    tab_count = 1;

    // === Undo/Redo System ===
    const MAX_UNDO = 100;
    const MAX_UNDO_SIZE = 64 * 1024; // 64KB max per undo state
    var undo_stack: [MAX_UNDO][MAX_UNDO_SIZE]u8 = undefined;
    var undo_lens: [MAX_UNDO]usize = [_]usize{0} ** MAX_UNDO;
    var undo_cursors: [MAX_UNDO]usize = [_]usize{0} ** MAX_UNDO;
    var undo_count: usize = 0;

    var redo_stack: [MAX_UNDO][MAX_UNDO_SIZE]u8 = undefined;
    var redo_lens: [MAX_UNDO]usize = [_]usize{0} ** MAX_UNDO;
    var redo_cursors: [MAX_UNDO]usize = [_]usize{0} ** MAX_UNDO;
    var redo_count: usize = 0;

    // Original content for tracking real modifications
    var tab_original_content: [MAX_TABS][MAX_UNDO_SIZE]u8 = undefined;
    var tab_original_lens: [MAX_TABS]usize = [_]usize{0} ** MAX_TABS;

    // Tree file structure
    var folder_files: [256][256]u8 = undefined;
    var folder_file_lens: [256]usize = [_]usize{0} ** 256;
    var folder_file_count: usize = 0;
    var folder_is_dir: [256]bool = [_]bool{false} ** 256;
    var folder_expanded: [256]bool = [_]bool{false} ** 256;
    var folder_anim_progress: [256]f32 = [_]f32{0.0} ** 256; // 0.0 = collapsed, 1.0 = expanded
    var folder_indent: [256]u8 = [_]u8{0} ** 256; // Nesting level
    var folder_parent: [256]i16 = [_]i16{-1} ** 256; // Parent folder
    var folder_full_path: [256][512]u8 = undefined; // Full path to each element
    var folder_full_path_lens: [256]usize = [_]usize{0} ** 256;

    var explorer_selected: i32 = -1;
    var explorer_hovered: i32 = -1;
    var explorer_scroll: i32 = 0;
    var animation_active = false; // Active animation flag

    // Plugin hover state
    var plugin_hovered: i32 = -1;

    // Plugin system - lazy loading
    var plugin_check_counter: u32 = 0;
    const PLUGIN_CHECK_INTERVAL: u32 = 60; // Check every ~60 frames (~1 sec)
    defer plugins.deinitLoader();

    // Main loop
    while (wayland.running) {
        // Check for new plugins periodically
        plugin_check_counter += 1;
        if (plugin_check_counter >= PLUGIN_CHECK_INTERVAL) {
            plugin_check_counter = 0;
            const plugin_changes = plugins.checkAndLoadNewPlugins();
            if (plugin_changes > 0) {
                needs_redraw = true;
            }
        }

        // Continue lazy loading if file is partially loaded
        if (g_lazy_loader.isPartial()) {
            // Load ALL remaining content without redrawing (fast bulk load)
            while (g_lazy_loader.continueLoad(&text_buffer)) {}
            // Now that loading is complete, sync and redraw once
            g_line_index_count = text_buffer.lineCount();
            invalidateLineIndex();
            needs_redraw = true;
        }

        // Check for window resize
        if (wayland.width != current_width or wayland.height != current_height) {
            gpu.resize(wayland.width, wayland.height);
            current_width = wayland.width;
            current_height = wayland.height;
            needs_redraw = true;
        }
        // Non-blocking flush
        _ = c.wl_display_flush(wayland.display);

        // Dispatch pending events (non-blocking)
        while (c.wl_display_prepare_read(wayland.display) != 0) {
            _ = c.wl_display_dispatch_pending(wayland.display);
        }

        // Poll with timeout for key repeat and animations
        var fds = [_]std.posix.pollfd{.{
            .fd = c.wl_display_get_fd(wayland.display),
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const timeout: i32 = if (key_repeat.held_key != null or animation_active or selection.dragging or g_lazy_loader.isPartial()) 16 else -1; // 60fps for animation, drag selection, and lazy loading
        _ = std.posix.poll(&fds, timeout) catch |e| logger.warn("Operation failed: {}", .{e});

        if ((fds[0].revents & std.posix.POLL.IN) != 0) {
            _ = c.wl_display_read_events(wayland.display);
            _ = c.wl_display_dispatch_pending(wayland.display);
        } else {
            c.wl_display_cancel_read(wayland.display);
        }

        const now = getTimeMs();

        // Menu block parameters (must match drawTitlebar, accounting for zoom)
        const titlebar_h_loop: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level));
        const menu_width: i32 = scaleI(140, zoom_level);
        const menu_height: i32 = scaleI(26, zoom_level);
        const menu_x: i32 = scaleI(8, zoom_level);
        const menu_y: i32 = @divTrunc(titlebar_h_loop - menu_height, 2);
        const menu_section: i32 = @divTrunc(menu_width, 3);

        // Determine menu hover
        const mx = wayland.mouse_x;
        const my = wayland.mouse_y;
        const in_menu_block = mx >= menu_x and mx < menu_x + menu_width and
            my >= menu_y and my < menu_y + menu_height;

        if (in_menu_block) {
            ui.menu_hover = @divTrunc(mx - menu_x, menu_section);
            if (ui.menu_hover > 2) ui.menu_hover = 2;
        } else {
            ui.menu_hover = -1;
        }

        // If menu is open - redraw and handle dropdown hover
        if (ui.menu_open >= 0) {
            const menu_block_x: i32 = scaleI(8, zoom_level);
            const menu_block_y: i32 = @divTrunc(titlebar_h_loop - scaleI(26, zoom_level), 2);
            const menu_section_w: i32 = scaleI(46, zoom_level);
            const dropdown_x: i32 = menu_block_x + ui.menu_open * menu_section_w;
            const dropdown_y: i32 = menu_block_y + scaleI(26, zoom_level) + 2;
            const dropdown_w: i32 = scaleI(160, zoom_level);
            const items_count: i32 = if (ui.menu_open == 0) 4 else if (ui.menu_open == 1) 7 else 10;
            const dropdown_h: i32 = items_count * scaleI(28, zoom_level) + scaleI(8, zoom_level);

            const in_dropdown = mx >= dropdown_x and mx < dropdown_x + dropdown_w and
                my >= dropdown_y and my < dropdown_y + dropdown_h;

            if (in_dropdown) {
                const rel_y = my - dropdown_y - 4;
                const new_item_hover = @divTrunc(rel_y, 28);
                if (new_item_hover >= 0 and new_item_hover < items_count) {
                    ui.menu_item_hover = new_item_hover;
                } else {
                    ui.menu_item_hover = -1;
                }
            } else {
                ui.menu_item_hover = -1;
            }
            needs_redraw = true;
        } else if (ui.menu_hover >= 0) {
            needs_redraw = true;
        }

        // Check mouse movement for drag selection and cursor
        if (wayland.mouse_moved) {
            wayland.mouse_moved = false;

            // Handle scrollbar drag (accounting for zoom)
            if (ui.dragging_vbar) {
                const delta = wayland.mouse_y - ui.drag_start_mouse;
                const line_h: i32 = @intCast(gpu.lineHeight());
                const titlebar_h_drag: u32 = scaleUI(TITLEBAR_HEIGHT, zoom_level);
                const vbar_height: i32 = @intCast(wayland.height - titlebar_h_drag - 18 - 12);
                const content_height = @as(i32, @intCast(g_cached_line_count)) * line_h + line_h * 5;
                const visible_height: i32 = @as(i32, @intCast(wayland.height)) - @as(i32, @intCast(titlebar_h_drag)) - 30;
                const max_scroll = @max(0, content_height - visible_height);
                const scroll_per_pixel = @divTrunc(max_scroll * 100, @max(1, vbar_height));
                const new_scroll = ui.drag_start_scroll + @divTrunc(delta * scroll_per_pixel, 100);
                scroll_y = @max(0, @min(max_scroll, new_scroll));
                needs_redraw = true;
            } else if (ui.dragging_hbar) {
                const delta = wayland.mouse_x - ui.drag_start_mouse;
                const char_w: i32 = @intCast(gpu.charWidth());
                // Account for sidebar when calculating width (with zoom)
                const editor_margin: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const editor_left_drag: i32 = if (ui.sidebar_visible) ui.sidebar_width + editor_margin else editor_margin;
                const editor_w_drag: i32 = @as(i32, @intCast(wayland.width)) - editor_margin - editor_left_drag;
                const hbar_width: i32 = editor_w_drag - 18 - 8;
                // Entire field moves together
                const gutter_w_drag: i32 = @intCast(scaleUI(GUTTER_WIDTH, zoom_level));
                const content_width = gutter_w_drag + 12 + @as(i32, @intCast(g_cached_max_line_len)) * char_w + char_w * 10;
                const visible_width: i32 = editor_w_drag - 18;
                const max_scroll_x = @max(0, content_width - visible_width);
                const scroll_per_pixel = @divTrunc(max_scroll_x * 100, @max(1, hbar_width));
                const new_scroll = ui.drag_start_scroll + @divTrunc(delta * scroll_per_pixel, 100);
                scroll_x = @max(0, @min(max_scroll_x, new_scroll));
                needs_redraw = true;
            } else if (ui.dragging_sidebar) {
                // Resize sidebar (mouse_x + 6 to account for padding)
                ui.sidebar_width = @max(100, @min(500, wayland.mouse_x + 6));
                needs_redraw = true;
            } else if (ui.dragging_bottom_panel) {
                // Resize bottom panel (drag up increases height)
                const delta = ui.drag_start_mouse - wayland.mouse_y;
                g_bottom_panel_height = @max(80, @min(400, ui.drag_start_scroll + delta));
                needs_redraw = true;
            } else if (ui.dragging_tab_bar) {
                // Resize tab bar (drag up decreases height)
                const delta = wayland.mouse_y - ui.drag_start_mouse;
                g_tab_bar_height = @max(30, @min(80, ui.drag_start_scroll - delta));
                needs_redraw = true;
            } else if (selection.dragging) {
                // Only update cursor position on mouse movement
                // Index and cache should already be valid (built during render or first click)
                const click_pos = screenToTextPos(&gpu, &text_buffer, wayland.mouse_x, wayland.mouse_y, scroll_x, scroll_y, ui.sidebar_visible, ui.sidebar_width);
                if (click_pos) |pos| {
                    text_buffer.moveCursor(pos);
                }
                needs_redraw = true;
            }

            // Change cursor based on position
            const resize_edge = getResizeEdge(wayland.mouse_x, wayland.mouse_y, wayland.width, wayland.height, zoom_level);

            // Check scrollbar zone (with zoom)
            const scrollbar_zone: i32 = 18;
            const mouse_px = wayland.mouse_x;
            const mouse_py = wayland.mouse_y;
            const ww: i32 = @intCast(wayland.width);
            const wh: i32 = @intCast(wayland.height);
            // Account for sidebar for horizontal scrollbar
            const editor_margin_cursor: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
            const editor_left_cursor: i32 = if (ui.sidebar_visible) ui.sidebar_width + editor_margin_cursor else editor_margin_cursor;
            const in_vbar = mouse_px >= ww - scrollbar_zone and mouse_py > titlebar_h_loop and mouse_py < wh - scrollbar_zone;
            const in_hbar = mouse_py >= wh - scrollbar_zone and mouse_px > editor_left_cursor and mouse_px < ww - scrollbar_zone;

            // Check sidebar edge for resize - small handle in center
            const sidebar_margin_edge: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
            const sidebar_y_edge: i32 = titlebar_h_loop + sidebar_margin_edge;
            const sidebar_h_edge: i32 = @as(i32, @intCast(wayland.height)) - titlebar_h_loop - sidebar_margin_edge * 2;
            const resize_handle_h: i32 = 40;
            const resize_bar_center = sidebar_y_edge + @divTrunc(sidebar_h_edge, 2);
            const resize_bar_top = resize_bar_center - @divTrunc(resize_handle_h, 2);
            const resize_bar_bottom = resize_bar_center + @divTrunc(resize_handle_h, 2);
            const sidebar_edge = ui.sidebar_width - sidebar_margin_edge - 3;
            const on_sidebar_edge = ui.sidebar_visible and
                wayland.mouse_x >= sidebar_edge - 4 and wayland.mouse_x <= sidebar_edge + 8 and
                wayland.mouse_y >= resize_bar_top and wayland.mouse_y <= resize_bar_bottom;

            // Update hover state of resize bar
            if (on_sidebar_edge != ui.sidebar_resize_hovered) {
                ui.sidebar_resize_hovered = on_sidebar_edge;
                needs_redraw = true;
            }

            // Check tab bar edge for resize
            const tab_bar_top: i32 = wh - editor_margin_cursor - g_tab_bar_height;
            const tab_bar_left: i32 = editor_left_cursor;
            const tab_bar_right: i32 = ww - editor_margin_cursor;
            const on_tab_bar_edge = wayland.mouse_y >= tab_bar_top - 4 and wayland.mouse_y <= tab_bar_top + 4 and
                wayland.mouse_x >= tab_bar_left and wayland.mouse_x <= tab_bar_right;

            if (on_tab_bar_edge != ui.tab_bar_resize_hovered) {
                ui.tab_bar_resize_hovered = on_tab_bar_edge;
                needs_redraw = true;
            }

            // Check hover over sidebar tabs (with zoom)
            var new_sidebar_tab_hovered: i32 = -1;
            if (ui.sidebar_visible and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_h: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_y_h: i32 = titlebar_h_loop + sidebar_margin_h;
                const stab_y_h: i32 = sidebar_y_h + scaleI(8, zoom_level);
                const stab_h_h: i32 = scaleI(24, zoom_level);

                // Check hover on sidebar tabs (icons) - 4 tabs: Explorer, Search, Git, Plugins
                if (wayland.mouse_y >= stab_y_h and wayland.mouse_y < stab_y_h + stab_h_h) {
                    const stab_w: i32 = scaleI(32, zoom_level); // Square tab width
                    var check_x: i32 = sidebar_margin_h + scaleI(8, zoom_level);
                    for (0..4) |tab_i| {
                        if (wayland.mouse_x >= check_x and wayland.mouse_x < check_x + stab_w) {
                            new_sidebar_tab_hovered = @intCast(tab_i);
                            break;
                        }
                        check_x += stab_w + scaleI(4, zoom_level);
                    }
                }
            }
            if (new_sidebar_tab_hovered != ui.sidebar_tab_hovered) {
                ui.sidebar_tab_hovered = new_sidebar_tab_hovered;
                needs_redraw = true;
            }

            // Check hover over Open Folder button (when no folder is open, with zoom)
            var new_open_folder_btn_hovered: bool = false;
            if (ui.sidebar_visible and current_folder_len == 0 and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_btn: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const titlebar_h_btn: u32 = scaleUI(TITLEBAR_HEIGHT, zoom_level);
                const sidebar_y_btn: i32 = @as(i32, @intCast(titlebar_h_btn)) + sidebar_margin_btn;
                const sidebar_h_btn = wayland.height - titlebar_h_btn - @as(u32, @intCast(sidebar_margin_btn)) * 2;
                const btn_y: i32 = sidebar_y_btn + @as(i32, @intCast(sidebar_h_btn / 2)) - scaleI(20, zoom_level);
                const btn_x: i32 = sidebar_margin_btn + scaleI(20, zoom_level);
                const btn_w: i32 = ui.sidebar_width - scaleI(56, zoom_level);
                const btn_h: i32 = scaleI(36, zoom_level);
                if (wayland.mouse_x >= btn_x and wayland.mouse_x < btn_x + btn_w and
                    wayland.mouse_y >= btn_y and wayland.mouse_y < btn_y + btn_h)
                {
                    new_open_folder_btn_hovered = true;
                }
            }
            if (new_open_folder_btn_hovered != ui.open_folder_btn_hovered) {
                ui.open_folder_btn_hovered = new_open_folder_btn_hovered;
                needs_redraw = true;
            }

            // Check hover over file manager buttons
            var new_fm_add_file_hovered: bool = false;
            var new_fm_add_folder_hovered: bool = false;
            var new_fm_delete_hovered: bool = false;
            if (ui.sidebar_visible and ui.sidebar_active_tab == 0 and current_folder_len > 0 and wayland.mouse_x < ui.sidebar_width) {
                const sidebar_margin_fm: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_x_fm: i32 = sidebar_margin_fm;
                const sidebar_w_fm: i32 = ui.sidebar_width - sidebar_margin_fm * 2;
                const sidebar_y_fm: i32 = titlebar_h_loop + sidebar_margin_fm;
                const header_y_fm: i32 = sidebar_y_fm + scaleI(8 + 24 + 12, zoom_level);
                const btn_size_fm: i32 = scaleI(22, zoom_level);
                const btn_spacing_fm: i32 = scaleI(2, zoom_level);
                const sidebar_padding_fm: i32 = scaleI(10, zoom_level);
                const btns_y_fm: i32 = header_y_fm - scaleI(4, zoom_level);
                var btn_x_fm: i32 = sidebar_x_fm + sidebar_w_fm - sidebar_padding_fm - btn_size_fm * 3 - btn_spacing_fm * 2;

                if (wayland.mouse_y >= btns_y_fm and wayland.mouse_y < btns_y_fm + btn_size_fm) {
                    // New File button
                    if (wayland.mouse_x >= btn_x_fm and wayland.mouse_x < btn_x_fm + btn_size_fm) {
                        new_fm_add_file_hovered = true;
                    }
                    btn_x_fm += btn_size_fm + btn_spacing_fm;

                    // New Folder button
                    if (wayland.mouse_x >= btn_x_fm and wayland.mouse_x < btn_x_fm + btn_size_fm) {
                        new_fm_add_folder_hovered = true;
                    }
                    btn_x_fm += btn_size_fm + btn_spacing_fm;

                    // Delete button
                    if (explorer_selected >= 0 and wayland.mouse_x >= btn_x_fm and wayland.mouse_x < btn_x_fm + btn_size_fm) {
                        new_fm_delete_hovered = true;
                    }
                }
            }
            if (new_fm_add_file_hovered != g_fm_add_file_btn_hovered or
                new_fm_add_folder_hovered != g_fm_add_folder_btn_hovered or
                new_fm_delete_hovered != g_fm_delete_btn_hovered)
            {
                g_fm_add_file_btn_hovered = new_fm_add_file_hovered;
                g_fm_add_folder_btn_hovered = new_fm_add_folder_hovered;
                g_fm_delete_btn_hovered = new_fm_delete_hovered;
                needs_redraw = true;
            }

            // Check hover over explorer items (with zoom)
            var new_explorer_hovered: i32 = -1;
            if (ui.sidebar_visible and ui.sidebar_active_tab == 0 and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_h: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_y_h: i32 = titlebar_h_loop + sidebar_margin_h;
                const file_start_y_h: i32 = sidebar_y_h + scaleI(8 + 24 + 12 + 20, zoom_level); // tabs + separator + header
                const file_item_h: i32 = scaleI(28, zoom_level);

                if (wayland.mouse_y >= file_start_y_h and folder_file_count > 0) {
                    const rel_y = wayland.mouse_y - file_start_y_h + explorer_scroll;
                    const hover_idx: i32 = @divTrunc(rel_y, file_item_h);
                    if (hover_idx >= 0 and hover_idx < @as(i32, @intCast(folder_file_count))) {
                        new_explorer_hovered = hover_idx;
                    }
                }
            }
            if (new_explorer_hovered != explorer_hovered) {
                explorer_hovered = new_explorer_hovered;
                needs_redraw = true;
            }

            // Check hover over plugins in sidebar
            var new_plugin_hovered: i32 = -1;
            if (ui.sidebar_visible and ui.sidebar_active_tab == 3 and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_h: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_y_h: i32 = titlebar_h_loop + sidebar_margin_h;
                const sidebar_w_h: i32 = ui.sidebar_width - sidebar_margin_h * 2;
                const plugin_start_y: i32 = sidebar_y_h + scaleI(8 + 24 + 12 + 20 + 30, zoom_level);
                const plugin_item_h: i32 = 58;

                const loader = plugins.getLoader();
                // Count only active plugins
                var active_count: i32 = 0;
                for (0..loader.plugin_count) |pi| {
                    if (loader.getPlugin(pi)) |plugin| {
                        if (plugin.state == .active) {
                            const item_y = plugin_start_y + active_count * plugin_item_h;
                            if (wayland.mouse_y >= item_y and wayland.mouse_y < item_y + 50 and
                                wayland.mouse_x >= sidebar_margin_h + 8 and wayland.mouse_x < sidebar_margin_h + sidebar_w_h - 8)
                            {
                                new_plugin_hovered = active_count;
                            }
                            active_count += 1;
                        }
                    }
                }
            }
            if (new_plugin_hovered != plugin_hovered) {
                plugin_hovered = new_plugin_hovered;
                needs_redraw = true;
            }

            // Check hover over disabled plugins
            var new_disabled_plugin_hovered: i32 = -1;
            if (ui.sidebar_visible and ui.sidebar_active_tab == 3 and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_h: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_y_h: i32 = titlebar_h_loop + sidebar_margin_h;
                const sidebar_w_h: i32 = ui.sidebar_width - sidebar_margin_h * 2;
                const plugin_start_y: i32 = sidebar_y_h + scaleI(8 + 24 + 12 + 20 + 30, zoom_level);
                const plugin_item_h: i32 = 58;
                const disabled_item_h: i32 = 44;

                const loader = plugins.getLoader();
                var active_count: i32 = 0;
                for (0..loader.plugin_count) |pi| {
                    if (loader.getPlugin(pi)) |plugin| {
                        if (plugin.state == .active) {
                            active_count += 1;
                        }
                    }
                }

                const disabled_plugins = plugins.getDisabledPlugins();
                if (disabled_plugins.len > 0) {
                    const disabled_section_y = plugin_start_y + active_count * plugin_item_h + 10 + 15 + 25;
                    for (0..disabled_plugins.len) |di| {
                        const item_y = disabled_section_y + @as(i32, @intCast(di)) * disabled_item_h;
                        if (wayland.mouse_y >= item_y and wayland.mouse_y < item_y + 36 and
                            wayland.mouse_x >= sidebar_margin_h + 8 and wayland.mouse_x < sidebar_margin_h + sidebar_w_h - 8)
                        {
                            new_disabled_plugin_hovered = @intCast(di);
                            break;
                        }
                    }
                }
            }
            if (new_disabled_plugin_hovered != g_disabled_plugin_hovered) {
                g_disabled_plugin_hovered = new_disabled_plugin_hovered;
                needs_redraw = true;
            }

            // Check hover over search results
            var new_search_result_hovered: i32 = -1;
            if (ui.sidebar_visible and ui.sidebar_active_tab == 1 and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > titlebar_h_loop) {
                const sidebar_margin_h: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                const sidebar_y_h: i32 = titlebar_h_loop + sidebar_margin_h;
                const search_area_y: i32 = sidebar_y_h + scaleI(8 + 24 + 12 + 20, zoom_level);
                const input_h: i32 = 28;
                const results_y: i32 = search_area_y + 10 + input_h + 12 + 20;
                const result_item_h: i32 = 48;

                if (g_search_result_count > 0 and wayland.mouse_y >= results_y) {
                    const rel_y = wayland.mouse_y - results_y;
                    const hover_idx = @divTrunc(rel_y, result_item_h) + g_search_result_scroll;
                    if (hover_idx >= 0 and hover_idx < @as(i32, @intCast(g_search_result_count))) {
                        new_search_result_hovered = hover_idx;
                    }
                }
            }
            if (new_search_result_hovered != g_search_result_hovered) {
                g_search_result_hovered = new_search_result_hovered;
                needs_redraw = true;
            }

            // Check hover over tabs
            var new_tab_hovered: i32 = -1;
            var new_tab_close_hovered: i32 = -1;
            // Coordinates match render function (with zoom)
            const hover_editor_margin: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
            const hover_editor_left: i32 = if (ui.sidebar_visible) ui.sidebar_width + hover_editor_margin else hover_editor_margin;
            const hover_tab_bar_h: i32 = @intCast(scaleUI(TAB_BAR_HEIGHT, zoom_level));
            const hover_editor_bottom: i32 = @as(i32, @intCast(wayland.height)) - hover_editor_margin - hover_tab_bar_h - 4;
            const tab_bar_y_hover: i32 = hover_editor_bottom + 4;
            if (wayland.mouse_y >= tab_bar_y_hover and wayland.mouse_y < tab_bar_y_hover + hover_tab_bar_h) {
                var hover_tab_x: i32 = hover_editor_left + scaleI(8, zoom_level); // +8 same as render
                const hover_tab_y: i32 = tab_bar_y_hover + scaleI(5, zoom_level); // +5 same as render
                const hover_tab_h: i32 = hover_tab_bar_h - scaleI(10, zoom_level); // -10 same as render

                for (0..tab_count) |hover_tab_idx| {
                    const name_len = tab_name_lens[hover_tab_idx];
                    if (name_len == 0) continue;

                    const text_width: i32 = @as(i32, @intCast(name_len)) * 8;
                    const hover_tab_w: i32 = @max(140, text_width + 70); // Same values as in render

                    if (wayland.mouse_x >= hover_tab_x and wayland.mouse_x < hover_tab_x + hover_tab_w and
                        wayland.mouse_y >= hover_tab_y and wayland.mouse_y < hover_tab_y + hover_tab_h)
                    {
                        new_tab_hovered = @intCast(hover_tab_idx);
                        // Check hover on close button
                        const close_x = hover_tab_x + hover_tab_w - 22;
                        if (wayland.mouse_x >= close_x and wayland.mouse_x < close_x + 18) {
                            new_tab_close_hovered = @intCast(hover_tab_idx);
                        }
                        break;
                    }
                    hover_tab_x += hover_tab_w + 4;
                }
            }
            if (new_tab_hovered != tab_hovered or new_tab_close_hovered != tab_close_hovered) {
                tab_hovered = new_tab_hovered;
                tab_close_hovered = new_tab_close_hovered;
                needs_redraw = true;
            }

            // Settings popup hover handling
            if (ui.settings_visible) {
                const popup_w: i32 = 400;
                const popup_h: i32 = 300;
                const popup_x: i32 = @divTrunc(@as(i32, @intCast(wayland.width)) - popup_w, 2);
                const popup_y: i32 = @divTrunc(@as(i32, @intCast(wayland.height)) - popup_h, 2);

                var new_tab_hover: i8 = -1;
                var new_checkbox_hover: bool = false;

                // Check if in popup
                if (mx >= popup_x and mx < popup_x + popup_w and my >= popup_y and my < popup_y + popup_h) {
                    // Tab hover check
                    const tab_y = popup_y + 52;
                    if (my >= tab_y and my < tab_y + 28) {
                        if (mx >= popup_x + 12 and mx < popup_x + 82) {
                            new_tab_hover = 0; // About
                        } else if (mx >= popup_x + 90 and mx < popup_x + 180) {
                            new_tab_hover = 1; // Additional
                        } else if (mx >= popup_x + 188 and mx < popup_x + 238) {
                            new_tab_hover = 2; // UI
                        }
                    }

                    // Checkbox hover check (only in Additional tab)
                    if (ui.settings_active_tab == 1) {
                        const content_y = popup_y + 100;
                        const checkbox_x = popup_x + 16;
                        if (my >= content_y and my < content_y + 18 and mx >= checkbox_x and mx < checkbox_x + 200) {
                            new_checkbox_hover = true;
                        }

                        // Set slider position before update
                        const slider_y = content_y + 60;
                        const slider_track_y = slider_y + 44;
                        const slider_x = popup_x + 16;
                        const slider_w: i32 = @as(i32, @intCast(popup_w)) - 80;
                        g_scroll_speed_slider.x = slider_x;
                        g_scroll_speed_slider.y = slider_track_y;
                        g_scroll_speed_slider.width = slider_w;
                        g_scroll_speed_slider.height = 20;

                        // Slider hover/drag update
                        const slider_changed = g_scroll_speed_slider.update(mx, my, wayland.mouse_pressed);
                        if (slider_changed) {
                            g_scroll_speed = g_scroll_speed_slider.value;
                            needs_redraw = true;
                        }
                        if (g_scroll_speed_slider.is_hovered or g_scroll_speed_slider.is_dragging) {
                            needs_redraw = true;
                        }
                    }

                    // UI tab slider
                    if (ui.settings_active_tab == 2) {
                        const content_y = popup_y + 100;
                        const slider_track_y = content_y + 44;
                        const slider_x = popup_x + 16;
                        const slider_w: i32 = @as(i32, @intCast(popup_w)) - 80;
                        g_line_visibility_slider.x = slider_x;
                        g_line_visibility_slider.y = slider_track_y;
                        g_line_visibility_slider.width = slider_w;
                        g_line_visibility_slider.height = 20;

                        const slider_changed = g_line_visibility_slider.update(mx, my, wayland.mouse_pressed);
                        if (slider_changed) {
                            g_line_visibility = g_line_visibility_slider.value;
                            needs_redraw = true;
                        }
                        if (g_line_visibility_slider.is_hovered or g_line_visibility_slider.is_dragging) {
                            needs_redraw = true;
                        }
                    }
                }

                // Close button hover
                const close_btn_x: i32 = popup_x + popup_w - 36;
                const close_btn_y: i32 = popup_y + 8;
                const new_close_hover = mx >= close_btn_x and mx < close_btn_x + 24 and
                    my >= close_btn_y and my < close_btn_y + 24;

                if (new_tab_hover != ui.settings_tab_hovered or new_checkbox_hover != ui.settings_checkbox_hovered or new_close_hover != ui.settings_close_hovered) {
                    ui.settings_tab_hovered = new_tab_hover;
                    ui.settings_checkbox_hovered = new_checkbox_hover;
                    ui.settings_close_hovered = new_close_hover;
                    needs_redraw = true;
                }

                // Set cursor
                if (new_tab_hover >= 0 or new_checkbox_hover or new_close_hover or g_scroll_speed_slider.is_hovered or g_scroll_speed_slider.is_dragging or g_line_visibility_slider.is_hovered or g_line_visibility_slider.is_dragging) {
                    wayland.setCursor(.pointer);
                } else {
                    wayland.setCursor(.default);
                }
            } else if (on_sidebar_edge) {
                wayland.setCursor(.resize_ew);
            } else if (on_tab_bar_edge) {
                wayland.setCursor(.resize_ns);
            } else if (in_vbar or in_hbar) {
                // On scrollbar - pointer cursor
                wayland.setCursor(.default);
            } else if (resize_edge != wl.RESIZE_NONE) {
                // Resize cursors
                const cursor_type: wl.CursorType = switch (resize_edge) {
                    wl.RESIZE_TOP, wl.RESIZE_BOTTOM => .resize_ns,
                    wl.RESIZE_LEFT, wl.RESIZE_RIGHT => .resize_ew,
                    wl.RESIZE_TOP_LEFT, wl.RESIZE_BOTTOM_RIGHT => .resize_nwse,
                    wl.RESIZE_TOP_RIGHT, wl.RESIZE_BOTTOM_LEFT => .resize_nesw,
                    else => .default,
                };
                wayland.setCursor(cursor_type);
            } else if (explorer_hovered >= 0) {
                // Over explorer item - pointer cursor
                wayland.setCursor(.pointer);
            } else if (tab_hovered >= 0) {
                // Over tab - pointer cursor
                wayland.setCursor(.pointer);
            } else if (wayland.mouse_y >= @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level)))) {
                // In text area
                const editor_left_cursor_h: i32 = if (ui.sidebar_visible) ui.sidebar_width + scaleI(10, zoom_level) else scaleI(10, zoom_level);
                if (wayland.mouse_x > editor_left_cursor_h + @as(i32, @intCast(scaleUI(GUTTER_WIDTH, zoom_level)))) {
                    wayland.setCursor(.text);
                } else {
                    wayland.setCursor(.default);
                }
            } else {
                // In titlebar - check buttons and menu
                const ctrl_width: i32 = scaleI(90, zoom_level);
                const ctrl_x: i32 = @as(i32, @intCast(wayland.width)) - ctrl_width - scaleI(8, zoom_level);
                const menu_block_end: i32 = scaleI(8 + 140, zoom_level);
                if (wayland.mouse_x >= ctrl_x or wayland.mouse_x < menu_block_end) {
                    wayland.setCursor(.pointer);
                } else {
                    wayland.setCursor(.default);
                }
            }

            needs_redraw = true;
        }

        // Handle mouse wheel scroll
        if (wayland.scroll_delta_x != 0 or wayland.scroll_delta_y != 0) {
            // Check if cursor is over sidebar
            const mouse_over_sidebar = ui.sidebar_visible and wayland.mouse_x < ui.sidebar_width and wayland.mouse_y > @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level)));

            if (mouse_over_sidebar and folder_file_count > 0) {
                // Scroll explorer
                const file_item_h: i32 = scaleI(28, zoom_level);
                const sidebar_margin_sc: i32 = scaleI(10, zoom_level);
                const sidebar_padding_sc: i32 = scaleI(16, zoom_level);
                const sidebar_h_sc: i32 = @as(i32, @intCast(wayland.height)) - @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - sidebar_margin_sc * 2;
                const files_area_h: i32 = sidebar_h_sc - sidebar_padding_sc * 2 - scaleI(32, zoom_level);
                const total_content_h: i32 = @as(i32, @intCast(folder_file_count)) * file_item_h;
                const max_explorer_scroll = @max(0, total_content_h - files_area_h);

                explorer_scroll = @max(0, @min(max_explorer_scroll, explorer_scroll + wayland.scroll_delta_y));
            } else {
                // Scroll editor
                const line_height: i32 = @intCast(gpu.lineHeight());
                const char_w: i32 = @intCast(gpu.charWidth());
                const content_h = @as(i32, @intCast(g_cached_line_count)) * line_height + line_height * 5;
                const visible_h: i32 = @as(i32, @intCast(wayland.height)) - @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - scaleI(30, zoom_level);
                const max_scroll_y = @max(0, content_h - visible_h);

                const max_line = g_cached_max_line_len;
                // Entire field moves together: gutter + padding + text + margin
                const content_w = @as(i32, @intCast(scaleUI(GUTTER_WIDTH, zoom_level))) + scaleI(12, zoom_level) + @as(i32, @intCast(max_line)) * char_w + char_w * 10;
                // Account for sidebar when calculating visible width
                const editor_margin_scroll: i32 = scaleI(10, zoom_level);
                const editor_left_scroll: i32 = if (ui.sidebar_visible) ui.sidebar_width + editor_margin_scroll else editor_margin_scroll;
                const visible_w: i32 = @as(i32, @intCast(wayland.width)) - editor_margin_scroll - editor_left_scroll - scaleI(20, zoom_level);
                const max_scroll_x = @max(0, content_w - visible_w);

                // Apply speed multiplier to wheel scroll
                const scroll_delta_x_scaled: i32 = @intFromFloat(@as(f32, @floatFromInt(wayland.scroll_delta_x)) * g_scroll_speed);
                const scroll_delta_y_scaled: i32 = @intFromFloat(@as(f32, @floatFromInt(wayland.scroll_delta_y)) * g_scroll_speed);

                scroll_x = @max(0, @min(max_scroll_x, scroll_x + scroll_delta_x_scaled));

                if (g_scroll_inertia) {
                    // Inertia: add to velocity
                    ui.scroll_velocity_y += @as(f32, @floatFromInt(scroll_delta_y_scaled)) * 0.8;
                } else {
                    // No inertia: direct scroll
                    scroll_y = @max(0, @min(max_scroll_y, scroll_y + scroll_delta_y_scaled));
                }
            }
            wayland.scroll_delta_x = 0;
            wayland.scroll_delta_y = 0;
            needs_redraw = true;
        }

        // Continuous auto-scroll during drag selection (works without mouse movement)
        // Use delta time for stable speed
        const delta_time: i64 = if (g_last_frame_time > 0) @max(1, now - g_last_frame_time) else 16;
        g_last_frame_time = now;

        if (selection.dragging) {
            const titlebar_h_drag: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level));
            const tab_bar_h_drag: i32 = @intCast(scaleUI(TAB_BAR_HEIGHT, zoom_level));
            const editor_margin_drag: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
            const editor_left_drag: i32 = if (ui.sidebar_visible) ui.sidebar_width + editor_margin_drag else editor_margin_drag;
            const editor_top_drag: i32 = titlebar_h_drag + editor_margin_drag;
            const editor_bottom_drag: i32 = @as(i32, @intCast(wayland.height)) - editor_margin_drag - tab_bar_h_drag - 4;
            const editor_right_drag: i32 = @as(i32, @intCast(wayland.width)) - editor_margin_drag - 18;

            const line_height_drag: i32 = @intCast(gpu.lineHeight());
            const char_width_drag: i32 = @intCast(gpu.charWidth());
            const gutter_w_drag: i32 = @intCast(scaleUI(GUTTER_WIDTH, zoom_level));

            // Base scroll speed (lines/chars per second) * speed setting
            const speed_mult = g_scroll_speed;
            const base_speed_v: i32 = @intFromFloat(8.0 * speed_mult);  // Min 8 lines/sec * multiplier
            const max_speed_v: i32 = @intFromFloat(60.0 * speed_mult);  // Max 60 lines/sec * multiplier
            const base_speed_h: i32 = @intFromFloat(15.0 * speed_mult); // Min 15 chars/sec * multiplier
            const max_speed_h: i32 = @intFromFloat(100.0 * speed_mult); // Max 100 chars/sec * multiplier

            // Max distance for acceleration (pixels from edge)
            const max_distance: i32 = 200;

            var did_scroll = false;
            const dt_factor: i32 = @intCast(@min(100, delta_time));

            // Vertical auto-scroll with distance-based acceleration
            if (wayland.mouse_y < editor_top_drag) {
                // Distance from top edge (farther up = faster)
                const distance: i32 = @min(max_distance, editor_top_drag - wayland.mouse_y);
                const speed_factor: i32 = base_speed_v + @divTrunc((max_speed_v - base_speed_v) * distance, max_distance);
                const scroll_amount: i32 = @max(1, @divTrunc(line_height_drag * speed_factor * dt_factor, 1000));
                scroll_y = @max(0, scroll_y - scroll_amount);
                did_scroll = true;
            } else if (wayland.mouse_y > editor_bottom_drag) {
                // Distance from bottom edge (farther down = faster)
                const distance: i32 = @min(max_distance, wayland.mouse_y - editor_bottom_drag);
                const speed_factor: i32 = base_speed_v + @divTrunc((max_speed_v - base_speed_v) * distance, max_distance);
                const scroll_amount: i32 = @max(1, @divTrunc(line_height_drag * speed_factor * dt_factor, 1000));
                const content_height_drag = @as(i32, @intCast(g_cached_line_count)) * line_height_drag;
                const visible_height_drag = editor_bottom_drag - editor_top_drag;
                const max_scroll_drag = @max(0, content_height_drag - visible_height_drag);
                scroll_y = @min(max_scroll_drag, scroll_y + scroll_amount);
                did_scroll = true;
            }

            // Horizontal auto-scroll with distance-based acceleration
            const left_edge: i32 = editor_left_drag + gutter_w_drag;
            if (wayland.mouse_x < left_edge) {
                const distance: i32 = @min(max_distance, left_edge - wayland.mouse_x);
                const speed_factor: i32 = base_speed_h + @divTrunc((max_speed_h - base_speed_h) * distance, max_distance);
                const scroll_amount: i32 = @max(1, @divTrunc(char_width_drag * speed_factor * dt_factor, 1000));
                scroll_x = @max(0, scroll_x - scroll_amount);
                did_scroll = true;
            } else if (wayland.mouse_x > editor_right_drag) {
                const distance: i32 = @min(max_distance, wayland.mouse_x - editor_right_drag);
                const speed_factor: i32 = base_speed_h + @divTrunc((max_speed_h - base_speed_h) * distance, max_distance);
                const scroll_amount: i32 = @max(1, @divTrunc(char_width_drag * speed_factor * dt_factor, 1000));
                const content_width_drag = @as(i32, @intCast(g_cached_max_line_len)) * char_width_drag;
                const visible_width_drag = editor_right_drag - editor_left_drag;
                const max_scroll_x_drag = @max(0, content_width_drag - visible_width_drag);
                scroll_x = @min(max_scroll_x_drag, scroll_x + scroll_amount);
                did_scroll = true;
            }

            // Update cursor position if scrolled
            if (did_scroll) {
                // Don't rebuild index - use existing (valid while text unchanged)
                const drag_pos = screenToTextPos(&gpu, &text_buffer, wayland.mouse_x, wayland.mouse_y, scroll_x, scroll_y, ui.sidebar_visible, ui.sidebar_width);
                if (drag_pos) |pos| {
                    text_buffer.moveCursor(pos);
                }
                needs_redraw = true;
            }
        }

        // Apply scroll inertia
        if (g_scroll_inertia and @abs(ui.scroll_velocity_y) > 0.5) {
            const line_height_inertia: i32 = @intCast(gpu.lineHeight());
            const content_h_inertia = @as(i32, @intCast(g_cached_line_count)) * line_height_inertia + line_height_inertia * 5;
            const visible_h_inertia: i32 = @as(i32, @intCast(wayland.height)) - @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - scaleI(30, zoom_level);
            const max_scroll_y_inertia = @max(0, content_h_inertia - visible_h_inertia);

            scroll_y = @max(0, @min(max_scroll_y_inertia, scroll_y + @as(i32, @intFromFloat(ui.scroll_velocity_y))));
            ui.scroll_velocity_y *= 0.92; // Friction
            if (@abs(ui.scroll_velocity_y) < 0.5) ui.scroll_velocity_y = 0;
            needs_redraw = true;
        }

        // Handle mouse events
        for (wayland.pollMouseEvents()) |event| {
            if (event.button == wl.BTN_LEFT) {
                if (event.pressed) {
                    // Handle confirm dialog clicks first (if visible)
                    if (g_confirm_dialog.visible) {
                        const escape_pressed = false;
                        const result = g_confirm_dialog.update(event.x, event.y, true, escape_pressed);
                        if (result == .confirmed) {
                            // Check for file/folder delete action first
                            if (g_pending_delete_action) {
                                if (g_pending_delete_idx < folder_file_count) {
                                    const target_path = folder_full_path[g_pending_delete_idx][0..folder_full_path_lens[g_pending_delete_idx]];
                                    const is_directory = folder_is_dir[g_pending_delete_idx];
                                    deleteFileOrFolder(current_folder_path[0..current_folder_len], target_path, is_directory, &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    explorer_selected = -1; // Deselect after deletion
                                }
                                g_pending_delete_action = false;
                            } else {
                                // Perform the pending plugin action
                                switch (g_pending_plugin_action) {
                                    .disable => {
                                        plugins.disablePlugin(g_pending_plugin_path[0..g_pending_plugin_path_len]) catch |e| logger.warn("Operation failed: {}", .{e});
                                    },
                                    .uninstall => {
                                        plugins.uninstallPlugin(g_pending_plugin_path[0..g_pending_plugin_path_len]) catch |e| logger.warn("Operation failed: {}", .{e});
                                        // Close the plugin tab
                                        if (tab_count > 1 and g_pending_plugin_tab < tab_count) {
                                            var close_i = g_pending_plugin_tab;
                                            while (close_i + 1 < tab_count) : (close_i += 1) {
                                                tab_paths[close_i] = tab_paths[close_i + 1];
                                                tab_path_lens[close_i] = tab_path_lens[close_i + 1];
                                                tab_modified[close_i] = tab_modified[close_i + 1];
                                                tab_is_plugin[close_i] = tab_is_plugin[close_i + 1];
                                                tab_plugin_idx[close_i] = tab_plugin_idx[close_i + 1];
                                            }
                                            tab_count -= 1;
                                            if (active_tab >= tab_count) active_tab = tab_count - 1;
                                        }
                                    },
                                    else => {},
                                }
                                g_pending_plugin_action = .none;
                            }
                        } else if (result == .cancelled) {
                            g_pending_plugin_action = .none;
                            g_pending_delete_action = false;
                        }
                        needs_redraw = true;
                        continue; // Don't process other clicks while dialog is open
                    }

                    // Remove focus from editor on any click
                    // (focus returns if clicked in editor area)
                    editor_focused = false;

                    // Cancel rename mode on any click outside rename area
                    if (g_rename_mode) {
                        g_rename_mode = false;
                        needs_redraw = true;
                    }

                    // Check resize edge (8px from edge)
                    const resize_edge = getResizeEdge(event.x, event.y, wayland.width, wayland.height, zoom_level);

                    // Check scrollbar zone
                    const scrollbar_zone: i32 = 18;
                    const ww: i32 = @intCast(wayland.width);
                    const wh: i32 = @intCast(wayland.height);
                    // Account for sidebar for horizontal scrollbar
                    const editor_margin_click: i32 = scaleI(10, zoom_level);
                    const editor_left_click: i32 = if (ui.sidebar_visible) ui.sidebar_width + editor_margin_click else editor_margin_click;
                    const titlebar_h_click: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level));
                    const in_vbar = event.x >= ww - scrollbar_zone and event.y > titlebar_h_click and event.y < wh - scrollbar_zone;
                    const in_hbar = event.y >= wh - scrollbar_zone and event.x > editor_left_click and event.x < ww - scrollbar_zone;

                    // Check sidebar edge for resize (visual edge = ui.sidebar_width - 6)
                    const sidebar_edge = ui.sidebar_width - scaleI(6, zoom_level);
                    const on_sidebar_edge = ui.sidebar_visible and
                        event.x >= sidebar_edge - scaleI(4, zoom_level) and event.x <= sidebar_edge + scaleI(8, zoom_level) and
                        event.y > titlebar_h_click;

                    // Check tab bar edge for resize
                    const tb_margin: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                    const tb_left: i32 = editor_left_click;
                    const tb_right: i32 = ww - tb_margin;
                    const tb_top: i32 = wh - tb_margin - g_tab_bar_height;
                    const on_tab_bar_edge = event.y >= tb_top - 4 and event.y <= tb_top + 4 and
                        event.x >= tb_left and event.x <= tb_right;

                    if (on_sidebar_edge) {
                        ui.dragging_sidebar = true;
                    } else if (on_tab_bar_edge) {
                        ui.dragging_tab_bar = true;
                        ui.drag_start_scroll = g_tab_bar_height;
                        ui.drag_start_mouse = event.y;
                    } else if (in_vbar) {
                        // Begin vertical scrollbar drag
                        ui.dragging_vbar = true;
                        ui.drag_start_scroll = scroll_y;
                        ui.drag_start_mouse = event.y;
                    } else if (in_hbar) {
                        // Begin horizontal scrollbar drag
                        ui.dragging_hbar = true;
                        ui.drag_start_scroll = scroll_x;
                        ui.drag_start_mouse = event.x;
                    } else if (resize_edge != wl.RESIZE_NONE) {
                        wayland.startResize(resize_edge);
                    } else if (ui.settings_visible) {
                        // Settings popup click handling
                        const popup_w: i32 = 400;
                        const popup_h: i32 = 300;
                        const popup_x: i32 = @divTrunc(@as(i32, @intCast(wayland.width)) - popup_w, 2);
                        const popup_y: i32 = @divTrunc(@as(i32, @intCast(wayland.height)) - popup_h, 2);

                        // Close button area (updated for new design)
                        const close_btn_x: i32 = popup_x + popup_w - 36;
                        const close_btn_y: i32 = popup_y + 8;
                        if (event.x >= close_btn_x and event.x < close_btn_x + 24 and
                            event.y >= close_btn_y and event.y < close_btn_y + 24)
                        {
                            ui.settings_visible = false;
                            needs_redraw = true;
                        }

                        // Tab clicks
                        const tab_y = popup_y + 52;
                        if (event.y >= tab_y and event.y < tab_y + 28) {
                            // About tab
                            if (event.x >= popup_x + 12 and event.x < popup_x + 82) {
                                ui.settings_active_tab = 0;
                                needs_redraw = true;
                            }
                            // Additional tab
                            else if (event.x >= popup_x + 90 and event.x < popup_x + 180) {
                                ui.settings_active_tab = 1;
                                needs_redraw = true;
                            }
                            // UI tab
                            else if (event.x >= popup_x + 188 and event.x < popup_x + 238) {
                                ui.settings_active_tab = 2;
                                needs_redraw = true;
                            }
                        }

                        // Checkbox clicks (only in Additional tab)
                        if (ui.settings_active_tab == 1) {
                            const content_y = popup_y + 100;
                            const checkbox_x = popup_x + 16;
                            const checkbox_y = content_y;
                            const checkbox_size: i32 = 18;
                            // Clickable area includes checkbox and label
                            if (event.y >= checkbox_y and event.y < checkbox_y + checkbox_size and
                                event.x >= checkbox_x and event.x < checkbox_x + 200)
                            {
                                g_scroll_inertia = !g_scroll_inertia;
                                ui.scroll_velocity_y = 0; // Reset velocity on toggle
                                saveSettings(); // Save to ~/.mncode
                                needs_redraw = true;
                            }

                            // Slider click - start drag
                            if (g_scroll_speed_slider.update(event.x, event.y, true)) {
                                g_scroll_speed = g_scroll_speed_slider.value;
                                saveSettings();
                                needs_redraw = true;
                            }
                        }

                        // UI tab slider
                        if (ui.settings_active_tab == 2) {
                            if (g_line_visibility_slider.update(event.x, event.y, true)) {
                                g_line_visibility = g_line_visibility_slider.value;
                                saveSettings();
                                needs_redraw = true;
                            }
                        }

                        // Click outside popup closes it
                        if (event.x < popup_x or event.x > popup_x + popup_w or
                            event.y < popup_y or event.y > popup_y + popup_h)
                        {
                            ui.settings_visible = false;
                            needs_redraw = true;
                        }
                    } else if (ui.menu_open >= 0) {
                        // Dropdown menu click handling
                        const menu_block_x: i32 = scaleI(8, zoom_level);
                        const menu_block_y: i32 = @divTrunc(@as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - scaleI(26, zoom_level), 2);
                        const menu_section_w: i32 = scaleI(46, zoom_level);
                        const dropdown_x: i32 = menu_block_x + ui.menu_open * menu_section_w;
                        const dropdown_y: i32 = menu_block_y + scaleI(26, zoom_level) + scaleI(2, zoom_level);
                        const dropdown_w: i32 = scaleI(160, zoom_level);

                        // Number of items in each menu
                        const items_count: i32 = if (ui.menu_open == 0) 4 else if (ui.menu_open == 1) 7 else 10;
                        const dropdown_h: i32 = items_count * scaleI(28, zoom_level) + scaleI(8, zoom_level);

                        const in_dropdown = event.x >= dropdown_x and event.x < dropdown_x + dropdown_w and
                            event.y >= dropdown_y and event.y < dropdown_y + dropdown_h;

                        // Check if clicked on menu block (to switch menus)
                        const in_menu_block_click = event.x >= menu_block_x and event.x < menu_block_x + scaleI(140, zoom_level) and
                            event.y >= menu_block_y and event.y < menu_block_y + scaleI(26, zoom_level);

                        if (in_dropdown) {
                            // Clicked on dropdown item
                            const rel_y = event.y - dropdown_y - scaleI(4, zoom_level);
                            const item_idx: i32 = @divTrunc(rel_y, scaleI(28, zoom_level));

                            if (ui.menu_open == 0) {
                                // File menu
                                if (item_idx == 0) {
                                    // New - new tab
                                    if (tab_count < MAX_TABS) {
                                        // Save current scroll position
                                        tab_scroll_x[active_tab] = scroll_x;
                                        tab_scroll_y[active_tab] = scroll_y;

                                        // Clear buffer for new tab
                                        text_buffer.clear();
                                        selection.clear();
                                        scroll_x = 0;
                                        scroll_y = 0;

                                        // Create new tab
                                        const new_name = "Untitled";
                                        @memcpy(tab_names[tab_count][0..new_name.len], new_name);
                                        tab_name_lens[tab_count] = new_name.len;
                                        tab_path_lens[tab_count] = 0;
                                        tab_is_plugin[tab_count] = false;
                                        tab_modified[tab_count] = false;
                                        tab_scroll_x[tab_count] = 0;
                                        tab_scroll_y[tab_count] = 0;
                                        active_tab = tab_count;
                                        tab_count += 1;
                                    }
                                } else if (item_idx == 1) {
                                    // Open File - open file via zenity
                                    openFileDialog(&text_buffer, &tab_names, &tab_name_lens, &tab_paths, &tab_path_lens, &tab_modified, &tab_count, &active_tab, &tab_scroll_x, &tab_scroll_y, &scroll_x, &scroll_y, &selection, &tab_original_content, &tab_original_lens, &undo_count, &redo_count, allocator);
                                } else if (item_idx == 2) {
                                    // Open Folder
                                    openFolderDialog(&current_folder_path, &current_folder_len, &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    ui.sidebar_visible = true;
                                } else if (item_idx == 3) {
                                    // Save
                                    if (tab_path_lens[active_tab] > 0) {
                                        saveFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                                        tab_modified[active_tab] = false;
                                    } else {
                                        // No path - call Save As
                                        saveFileDialogTab(&text_buffer, &tab_paths, &tab_path_lens, &tab_names, &tab_name_lens, &tab_modified, active_tab);
                                    }
                                } else if (item_idx == 4) {
                                    // Save As
                                    saveFileDialogTab(&text_buffer, &tab_paths, &tab_path_lens, &tab_names, &tab_name_lens, &tab_modified, active_tab);
                                } else if (item_idx == 5) {
                                    // Close Tab
                                    if (tab_count > 1) {
                                        // Delete current tab
                                        var close_i: usize = active_tab;
                                        while (close_i + 1 < tab_count) : (close_i += 1) {
                                            tab_names[close_i] = tab_names[close_i + 1];
                                            tab_name_lens[close_i] = tab_name_lens[close_i + 1];
                                            tab_paths[close_i] = tab_paths[close_i + 1];
                                            tab_path_lens[close_i] = tab_path_lens[close_i + 1];
                                            tab_modified[close_i] = tab_modified[close_i + 1];
                                            tab_scroll_x[close_i] = tab_scroll_x[close_i + 1];
                                            tab_scroll_y[close_i] = tab_scroll_y[close_i + 1];
                                        }
                                        tab_count -= 1;
                                        if (active_tab >= tab_count) {
                                            active_tab = tab_count - 1;
                                        }
                                        // Load active tab contents
                                        text_buffer.clear();
                                        if (tab_path_lens[active_tab] > 0) {
                                            loadFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                                        }
                                        scroll_x = tab_scroll_x[active_tab];
                                        scroll_y = tab_scroll_y[active_tab];
                                        selection.clear();
                                    } else {
                                        // Last tab - just clear
                                        text_buffer.clear();
                                        const new_name = "Untitled";
                                        @memcpy(tab_names[0][0..new_name.len], new_name);
                                        tab_name_lens[0] = new_name.len;
                                        tab_path_lens[0] = 0;
                                        tab_modified[0] = false;
                                        scroll_x = 0;
                                        scroll_y = 0;
                                        selection.clear();
                                    }
                                }
                            } else if (ui.menu_open == 1) {
                                // Edit menu
                                if (item_idx == 0) {
                                    // Undo - not yet implemented
                                } else if (item_idx == 1) {
                                    // Redo - not yet implemented
                                } else if (item_idx == 2) {
                                    // Cut - uses system clipboard
                                    if (selection.getRange(text_buffer.cursor())) |range| {
                                        copyToClipboardSystem(&text_buffer, range.start, range.end, &wayland);
                                        deleteRange(&text_buffer, range.start, range.end);
                                        selection.clear();
                                    }
                                } else if (item_idx == 3) {
                                    // Copy - uses system clipboard
                                    if (selection.getRange(text_buffer.cursor())) |range| {
                                        copyToClipboardSystem(&text_buffer, range.start, range.end, &wayland);
                                    }
                                } else if (item_idx == 4) {
                                    // Paste - uses system clipboard
                                    if (selection.getRange(text_buffer.cursor())) |range| {
                                        deleteRange(&text_buffer, range.start, range.end);
                                        selection.clear();
                                    }
                                    var paste_buf: [64 * 1024]u8 = undefined;
                                    if (wayland.pasteFromClipboard(&paste_buf)) |data| {
                                        text_buffer.insertSlice(data) catch |e| logger.warn("Operation failed: {}", .{e});
                                    } else if (clipboard_len > 0) {
                                        text_buffer.insertSlice(clipboard_buffer[0..clipboard_len]) catch |e| logger.warn("Operation failed: {}", .{e});
                                    }
                                } else if (item_idx == 5) {
                                    // Search
                                    search_visible = true;
                                    search_field.moveCursorEnd();
                                    editor_focused = false; // Focus on search
                                } else if (item_idx == 6) {
                                    // Settings
                                    ui.settings_visible = true;
                                }
                            } else if (ui.menu_open == 2) {
                                // View menu
                                if (item_idx == 0) {
                                    // Toggle Explorer
                                    ui.sidebar_visible = !ui.sidebar_visible;
                                } else if (item_idx == 1) {
                                    // Zoom In
                                    zoom_level = @min(ZOOM_MAX, zoom_level + ZOOM_STEP);
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 2) {
                                    // Zoom Out
                                    zoom_level = @max(ZOOM_MIN, zoom_level - ZOOM_STEP);
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 3) {
                                    // Reset Zoom
                                    zoom_level = 1.0;
                                    gpu.setZoom(zoom_level);
                                    // idx 4 is separator, skip
                                } else if (item_idx == 5) {
                                    // Zoom 75%
                                    zoom_level = 0.75;
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 6) {
                                    // Zoom 90%
                                    zoom_level = 0.9;
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 7) {
                                    // Zoom 100%
                                    zoom_level = 1.0;
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 8) {
                                    // Zoom 125%
                                    zoom_level = 1.25;
                                    gpu.setZoom(zoom_level);
                                } else if (item_idx == 9) {
                                    // Zoom 150%
                                    zoom_level = 1.5;
                                    gpu.setZoom(zoom_level);
                                }
                            }

                            ui.menu_open = -1;
                            ui.menu_item_hover = -1;
                            needs_redraw = true;
                        } else if (in_menu_block_click) {
                            // Switch to different menu
                            const new_menu = @divTrunc(event.x - menu_block_x, menu_section_w);
                            if (new_menu == ui.menu_open) {
                                ui.menu_open = -1;
                            } else {
                                ui.menu_open = @min(2, new_menu);
                            }
                            ui.menu_item_hover = -1;
                            needs_redraw = true;
                        } else {
                            // Clicked outside - close menu
                            ui.menu_open = -1;
                            ui.menu_item_hover = -1;
                            needs_redraw = true;
                        }
                    } else if (event.y >= 0 and event.y < @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level)))) {
                        // Titlebar click handling
                        // Check window buttons (right, unified block)
                        const ctrl_width: i32 = scaleI(90, zoom_level);
                        const ctrl_height: i32 = scaleI(26, zoom_level);
                        const ctrl_x: i32 = @as(i32, @intCast(wayland.width)) - ctrl_width - scaleI(8, zoom_level);
                        const ctrl_y: i32 = @divTrunc(@as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - ctrl_height, 2);
                        const section_width: i32 = @divTrunc(ctrl_width, 3);

                        const in_ctrl = event.x >= ctrl_x and event.x < ctrl_x + ctrl_width and
                            event.y >= ctrl_y and event.y < ctrl_y + ctrl_height;

                        // Check menu block
                        const menu_block_x: i32 = scaleI(8, zoom_level);
                        const menu_block_y: i32 = @divTrunc(@as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level))) - scaleI(26, zoom_level), 2);
                        const in_menu_block_click = event.x >= menu_block_x and event.x < menu_block_x + scaleI(140, zoom_level) and
                            event.y >= menu_block_y and event.y < menu_block_y + scaleI(26, zoom_level);

                        if (in_ctrl) {
                            const rel_x = event.x - ctrl_x;
                            const section = @divTrunc(rel_x, section_width);
                            if (section == 0) {
                                // Minimize
                                wayland.minimize();
                            } else if (section == 1) {
                                // Maximize
                                wayland.toggleMaximize();
                            } else if (section == 2) {
                                // Close
                                wayland.running = false;
                                break;
                            }
                        } else if (in_menu_block_click) {
                            // Open menu
                            const menu_section_w: i32 = scaleI(46, zoom_level);
                            ui.menu_open = @min(2, @divTrunc(event.x - menu_block_x, menu_section_w));
                            ui.menu_item_hover = -1;
                            needs_redraw = true;
                        } else {
                            // Drag via rest of titlebar
                            wayland.startMove();
                        }
                    } else if (ui.sidebar_visible and event.x < ui.sidebar_width and event.y > @as(i32, @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level)))) {
                        // Click in sidebar
                        const sidebar_margin: i32 = scaleI(10, zoom_level);
                        const titlebar_h_sb: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level));
                        const sidebar_y: i32 = titlebar_h_sb + sidebar_margin;

                        // Check click on sidebar tabs
                        const stab_y_click: i32 = sidebar_y + scaleI(8, zoom_level);
                        const stab_h_click: i32 = scaleI(24, zoom_level);
                        if (event.y >= stab_y_click and event.y < stab_y_click + stab_h_click) {
                            const stab_w_click: i32 = scaleI(32, zoom_level); // Square tab width
                            var check_x_click: i32 = sidebar_margin + scaleI(8, zoom_level);
                            for (0..4) |tab_i| { // 4 tabs: Explorer, Search, Git, Plugins
                                if (event.x >= check_x_click and event.x < check_x_click + stab_w_click) {
                                    ui.sidebar_active_tab = tab_i;
                                    needs_redraw = true;
                                    break;
                                }
                                check_x_click += stab_w_click + scaleI(4, zoom_level);
                            }
                        }

                        // Click on Open Folder button (when no folder is open)
                        if (ui.sidebar_active_tab == 0 and current_folder_len == 0) {
                            const sidebar_h_click = wayland.height - scaleUI(TITLEBAR_HEIGHT, zoom_level) - @as(u32, @intCast(sidebar_margin)) * 2;
                            const btn_y_click: i32 = sidebar_y + @as(i32, @intCast(sidebar_h_click / 2)) - scaleI(20, zoom_level);
                            const btn_x_click: i32 = sidebar_margin + scaleI(10, zoom_level);
                            const btn_w_click: i32 = @as(i32, @intCast(ui.sidebar_width)) - scaleI(20, zoom_level);
                            const btn_h_click: i32 = scaleI(36, zoom_level);
                            if (event.x >= btn_x_click and event.x < btn_x_click + btn_w_click and
                                event.y >= btn_y_click and event.y < btn_y_click + btn_h_click)
                            {
                                openFolderDialog(&current_folder_path, &current_folder_len, &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                needs_redraw = true;
                            }
                        }

                        // Click on file manager buttons (New File, New Folder, Delete)
                        if (ui.sidebar_active_tab == 0 and current_folder_len > 0) {
                            const sidebar_x_fm: i32 = sidebar_margin;
                            const sidebar_w_fm: i32 = ui.sidebar_width - sidebar_margin * 2;
                            const header_y_fm: i32 = sidebar_y + scaleI(8 + 24 + 12, zoom_level);
                            const btn_size_fm: i32 = scaleI(22, zoom_level);
                            const btn_spacing_fm: i32 = scaleI(2, zoom_level);
                            const sidebar_padding_fm: i32 = scaleI(10, zoom_level);
                            const btns_y_fm: i32 = header_y_fm - scaleI(4, zoom_level);
                            var btn_x_fm: i32 = sidebar_x_fm + sidebar_w_fm - sidebar_padding_fm - btn_size_fm * 3 - btn_spacing_fm * 2;

                            if (event.y >= btns_y_fm and event.y < btns_y_fm + btn_size_fm) {
                                // New File button
                                if (event.x >= btn_x_fm and event.x < btn_x_fm + btn_size_fm) {
                                    // Create new file in current folder
                                    createNewFile(current_folder_path[0..current_folder_len], &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    needs_redraw = true;
                                }
                                btn_x_fm += btn_size_fm + btn_spacing_fm;

                                // New Folder button
                                if (event.x >= btn_x_fm and event.x < btn_x_fm + btn_size_fm) {
                                    // Create new folder in current folder
                                    createNewFolder(current_folder_path[0..current_folder_len], &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    needs_redraw = true;
                                }
                                btn_x_fm += btn_size_fm + btn_spacing_fm;

                                // Delete button (only if something selected)
                                if (explorer_selected >= 0 and event.x >= btn_x_fm and event.x < btn_x_fm + btn_size_fm) {
                                    const sel_idx: usize = @intCast(explorer_selected);
                                    if (sel_idx < folder_file_count) {
                                        // Show confirm dialog for deletion
                                        const file_name = folder_files[sel_idx][0..folder_file_lens[sel_idx]];
                                        var msg_buf: [256]u8 = undefined;
                                        const msg = std.fmt.bufPrint(&msg_buf, "Delete \"{s}\"?", .{file_name}) catch "Delete this item?";
                                        g_confirm_dialog.show("Confirm Delete", msg, "Delete", "Cancel", true, wayland.width, wayland.height);
                                        g_pending_plugin_action = .none; // Reset plugin action
                                        g_pending_delete_idx = sel_idx;
                                        g_pending_delete_action = true;
                                        needs_redraw = true;
                                    }
                                }
                            }
                        }

                        // Click on files only if Files tab is active
                        const file_start_y: i32 = sidebar_y + scaleI(8 + 24 + 12 + 20, zoom_level); // tabs + separator + header
                        const file_item_h: i32 = scaleI(28, zoom_level);

                        if (ui.sidebar_active_tab == 0 and event.y >= file_start_y and folder_file_count > 0) {
                            const rel_y = event.y - file_start_y + explorer_scroll;
                            const clicked_idx: i32 = @divTrunc(rel_y, file_item_h);
                            if (clicked_idx >= 0 and clicked_idx < @as(i32, @intCast(folder_file_count))) {
                                const idx: usize = @intCast(clicked_idx);

                                // Check for double-click (for rename)
                                const current_time = std.time.milliTimestamp();
                                const double_click_threshold: i64 = 400; // ms

                                if (clicked_idx == g_last_click_idx and
                                    current_time - g_last_click_time < double_click_threshold and
                                    !g_rename_mode)
                                {
                                    // Double-click detected - enter rename mode
                                    g_rename_mode = true;
                                    g_rename_idx = idx;
                                    // Initialize with current name
                                    const name = folder_files[idx][0..folder_file_lens[idx]];
                                    g_rename_field.clear();
                                    for (name) |ch| {
                                        _ = g_rename_field.insert(ch);
                                    }
                                    needs_redraw = true;
                                    g_last_click_idx = -1; // Reset to prevent triple-click
                                    continue;
                                }

                                g_last_click_time = current_time;
                                g_last_click_idx = clicked_idx;
                                explorer_selected = clicked_idx;

                                if (folder_is_dir[idx]) {
                                    // Click on folder - expand/collapse
                                    folder_expanded[idx] = !folder_expanded[idx];

                                    if (folder_expanded[idx]) {
                                        // Expand - load child elements
                                        expandFolder(idx, &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    } else {
                                        // Collapse - hide child elements
                                        collapseFolder(idx, &folder_files, &folder_file_lens, &folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, &folder_parent, &folder_full_path, &folder_full_path_lens);
                                    }
                                } else {
                                    // Click on file - open in tab
                                    const path_len = folder_full_path_lens[idx];
                                    if (path_len > 0 and path_len < 512) {
                                        // Check if already open
                                        var found_tab: i32 = -1;
                                        for (0..tab_count) |check_i| {
                                            if (tab_path_lens[check_i] == path_len) {
                                                var same = true;
                                                for (0..path_len) |char_i| {
                                                    if (tab_paths[check_i][char_i] != folder_full_path[idx][char_i]) {
                                                        same = false;
                                                        break;
                                                    }
                                                }
                                                if (same) {
                                                    found_tab = @intCast(check_i);
                                                    break;
                                                }
                                            }
                                        }

                                        if (found_tab >= 0) {
                                            // Switch to existing tab
                                            tab_scroll_x[active_tab] = scroll_x;
                                            tab_scroll_y[active_tab] = scroll_y;
                                            active_tab = @intCast(found_tab);
                                            text_buffer.clear();
                                            loadFile(folder_full_path[idx][0..path_len], &text_buffer);
                                            scroll_x = tab_scroll_x[active_tab];
                                            scroll_y = tab_scroll_y[active_tab];
                                        } else if (tab_count < MAX_TABS) {
                                            // Create new tab
                                            tab_scroll_x[active_tab] = scroll_x;
                                            tab_scroll_y[active_tab] = scroll_y;

                                            const new_idx = tab_count;
                                            @memcpy(tab_paths[new_idx][0..path_len], folder_full_path[idx][0..path_len]);
                                            tab_path_lens[new_idx] = path_len;

                                            // File name
                                            const name_len = folder_file_lens[idx];
                                            const capped_name_len = @min(name_len, 63);
                                            @memcpy(tab_names[new_idx][0..capped_name_len], folder_files[idx][0..capped_name_len]);
                                            tab_name_lens[new_idx] = capped_name_len;
                                            tab_modified[new_idx] = false;
                                            tab_scroll_x[new_idx] = 0;
                                            tab_scroll_y[new_idx] = 0;

                                            active_tab = new_idx;
                                            tab_count += 1;

                                            text_buffer.clear();
                                            loadFile(folder_full_path[idx][0..path_len], &text_buffer);
                                            scroll_x = 0;
                                            scroll_y = 0;

                                            // Save original content for modification tracking
                                            const content_len = @min(text_buffer.len(), MAX_UNDO_SIZE);
                                            if (text_buffer.getText(allocator)) |txt| {
                                                @memcpy(tab_original_content[new_idx][0..content_len], txt[0..content_len]);
                                                tab_original_lens[new_idx] = content_len;
                                                allocator.free(txt);
                                            } else |_| {
                                                tab_original_lens[new_idx] = 0;
                                            }
                                            undo_count = 0;
                                            redo_count = 0;
                                        }
                                        selection.clear();
                                    }
                                }
                                needs_redraw = true;
                            }
                        }

                        // Click on Search tab
                        if (ui.sidebar_active_tab == 1) {
                            const search_area_y_click: i32 = sidebar_y + scaleI(8 + 24 + 12 + 20, zoom_level);
                            const input_y_click: i32 = search_area_y_click + 10;
                            const input_h_click: i32 = 28;

                            // Check click on search input
                            if (event.y >= input_y_click and event.y < input_y_click + input_h_click) {
                                g_search_active = true;
                                needs_redraw = true;
                            } else {
                                // Check click on search results
                                const results_y_click: i32 = input_y_click + input_h_click + 12 + 20;
                                const result_item_h: i32 = 48;

                                if (g_search_result_count > 0 and event.y >= results_y_click) {
                                    const rel_y = event.y - results_y_click;
                                    const clicked_idx = @divTrunc(rel_y, result_item_h) + g_search_result_scroll;
                                    if (clicked_idx >= 0 and clicked_idx < @as(i32, @intCast(g_search_result_count))) {
                                        // Open file at this result
                                        const result = &g_search_results[@intCast(clicked_idx)];
                                        const file_path = result.file_path[0..result.file_path_len];

                                        // Check if file is already open in a tab
                                        var found_tab: i32 = -1;
                                        for (0..tab_count) |ti| {
                                            if (!tab_is_plugin[ti]) {
                                                const tab_path = tab_paths[ti][0..tab_path_lens[ti]];
                                                if (std.mem.eql(u8, tab_path, file_path)) {
                                                    found_tab = @intCast(ti);
                                                    break;
                                                }
                                            }
                                        }

                                        if (found_tab >= 0) {
                                            // Switch to existing tab
                                            tab_scroll_x[active_tab] = scroll_x;
                                            tab_scroll_y[active_tab] = scroll_y;
                                            active_tab = @intCast(found_tab);
                                            scroll_x = tab_scroll_x[active_tab];
                                            scroll_y = tab_scroll_y[active_tab];
                                        } else if (tab_count < MAX_TABS) {
                                            // Open in new tab
                                            tab_scroll_x[active_tab] = scroll_x;
                                            tab_scroll_y[active_tab] = scroll_y;

                                            const new_tab = tab_count;
                                            tab_is_plugin[new_tab] = false;
                                            tab_modified[new_tab] = false;
                                            @memcpy(tab_paths[new_tab][0..file_path.len], file_path);
                                            tab_path_lens[new_tab] = file_path.len;

                                            // Extract file name for tab
                                            var fname: []const u8 = file_path;
                                            if (std.mem.lastIndexOf(u8, file_path, "/")) |idx| {
                                                fname = file_path[idx + 1 ..];
                                            }
                                            @memcpy(tab_names[new_tab][0..fname.len], fname);
                                            tab_name_lens[new_tab] = fname.len;

                                            tab_scroll_x[new_tab] = 0;
                                            tab_scroll_y[new_tab] = 0;
                                            active_tab = new_tab;
                                            tab_count += 1;

                                            // Load file content
                                            loadFile(file_path, &text_buffer);
                                            invalidateLineIndex();
                                            invalidateCursorCache();
                                            invalidateTokenCache();
                                        }

                                        // Jump to line
                                        buildLineIndex(&text_buffer);
                                        const target_line = @max(1, result.line_num) - 1;
                                        const line_offset = text_buffer.getLineOffsetFast(target_line);
                                        text_buffer.moveCursor(line_offset);
                                        invalidateCursorCache();
                                        scroll_x = 0;
                                        scroll_y = 0;
                                        needs_redraw = true;
                                    }
                                }
                                g_search_active = false;
                            }
                        }

                        // Click on plugins (Plugins tab)
                        if (ui.sidebar_active_tab == 3) {
                            const plugin_start_y_click: i32 = sidebar_y + scaleI(8 + 24 + 12 + 20 + 30, zoom_level); // tabs + separator + header + "INSTALLED"
                            const plugin_item_h_click: i32 = 58;

                            const loader = plugins.getLoader();
                            var click_handled = false;

                            // Calculate where disabled section starts
                            const active_plugins_end_y = plugin_start_y_click + @as(i32, @intCast(loader.plugin_count)) * plugin_item_h_click;
                            const disabled_plugins = plugins.getDisabledPlugins();
                            const disabled_section_y = if (disabled_plugins.len > 0)
                                active_plugins_end_y + 10 + 15 + 25 // divider + header
                            else
                                active_plugins_end_y;
                            const disabled_item_h: i32 = 44;

                            // Check click on active plugins
                            if (loader.plugin_count > 0 and event.y >= plugin_start_y_click and event.y < active_plugins_end_y) {
                                const rel_y_plugin = event.y - plugin_start_y_click;
                                const clicked_plugin_idx: i32 = @divTrunc(rel_y_plugin, plugin_item_h_click);
                                if (clicked_plugin_idx >= 0 and clicked_plugin_idx < @as(i32, @intCast(loader.plugin_count))) {
                                    click_handled = true;
                                    const plugin_idx: usize = @intCast(clicked_plugin_idx);
                                    // Check if plugin tab already open
                                    var found_plugin_tab: i32 = -1;
                                    for (0..tab_count) |check_ti| {
                                        if (tab_is_plugin[check_ti] and tab_plugin_idx[check_ti] == plugin_idx) {
                                            found_plugin_tab = @intCast(check_ti);
                                            break;
                                        }
                                    }

                                    if (found_plugin_tab >= 0) {
                                        // Switch to existing tab
                                        tab_scroll_x[active_tab] = scroll_x;
                                        tab_scroll_y[active_tab] = scroll_y;
                                        active_tab = @intCast(found_plugin_tab);
                                        scroll_x = tab_scroll_x[active_tab];
                                        scroll_y = tab_scroll_y[active_tab];
                                    } else if (tab_count < MAX_TABS) {
                                        // Create new tab for plugin
                                        tab_scroll_x[active_tab] = scroll_x;
                                        tab_scroll_y[active_tab] = scroll_y;

                                        const new_plugin_tab_idx = tab_count;
                                        tab_is_plugin[new_plugin_tab_idx] = true;
                                        tab_plugin_idx[new_plugin_tab_idx] = plugin_idx;
                                        tab_modified[new_plugin_tab_idx] = false;
                                        tab_scroll_x[new_plugin_tab_idx] = 0;
                                        tab_scroll_y[new_plugin_tab_idx] = 0;
                                        tab_path_lens[new_plugin_tab_idx] = 0;

                                        // Tab name = plugin name
                                        const plugin_info = &loader.plugins[plugin_idx].info;
                                        const pname = plugin_info.getName();
                                        const pname_len = @min(pname.len, 63);
                                        @memcpy(tab_names[new_plugin_tab_idx][0..pname_len], pname[0..pname_len]);
                                        tab_name_lens[new_plugin_tab_idx] = pname_len;

                                        active_tab = new_plugin_tab_idx;
                                        tab_count += 1;
                                        scroll_x = 0;
                                        scroll_y = 0;
                                    }
                                    needs_redraw = true;
                                }
                            }

                            // Check click on disabled plugins (to re-enable them)
                            if (!click_handled and disabled_plugins.len > 0 and event.y >= disabled_section_y) {
                                const rel_y_disabled = event.y - disabled_section_y;
                                const clicked_disabled_idx: i32 = @divTrunc(rel_y_disabled, disabled_item_h);
                                if (clicked_disabled_idx >= 0 and clicked_disabled_idx < @as(i32, @intCast(disabled_plugins.len))) {
                                    const dp_idx: usize = @intCast(clicked_disabled_idx);
                                    const dp = &disabled_plugins[dp_idx];
                                    // Enable the plugin
                                    plugins.enablePlugin(dp.getPath()) catch |e| logger.warn("Operation failed: {}", .{e});
                                    needs_redraw = true;
                                }
                            }
                        }
                    } else {
                        // Check click in tab bar (coordinates match render, with zoom)
                        const click_editor_margin: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
                        const click_editor_left: i32 = if (ui.sidebar_visible) ui.sidebar_width + click_editor_margin else click_editor_margin;
                        const click_tab_bar_h: i32 = @intCast(scaleUI(TAB_BAR_HEIGHT, zoom_level));
                        const click_editor_bottom: i32 = @as(i32, @intCast(wayland.height)) - click_editor_margin - click_tab_bar_h - 4;
                        const tab_bar_y: i32 = click_editor_bottom + 4;
                        const tab_bar_x: i32 = click_editor_left;
                        const tab_h: i32 = click_tab_bar_h - scaleI(10, zoom_level); // -10 same as render

                        if (event.y >= tab_bar_y and event.y < tab_bar_y + click_tab_bar_h) {
                            // Click in tab bar
                            var check_tab_x: i32 = tab_bar_x + scaleI(8, zoom_level); // +8 same as render
                            const check_tab_y: i32 = tab_bar_y + scaleI(5, zoom_level); // +5 same as render

                            var clicked_on_tab = false;
                            for (0..tab_count) |check_tab_idx| {
                                const name_len = tab_name_lens[check_tab_idx];
                                if (name_len == 0) continue;

                                const text_width: i32 = @as(i32, @intCast(name_len)) * 8;
                                const tab_w: i32 = @max(140, text_width + 70); // Same values as in render

                                if (event.x >= check_tab_x and event.x < check_tab_x + tab_w and
                                    event.y >= check_tab_y and event.y < check_tab_y + tab_h)
                                {
                                    // Check click on close button
                                    const close_x = check_tab_x + tab_w - 22;
                                    if (event.x >= close_x and event.x < close_x + 18 and tab_count > 1) {
                                        // Close tab
                                        var close_i: usize = check_tab_idx;
                                        while (close_i + 1 < tab_count) : (close_i += 1) {
                                            tab_names[close_i] = tab_names[close_i + 1];
                                            tab_name_lens[close_i] = tab_name_lens[close_i + 1];
                                            tab_paths[close_i] = tab_paths[close_i + 1];
                                            tab_path_lens[close_i] = tab_path_lens[close_i + 1];
                                            tab_modified[close_i] = tab_modified[close_i + 1];
                                            tab_scroll_x[close_i] = tab_scroll_x[close_i + 1];
                                            tab_scroll_y[close_i] = tab_scroll_y[close_i + 1];
                                            tab_is_plugin[close_i] = tab_is_plugin[close_i + 1];
                                            tab_plugin_idx[close_i] = tab_plugin_idx[close_i + 1];
                                        }
                                        tab_count -= 1;
                                        if (active_tab >= tab_count) {
                                            active_tab = tab_count - 1;
                                        }
                                        // Plugin tabs don't need to load file
                                        if (!tab_is_plugin[active_tab]) {
                                            text_buffer.clear();
                                            if (tab_path_lens[active_tab] > 0) {
                                                loadFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                                            }
                                        }
                                        scroll_x = tab_scroll_x[active_tab];
                                        scroll_y = tab_scroll_y[active_tab];
                                        selection.clear();
                                    } else if (check_tab_idx != active_tab) {
                                        // Switch to tab
                                        tab_scroll_x[active_tab] = scroll_x;
                                        tab_scroll_y[active_tab] = scroll_y;
                                        active_tab = check_tab_idx;
                                        // Plugin tabs don't need to load file
                                        if (!tab_is_plugin[active_tab]) {
                                            text_buffer.clear();
                                            if (tab_path_lens[active_tab] > 0) {
                                                loadFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                                            }
                                        }
                                        scroll_x = tab_scroll_x[active_tab];
                                        scroll_y = tab_scroll_y[active_tab];
                                        selection.clear();
                                    }
                                    clicked_on_tab = true;
                                    needs_redraw = true;
                                    break;
                                }
                                check_tab_x += tab_w + 4;
                            }

                            // Check click on "+" button
                            if (!clicked_on_tab and tab_count < MAX_TABS) {
                                const plus_x = check_tab_x + 4;
                                if (event.x >= plus_x and event.x < plus_x + 28) {
                                    // New tab
                                    tab_scroll_x[active_tab] = scroll_x;
                                    tab_scroll_y[active_tab] = scroll_y;

                                    text_buffer.clear();
                                    selection.clear();
                                    scroll_x = 0;
                                    scroll_y = 0;

                                    const new_name = "Untitled";
                                    @memcpy(tab_names[tab_count][0..new_name.len], new_name);
                                    tab_name_lens[tab_count] = new_name.len;
                                    tab_path_lens[tab_count] = 0;
                                    tab_is_plugin[tab_count] = false;
                                    tab_modified[tab_count] = false;
                                    tab_scroll_x[tab_count] = 0;
                                    tab_scroll_y[tab_count] = 0;
                                    active_tab = tab_count;
                                    tab_count += 1;
                                    needs_redraw = true;
                                }
                            }

                            // Check click on buttons on the right (Run, Panel)
                            const click_tab_bar_w: i32 = @as(i32, @intCast(wayland.width)) - click_editor_margin * 2 - (if (ui.sidebar_visible) ui.sidebar_width else 0);
                            const click_tab_bar_right: i32 = tab_bar_x + click_tab_bar_w;
                            const click_right_btn_size: i32 = scaleI(28, zoom_level);

                            // Panel button (far right)
                            const click_panel_btn_x: i32 = click_tab_bar_right - click_right_btn_size - scaleI(8, zoom_level);
                            if (event.x >= click_panel_btn_x and event.x < click_panel_btn_x + click_right_btn_size and
                                event.y >= check_tab_y and event.y < check_tab_y + tab_h)
                            {
                                g_bottom_panel_visible = !g_bottom_panel_visible;
                                needs_redraw = true;
                            }

                            // Run button (left of Panel)
                            const click_run_btn_x: i32 = click_panel_btn_x - click_right_btn_size - scaleI(4, zoom_level);
                            if (event.x >= click_run_btn_x and event.x < click_run_btn_x + click_right_btn_size and
                                event.y >= check_tab_y and event.y < check_tab_y + tab_h)
                            {
                                g_bottom_panel_visible = true;
                                g_bottom_panel_tab = 0; // Output tab
                                g_output_line_count = 0;

                                // Get file path
                                const file_path = if (tab_path_lens[active_tab] > 0)
                                    tab_paths[active_tab][0..tab_path_lens[active_tab]]
                                else
                                    "";

                                if (file_path.len == 0) {
                                    const msg = "Run: No file open";
                                    @memcpy(g_output_lines[0][0..msg.len], msg);
                                    g_output_line_lens[0] = msg.len;
                                    g_output_line_count = 1;
                                } else {
                                    // Search for plugin for this file
                                    var loader = plugins.getLoader();
                                    if (loader.findPluginForFile(file_path)) |plugin_idx| {
                                        // Get run commands from plugin (comma-separated)
                                        var cmd_buf: [128]u8 = undefined;
                                        if (loader.getRunCommand(plugin_idx, &cmd_buf)) |run_cmds| {
                                            // Parse commands by comma and try each
                                            var cmd_iter = std.mem.splitScalar(u8, run_cmds, ',');
                                            var success = false;

                                            while (cmd_iter.next()) |cmd| {
                                                // Check command existence via which
                                                var which_buf: [256]u8 = undefined;
                                                const which_cmd = std.fmt.bufPrint(&which_buf, "which {s} >/dev/null 2>&1", .{cmd}) catch continue;

                                                const which_result = std.process.Child.run(.{
                                                    .allocator = allocator,
                                                    .argv = &[_][]const u8{ "/bin/sh", "-c", which_cmd },
                                                }) catch continue;
                                                allocator.free(which_result.stdout);
                                                allocator.free(which_result.stderr);

                                                if (which_result.term.Exited != 0) continue; // Command not found

                                                // Build full command
                                                var full_cmd: [1024]u8 = undefined;
                                                const cmd_str = std.fmt.bufPrint(&full_cmd, "{s} \"{s}\" 2>&1", .{ cmd, file_path }) catch continue;

                                                // Execute command
                                                const result = std.process.Child.run(.{
                                                    .allocator = allocator,
                                                    .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
                                                }) catch continue;
                                                defer allocator.free(result.stdout);
                                                defer allocator.free(result.stderr);

                                                success = true;
                                                g_run_exit_code = result.term.Exited;

                                                // Parse output by lines
                                                const output = if (result.stdout.len > 0) result.stdout else result.stderr;
                                                var line_start: usize = 0;
                                                for (output, 0..) |ch, idx| {
                                                    if (ch == '\n' or idx == output.len - 1) {
                                                        const line_end = if (ch == '\n') idx else idx + 1;
                                                        const line_len = @min(line_end - line_start, 255);
                                                        if (line_len > 0 and g_output_line_count < 255) {
                                                            @memcpy(g_output_lines[g_output_line_count][0..line_len], output[line_start..line_start + line_len]);
                                                            g_output_line_lens[g_output_line_count] = line_len;
                                                            // Determine line type (error/warning)
                                                            const line_text = g_output_lines[g_output_line_count][0..line_len];
                                                            g_output_line_types[g_output_line_count] = detectOutputLineType(line_text);
                                                            g_output_line_count += 1;
                                                        }
                                                        line_start = idx + 1;
                                                    }
                                                }
                                                break; // Successfully executed
                                            }

                                            if (!success) {
                                                const msg = "Run: No working interpreter found";
                                                @memcpy(g_output_lines[0][0..msg.len], msg);
                                                g_output_line_lens[0] = msg.len;
                                                g_output_line_types[0] = 2; // error
                                                g_output_line_count = 1;
                                            } else if (g_output_line_count == 0) {
                                                const msg = "Run: (no output)";
                                                @memcpy(g_output_lines[0][0..msg.len], msg);
                                                g_output_line_lens[0] = msg.len;
                                                g_output_line_types[0] = 0;
                                                g_output_line_count = 1;
                                            }
                                        } else {
                                            const msg = "Run: Plugin does not support run command";
                                            @memcpy(g_output_lines[0][0..msg.len], msg);
                                            g_output_line_lens[0] = msg.len;
                                            g_output_line_types[0] = 2;
                                            g_output_line_count = 1;
                                        }
                                    } else {
                                        const msg = "Run: No plugin for this file type";
                                        @memcpy(g_output_lines[0][0..msg.len], msg);
                                        g_output_line_lens[0] = msg.len;
                                        g_output_line_count = 1;
                                    }
                                }
                                needs_redraw = true;
                            }
                        } else if (g_bottom_panel_visible) {
                            // Check click in bottom panel area
                            const bp_panel_space: i32 = g_bottom_panel_height + 4;
                            const bp_y: i32 = @as(i32, @intCast(wayland.height)) - click_editor_margin - click_tab_bar_h - 4 - bp_panel_space + 4;
                            const bp_h: i32 = g_bottom_panel_height;

                            if (event.y >= bp_y and event.y < bp_y + bp_h) {
                                // Click in bottom panel
                                // Resize handle area (first 10 pixels)
                                if (event.y < bp_y + 10) {
                                    ui.dragging_bottom_panel = true;
                                    ui.drag_start_mouse = event.y;
                                    ui.drag_start_scroll = g_bottom_panel_height;
                                } else {
                                    // Tab clicks
                                    const bp_tab_y_click: i32 = bp_y + 10;
                                    if (event.y >= bp_tab_y_click and event.y < bp_tab_y_click + 26) {
                                        // Output tab
                                        if (event.x >= click_editor_left + 12 and event.x < click_editor_left + 82) {
                                            g_bottom_panel_tab = 0;
                                            needs_redraw = true;
                                        }
                                        // Problems tab
                                        else if (event.x >= click_editor_left + 86 and event.x < click_editor_left + 166) {
                                            g_bottom_panel_tab = 1;
                                            g_terminal_focused = false;
                                            needs_redraw = true;
                                        }
                                        // Terminal tab
                                        else if (event.x >= click_editor_left + 170 and event.x < click_editor_left + 250) {
                                            g_bottom_panel_tab = 2;
                                            g_terminal_focused = true;
                                            editor_focused = false;
                                            // Start shell if not running
                                            const term = shell.getShell();
                                            if (!term.isRunning()) {
                                                term.start() catch |e| logger.warn("Operation failed: {}", .{e});
                                            }
                                            needs_redraw = true;
                                        }
                                        // Close button (right)
                                        const bp_w_click: i32 = @as(i32, @intCast(wayland.width)) - click_editor_margin * 2 - (if (ui.sidebar_visible) ui.sidebar_width else 0);
                                        const close_x: i32 = click_editor_left + bp_w_click - 32;
                                        if (event.x >= close_x and event.x < close_x + 20) {
                                            g_bottom_panel_visible = false;
                                            needs_redraw = true;
                                        }
                                    }
                                }
                            } else {
                                // Click outside panel - in editor
                                editor_focused = true;
                                _ = text_buffer.getTextCached(); // Ensure cache is valid
                                buildLineIndex(&text_buffer); // Ensure line index for O(1) lookup
                                const click_pos = screenToTextPos(&gpu, &text_buffer, event.x, event.y, scroll_x, scroll_y, ui.sidebar_visible, ui.sidebar_width);
                                if (click_pos) |pos| {
                                    if (wayland.shift_held) {
                                        if (selection.anchor == null) {
                                            selection.anchor = text_buffer.cursor();
                                        }
                                        text_buffer.moveCursor(pos);
                                    } else {
                                        selection.clear();
                                        selection.anchor = pos;
                                        selection.dragging = true;
                                        text_buffer.moveCursor(pos);
                                    }
                                    needs_redraw = true;
                                }
                            }
                        } else {
                            // Check if plugin tab and click on buttons
                            var plugin_btn_clicked = false;
                            if (tab_is_plugin[active_tab] and !g_confirm_dialog.visible) {
                                const plugin_idx_click = tab_plugin_idx[active_tab];
                                const loader_click = plugins.getLoader();

                                // Check Disable/Enable button
                                if (event.x >= g_plugin_disable_btn_rect.x and
                                    event.x < g_plugin_disable_btn_rect.x + g_plugin_disable_btn_rect.w and
                                    event.y >= g_plugin_disable_btn_rect.y and
                                    event.y < g_plugin_disable_btn_rect.y + g_plugin_disable_btn_rect.h)
                                {
                                    plugin_btn_clicked = true;
                                    if (plugin_idx_click < loader_click.plugin_count) {
                                        const plugin_path_click = loader_click.plugins[plugin_idx_click].path;
                                        const path_len_click = loader_click.plugins[plugin_idx_click].path_len;
                                        const is_disabled = plugins.isPluginDisabled(plugin_path_click[0..path_len_click]);

                                        // Store pending action
                                        @memcpy(g_pending_plugin_path[0..path_len_click], plugin_path_click[0..path_len_click]);
                                        g_pending_plugin_path_len = path_len_click;
                                        g_pending_plugin_tab = active_tab;

                                        if (is_disabled) {
                                            // Enable without confirmation
                                            plugins.enablePlugin(plugin_path_click[0..path_len_click]) catch |e| logger.warn("Operation failed: {}", .{e});
                                        } else {
                                            // Show confirm dialog for disable
                                            g_pending_plugin_action = .disable;
                                            const plugin_name = loader_click.plugins[plugin_idx_click].info.getName();
                                            var msg_buf: [128]u8 = undefined;
                                            const msg = std.fmt.bufPrint(&msg_buf, "Disable plugin '{s}'?", .{plugin_name}) catch "Disable this plugin?";
                                            g_confirm_dialog.show("Disable Plugin", msg, "Disable", "Cancel", false, wayland.width, wayland.height);
                                        }
                                        needs_redraw = true;
                                    }
                                }

                                // Check Uninstall button
                                if (event.x >= g_plugin_uninstall_btn_rect.x and
                                    event.x < g_plugin_uninstall_btn_rect.x + g_plugin_uninstall_btn_rect.w and
                                    event.y >= g_plugin_uninstall_btn_rect.y and
                                    event.y < g_plugin_uninstall_btn_rect.y + g_plugin_uninstall_btn_rect.h)
                                {
                                    plugin_btn_clicked = true;
                                    if (plugin_idx_click < loader_click.plugin_count) {
                                        const plugin_path_click = loader_click.plugins[plugin_idx_click].path;
                                        const path_len_click = loader_click.plugins[plugin_idx_click].path_len;

                                        // Store pending action
                                        @memcpy(g_pending_plugin_path[0..path_len_click], plugin_path_click[0..path_len_click]);
                                        g_pending_plugin_path_len = path_len_click;
                                        g_pending_plugin_tab = active_tab;

                                        // Show confirm dialog for uninstall
                                        g_pending_plugin_action = .uninstall;
                                        const plugin_name = loader_click.plugins[plugin_idx_click].info.getName();
                                        var msg_buf: [128]u8 = undefined;
                                        const msg = std.fmt.bufPrint(&msg_buf, "Uninstall plugin '{s}'? This cannot be undone.", .{plugin_name}) catch "Uninstall this plugin?";
                                        g_confirm_dialog.show("Uninstall Plugin", msg, "Uninstall", "Cancel", true, wayland.width, wayland.height);
                                        needs_redraw = true;
                                    }
                                }
                            }

                            if (!plugin_btn_clicked) {
                                // Click in editor
                                editor_focused = true; // Return focus to editor
                                _ = text_buffer.getTextCached(); // Ensure cache is valid
                                buildLineIndex(&text_buffer); // Ensure line index for O(1) lookup
                                const click_pos = screenToTextPos(&gpu, &text_buffer, event.x, event.y, scroll_x, scroll_y, ui.sidebar_visible, ui.sidebar_width);
                                if (click_pos) |pos| {
                                    if (wayland.shift_held) {
                                        // Shift+click: extend selection
                                        if (selection.anchor == null) {
                                            selection.anchor = text_buffer.cursor();
                                        }
                                        text_buffer.moveCursor(pos);
                                    } else {
                                        // Normal click: start new selection
                                        selection.clear();
                                        selection.anchor = pos;
                                        selection.dragging = true;
                                        text_buffer.moveCursor(pos);
                                    }
                                    needs_redraw = true;
                                }
                            }
                        }
                    }
                } else {
                    // Left mouse button release
                    ui.dragging_vbar = false;
                    ui.dragging_hbar = false;
                    ui.dragging_sidebar = false;
                    ui.dragging_bottom_panel = false;
                    ui.dragging_tab_bar = false;
                    if (selection.dragging) {
                        selection.dragging = false;
                        // If anchor == cursor, just click without movement - remove selection
                        if (selection.anchor == text_buffer.cursor()) {
                            selection.clear();
                        }
                    }
                    // Save settings if slider was dragged
                    if (g_scroll_speed_slider.is_dragging) {
                        g_scroll_speed_slider.is_dragging = false;
                        saveSettings();
                    }
                    if (g_line_visibility_slider.is_dragging) {
                        g_line_visibility_slider.is_dragging = false;
                        saveSettings();
                    }
                }
            }
        }

        // Handle keyboard events
        for (wayland.pollKeyEvents()) |event| {
            if (event.pressed) {
                // New press - remember for repeat
                key_repeat.held_key = event.key;
                key_repeat.held_char = event.char;
                key_repeat.press_time_ms = now;
                key_repeat.last_repeat_ms = now;
                key_repeat.skip_lines = 1;
                key_repeat.last_accel_ms = now;

                // Mark navigation for scroll
                if (isNavigationKey(event.key)) {
                    just_navigated = true;
                }

                // F11 - toggle fullscreen
                if (event.key == wl.KEY_F11) {
                    wayland.toggleFullscreen();
                    needs_redraw = true;
                    continue;
                }

                // === Confirm dialog escape handling ===
                if (g_confirm_dialog.visible) {
                    if (event.key == wl.KEY_ESC) {
                        g_confirm_dialog.hide();
                        g_pending_plugin_action = .none;
                        g_pending_delete_action = false;
                        needs_redraw = true;
                        continue;
                    }
                    // Block other input while dialog is open
                    continue;
                }

                // === LSP Completion popup handling ===
                if (g_lsp_completion_visible) {
                    const completions = lspGetCompletions();
                    if (event.key == wl.KEY_ESC) {
                        g_lsp_completion_visible = false;
                        needs_redraw = true;
                        continue;
                    }
                    if (event.key == wl.KEY_UP) {
                        if (g_lsp_completion_selected > 0) {
                            g_lsp_completion_selected -= 1;
                        }
                        needs_redraw = true;
                        continue;
                    }
                    if (event.key == wl.KEY_DOWN) {
                        if (g_lsp_completion_selected < @as(i32, @intCast(completions.len)) - 1) {
                            g_lsp_completion_selected += 1;
                        }
                        needs_redraw = true;
                        continue;
                    }
                    if (event.key == wl.KEY_ENTER or event.key == wl.KEY_TAB) {
                        // Insert selected completion
                        if (completions.len > 0 and g_lsp_completion_selected < @as(i32, @intCast(completions.len))) {
                            const selected = &completions[@intCast(g_lsp_completion_selected)];
                            const insert_text = selected.getInsertText();
                            // Delete word before cursor (simple approach)
                            // Just insert the text for now
                            for (insert_text) |ch| {
                                text_buffer.insert(ch) catch |e| logger.warn("Operation failed: {}", .{e});
                            }
                            invalidateCursorCache();
                            invalidateLineIndex();
                            tab_modified[active_tab] = true;
                        }
                        g_lsp_completion_visible = false;
                        needs_redraw = true;
                        continue;
                    }
                    // Any other key closes completion
                    if (event.char == null and event.key != wl.KEY_LEFT and event.key != wl.KEY_RIGHT) {
                        // Keep open for navigation
                    } else if (event.char != null) {
                        // Close on typing
                        g_lsp_completion_visible = false;
                    }
                }

                // === Rename mode handling ===
                if (g_rename_mode) {
                    if (event.key == wl.KEY_ESC) {
                        // Cancel rename
                        g_rename_mode = false;
                        needs_redraw = true;
                        continue;
                    }
                    if (event.key == wl.KEY_ENTER) {
                        // Confirm rename
                        const new_name = g_rename_field.getText();
                        if (new_name.len > 0 and g_rename_idx < folder_file_count) {
                            renameFileOrFolder(
                                current_folder_path[0..current_folder_len],
                                folder_full_path[g_rename_idx][0..folder_full_path_lens[g_rename_idx]],
                                new_name,
                                &folder_files,
                                &folder_file_lens,
                                &folder_file_count,
                                &folder_is_dir,
                                &folder_expanded,
                                &folder_anim_progress,
                                &folder_indent,
                                &folder_parent,
                                &folder_full_path,
                                &folder_full_path_lens,
                            );
                        }
                        g_rename_mode = false;
                        needs_redraw = true;
                        continue;
                    }
                    // Handle text input
                    if (!wayland.ctrl_held) {
                        const changed = text_input.handleTextFieldKey(&g_rename_field, event.key, event.char);
                        if (changed) {
                            needs_redraw = true;
                        }
                    }
                    continue;
                }

                // === Search input handling ===
                if (search_visible) {
                    // Escape - close search
                    if (event.key == wl.KEY_ESC) {
                        search_visible = false;
                        editor_focused = true; // Return focus to editor
                        needs_redraw = true;
                        continue;
                    }

                    // Enter/F3 - next match (Shift - previous)
                    if (event.key == wl.KEY_ENTER or event.key == wl.KEY_F3) {
                        if (search_match_count > 0) {
                            if (wayland.shift_held) {
                                // Previous match
                                if (search_current_match > 0) {
                                    search_current_match -= 1;
                                } else {
                                    search_current_match = search_match_count - 1;
                                }
                            } else {
                                // Next match
                                search_current_match = (search_current_match + 1) % search_match_count;
                            }
                            // Jump to match
                            const match_pos = search_matches[search_current_match];
                            text_buffer.moveCursor(match_pos);
                            // Auto-scroll to match
                            const cur_pos = text_buffer.cursorPositionConst();
                            const line_h: i32 = @intCast(gpu.lineHeight());
                            scroll_y = @max(0, @as(i32, @intCast(cur_pos.line)) * line_h - @as(i32, @intCast(wayland.height / 3)));
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Handle search field input via common module
                    if (!wayland.ctrl_held) {
                        const changed = text_input.handleTextFieldKey(&search_field, event.key, event.char);
                        if (changed) {
                            // Re-search on change
                            search_match_count = performSearch(&text_buffer, search_field.getText(), &search_matches);
                            if (search_match_count > 0) {
                                search_current_match = findNearestMatch(search_matches[0..search_match_count], text_buffer.cursor());
                            }
                        }
                        // Start key repeat for search
                        search_key_repeat.startPress(event.key, event.char, now);
                        needs_redraw = true;
                        continue;
                    }
                }

                // === Keyboard shortcuts ===
                if (wayland.ctrl_held) {
                    // Ctrl+S - Save
                    if (event.key == wl.KEY_S) {
                        if (tab_path_lens[active_tab] > 0) {
                            saveFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                            tab_modified[active_tab] = false;
                            // Update original content
                            const content_len = @min(text_buffer.len(), MAX_UNDO_SIZE);
                            if (text_buffer.getText(allocator)) |txt| {
                                @memcpy(tab_original_content[active_tab][0..content_len], txt[0..content_len]);
                                tab_original_lens[active_tab] = content_len;
                                allocator.free(txt);
                            } else |_| {}
                        } else {
                            saveFileDialogTab(&text_buffer, &tab_paths, &tab_path_lens, &tab_names, &tab_name_lens, &tab_modified, active_tab);
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+N - New tab
                    if (event.key == wl.KEY_N) {
                        if (tab_count < MAX_TABS) {
                            active_tab = tab_count;
                            const new_name = "Untitled";
                            @memcpy(tab_names[active_tab][0..new_name.len], new_name);
                            tab_name_lens[active_tab] = new_name.len;
                            tab_path_lens[active_tab] = 0;
                            tab_is_plugin[active_tab] = false;
                            tab_modified[active_tab] = false;
                            tab_scroll_x[active_tab] = 0;
                            tab_scroll_y[active_tab] = 0;
                            tab_original_lens[active_tab] = 0;
                            text_buffer.clear();
                            scroll_x = 0;
                            scroll_y = 0;
                            tab_count += 1;
                            undo_count = 0;
                            redo_count = 0;
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+W - Close tab
                    if (event.key == wl.KEY_W) {
                        if (tab_count > 1) {
                            var close_i: usize = active_tab;
                            while (close_i + 1 < tab_count) : (close_i += 1) {
                                tab_names[close_i] = tab_names[close_i + 1];
                                tab_name_lens[close_i] = tab_name_lens[close_i + 1];
                                tab_paths[close_i] = tab_paths[close_i + 1];
                                tab_path_lens[close_i] = tab_path_lens[close_i + 1];
                                tab_modified[close_i] = tab_modified[close_i + 1];
                                tab_scroll_x[close_i] = tab_scroll_x[close_i + 1];
                                tab_scroll_y[close_i] = tab_scroll_y[close_i + 1];
                                tab_original_content[close_i] = tab_original_content[close_i + 1];
                                tab_original_lens[close_i] = tab_original_lens[close_i + 1];
                            }
                            tab_count -= 1;
                            if (active_tab >= tab_count) {
                                active_tab = tab_count - 1;
                            }
                            text_buffer.clear();
                            if (tab_path_lens[active_tab] > 0) {
                                loadFile(tab_paths[active_tab][0..tab_path_lens[active_tab]], &text_buffer);
                            }
                            scroll_x = tab_scroll_x[active_tab];
                            scroll_y = tab_scroll_y[active_tab];
                            undo_count = 0;
                            redo_count = 0;
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Z - Undo
                    if (event.key == wl.KEY_Z) {
                        if (undo_count > 0) {
                            // Save current state to redo
                            if (redo_count < MAX_UNDO) {
                                const cur_len = @min(text_buffer.len(), MAX_UNDO_SIZE);
                                if (text_buffer.getText(allocator)) |txt| {
                                    @memcpy(redo_stack[redo_count][0..cur_len], txt[0..cur_len]);
                                    redo_lens[redo_count] = cur_len;
                                    redo_cursors[redo_count] = text_buffer.cursor();
                                    redo_count += 1;
                                    allocator.free(txt);
                                } else |_| {}
                            }
                            // Restore from undo
                            undo_count -= 1;
                            text_buffer.clear();
                            const undo_len = undo_lens[undo_count];
                            text_buffer.insertSlice(undo_stack[undo_count][0..undo_len]) catch |e| logger.warn("Operation failed: {}", .{e});
                            text_buffer.moveCursor(undo_cursors[undo_count]);
                            // Check if matches original
                            const matches_original = (undo_len == tab_original_lens[active_tab]) and
                                std.mem.eql(u8, undo_stack[undo_count][0..undo_len], tab_original_content[active_tab][0..undo_len]);
                            tab_modified[active_tab] = !matches_original;
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Y - Redo
                    if (event.key == wl.KEY_Y) {
                        if (redo_count > 0) {
                            // Save current state to undo
                            if (undo_count < MAX_UNDO) {
                                const cur_len = @min(text_buffer.len(), MAX_UNDO_SIZE);
                                if (text_buffer.getText(allocator)) |txt| {
                                    @memcpy(undo_stack[undo_count][0..cur_len], txt[0..cur_len]);
                                    undo_lens[undo_count] = cur_len;
                                    undo_cursors[undo_count] = text_buffer.cursor();
                                    undo_count += 1;
                                    allocator.free(txt);
                                } else |_| {}
                            }
                            // Restore from redo
                            redo_count -= 1;
                            text_buffer.clear();
                            const redo_len = redo_lens[redo_count];
                            text_buffer.insertSlice(redo_stack[redo_count][0..redo_len]) catch |e| logger.warn("Operation failed: {}", .{e});
                            text_buffer.moveCursor(redo_cursors[redo_count]);
                            // Check if matches original
                            const matches_original = (redo_len == tab_original_lens[active_tab]) and
                                std.mem.eql(u8, redo_stack[redo_count][0..redo_len], tab_original_content[active_tab][0..redo_len]);
                            tab_modified[active_tab] = !matches_original;
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+O - Open file
                    if (event.key == wl.KEY_O) {
                        openFileDialog(&text_buffer, &tab_names, &tab_name_lens, &tab_paths, &tab_path_lens, &tab_modified, &tab_count, &active_tab, &tab_scroll_x, &tab_scroll_y, &scroll_x, &scroll_y, &selection, &tab_original_content, &tab_original_lens, &undo_count, &redo_count, allocator);
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+F - Open search
                    if (event.key == wl.KEY_F) {
                        search_visible = true;
                        search_field.moveCursorEnd();
                        editor_focused = false; // Focus on search
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Space - LSP Autocomplete
                    if (event.key == wl.KEY_SPACE) {
                        if (tab_path_lens[active_tab] > 0 and lspIsConnected()) {
                            const cursor_p = text_buffer.cursorPositionConst();
                            lspRequestCompletion(
                                tab_paths[active_tab][0..tab_path_lens[active_tab]],
                                @intCast(cursor_p.line),
                                @intCast(cursor_p.col),
                            );
                            // Calculate popup position
                            const line_h: i32 = @intCast(gpu.lineHeight());
                            const char_w: i32 = @intCast(gpu.charWidth());
                            const editor_x: i32 = if (ui.sidebar_visible) ui.sidebar_width else 0;
                            const gutter_w: u32 = gpu.scaled(GUTTER_WIDTH);
                            g_lsp_completion_x = editor_x + @as(i32, @intCast(gutter_w)) + @as(i32, @intCast(cursor_p.col)) * char_w - scroll_x + 20;
                            g_lsp_completion_y = @as(i32, @intCast(gpu.scaled(TITLEBAR_HEIGHT))) + g_tab_bar_height + @as(i32, @intCast(cursor_p.line)) * line_h - scroll_y + line_h + 10;
                            g_lsp_completion_visible = true;
                            g_lsp_completion_selected = 0;
                        }
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+G - Go to next/prev match
                    if (event.key == wl.KEY_G and search_match_count > 0) {
                        if (wayland.shift_held) {
                            // Previous match
                            if (search_current_match > 0) {
                                search_current_match -= 1;
                            } else {
                                search_current_match = search_match_count - 1;
                            }
                        } else {
                            // Next match
                            search_current_match = (search_current_match + 1) % search_match_count;
                        }
                        // Jump to match
                        const match_pos = search_matches[search_current_match];
                        text_buffer.moveCursor(match_pos);
                        // Auto-scroll to match
                        const cur_pos = text_buffer.cursorPositionConst();
                        const line_h: i32 = @intCast(gpu.lineHeight());
                        scroll_y = @max(0, @as(i32, @intCast(cur_pos.line)) * line_h - @as(i32, @intCast(wayland.height / 3)));
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+= (Ctrl+Plus) - Zoom In (UI)
                    if (event.key == wl.KEY_EQUAL and !wayland.shift_held) {
                        zoom_level = @min(ZOOM_MAX, zoom_level + ZOOM_STEP);
                        gpu.setZoom(zoom_level);
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+- (Ctrl+Minus) - Zoom Out (UI)
                    if (event.key == wl.KEY_MINUS and !wayland.shift_held) {
                        zoom_level = @max(ZOOM_MIN, zoom_level - ZOOM_STEP);
                        gpu.setZoom(zoom_level);
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+0 - Reset Zoom to 100%
                    if (event.key == wl.KEY_0 and !wayland.shift_held) {
                        zoom_level = 1.0;
                        gpu.setZoom(zoom_level);
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Shift+= - Text Zoom In
                    if (event.key == wl.KEY_EQUAL and wayland.shift_held) {
                        text_zoom = @min(TEXT_ZOOM_MAX, text_zoom + TEXT_ZOOM_STEP);
                        gpu.setTextZoom(text_zoom) catch |e| logger.warn("Operation failed: {}", .{e});
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Shift+- - Text Zoom Out
                    if (event.key == wl.KEY_MINUS and wayland.shift_held) {
                        text_zoom = @max(TEXT_ZOOM_MIN, text_zoom - TEXT_ZOOM_STEP);
                        gpu.setTextZoom(text_zoom) catch |e| logger.warn("Operation failed: {}", .{e});
                        needs_redraw = true;
                        continue;
                    }

                    // Ctrl+Shift+0 - Reset Text Zoom to 100%
                    if (event.key == wl.KEY_0 and wayland.shift_held) {
                        text_zoom = 1.0;
                        gpu.setTextZoom(text_zoom) catch |e| logger.warn("Operation failed: {}", .{e});
                        needs_redraw = true;
                        continue;
                    }
                }

                // F3 - next/prev match (global, no Ctrl needed)
                if (event.key == wl.KEY_F3 and search_match_count > 0) {
                    if (wayland.shift_held) {
                        if (search_current_match > 0) {
                            search_current_match -= 1;
                        } else {
                            search_current_match = search_match_count - 1;
                        }
                    } else {
                        search_current_match = (search_current_match + 1) % search_match_count;
                    }
                    const match_pos = search_matches[search_current_match];
                    text_buffer.moveCursor(match_pos);
                    const cur_pos = text_buffer.cursorPositionConst();
                    const line_h: i32 = @intCast(gpu.lineHeight());
                    scroll_y = @max(0, @as(i32, @intCast(cur_pos.line)) * line_h - @as(i32, @intCast(wayland.height / 3)));
                    needs_redraw = true;
                    continue;
                }

                // Input to terminal if focused
                if (g_terminal_focused and g_bottom_panel_tab == 2) {
                    const term = shell.getShell();

                    if (event.key == wl.KEY_ENTER) {
                        // Send command to shell
                        const cmd = g_terminal_field.getText();
                        if (term.isRunning() and cmd.len > 0) {
                            term.sendLine(cmd);
                            g_terminal_field.clear();
                        } else if (!term.isRunning()) {
                            // Start shell on Enter
                            term.start() catch |e| logger.warn("Operation failed: {}", .{e});
                        }
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_ESC) {
                        // Unfocus terminal, focus editor
                        g_terminal_focused = false;
                        editor_focused = true;
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_UP) {
                        // History previous
                        if (term.historyPrev()) |prev_cmd| {
                            g_terminal_field.clear();
                            for (prev_cmd) |ch| {
                                _ = g_terminal_field.insert(ch);
                            }
                        }
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_DOWN) {
                        // History next
                        if (term.historyNext()) |next_cmd| {
                            g_terminal_field.clear();
                            for (next_cmd) |ch| {
                                _ = g_terminal_field.insert(ch);
                            }
                        } else {
                            g_terminal_field.clear();
                        }
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_PAGEUP) {
                        // Scroll terminal output up
                        term.scrollUp(5);
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_PAGEDOWN) {
                        // Scroll terminal output down
                        term.scrollDown(5);
                        needs_redraw = true;
                    } else {
                        // Handle text input using TextFieldBuffer
                        _ = text_input.handleTextFieldKey(&g_terminal_field, event.key, event.char);
                        g_terminal_key_repeat.startPress(event.key, event.char, now);
                        needs_redraw = true;
                    }
                    continue; // Don't process further
                }

                // Input to global search if focused
                if (g_search_active) {
                    if (event.key == wl.KEY_ENTER) {
                        // Perform search
                        const query = g_search_field.getText();
                        if (query.len > 0) {
                            performGlobalSearch(query);
                        }
                        needs_redraw = true;
                    } else if (event.key == wl.KEY_ESC) {
                        // Deactivate search
                        g_search_active = false;
                        needs_redraw = true;
                    } else {
                        // Handle text input
                        const changed = text_input.handleTextFieldKey(&g_search_field, event.key, event.char);
                        if (changed) {
                            // Auto-search as you type (if query >= 2 chars)
                            const query = g_search_field.getText();
                            if (query.len >= 2) {
                                performGlobalSearch(query);
                            } else {
                                g_search_result_count = 0;
                            }
                        }
                        needs_redraw = true;
                    }
                    continue; // Don't process further
                }

                // Input to editor only if focused
                if (editor_focused) {
                    // Save undo state before modifying (skip if Ctrl is held - those are shortcuts, not edits)
                    const len_before = text_buffer.len();
                    if ((event.char != null and !wayland.ctrl_held) or event.key == wl.KEY_BACKSPACE or event.key == wl.KEY_DELETE) {
                        // Save current state for undo
                        if (undo_count < MAX_UNDO) {
                            const cur_len = @min(text_buffer.len(), MAX_UNDO_SIZE);
                            if (text_buffer.getText(allocator)) |txt| {
                                @memcpy(undo_stack[undo_count][0..cur_len], txt[0..cur_len]);
                                undo_lens[undo_count] = cur_len;
                                undo_cursors[undo_count] = text_buffer.cursor();
                                undo_count += 1;
                                redo_count = 0; // Clear redo on new edit
                                allocator.free(txt);
                            } else |_| {}
                        }
                    }

                    // === Smart editing features (all languages) ===
                    const file_type: FileType = if (tab_path_lens[active_tab] > 0)
                        detectFileType(tab_paths[active_tab][0..tab_path_lens[active_tab]])
                    else
                        .zig; // Default to zig for new unsaved files

                    // Enable smart editing for all files
                    const is_code_file = true;
                    var handled_specially = false;

                    // Check if we have a plugin for this file with on_char/on_enter support
                    var active_plugin_idx: ?usize = null;
                    var plugin_loader = plugins.getLoader();
                    if (tab_path_lens[active_tab] > 0) {
                        if (plugin_loader.findPluginForFile(tab_paths[active_tab][0..tab_path_lens[active_tab]])) |pidx| {
                            if (pidx < plugin_loader.plugin_count) {
                                const pinfo = &plugin_loader.plugins[pidx].info;
                                if (pinfo.has_on_char or pinfo.has_on_enter) {
                                    active_plugin_idx = pidx;
                                }
                            }
                        }
                    }

                    // Plugin-based smart Enter handling
                    if (active_plugin_idx != null and event.char != null and event.char.? == '\n' and !wayland.ctrl_held) {
                        // Try plugin's on_enter first
                        if (text_buffer.getText(allocator)) |source_text| {
                            defer allocator.free(source_text);
                            var enter_buf: [256]u8 = undefined;
                            if (plugin_loader.onEnter(active_plugin_idx.?, source_text[0..text_buffer.len()], @intCast(text_buffer.cursor()), &enter_buf)) |insert_text| {
                                // Remove selection if any
                                if (selection.getRange(text_buffer.cursor())) |range| {
                                    var del_i: usize = 0;
                                    text_buffer.moveCursor(range.start);
                                    while (del_i < range.end - range.start) : (del_i += 1) {
                                        text_buffer.deleteForward();
                                    }
                                    selection.clear();
                                }
                                // Insert the text from plugin
                                for (insert_text) |ch| {
                                    text_buffer.insert(ch) catch |e| logger.warn("Operation failed: {}", .{e});
                                }
                                handled_specially = true;
                            }
                        } else |_| {}
                    }

                    if (!handled_specially and is_code_file and !wayland.ctrl_held) {
                        // Auto-indent on Enter
                        if (event.char != null and event.char.? == '\n') {
                            // Delete selection if exists
                            if (selection.getRange(text_buffer.cursor())) |range| {
                                var del_i: usize = 0;
                                text_buffer.moveCursor(range.start);
                                while (del_i < range.end - range.start) : (del_i += 1) {
                                    text_buffer.deleteForward();
                                }
                                selection.clear();
                            }

                            // Get current indent
                            const indent = getCurrentLineIndent(&text_buffer);
                            const extra_indent = shouldAddExtraIndent(&text_buffer, file_type);

                            // Insert newline + indent
                            text_buffer.insert('\n') catch |e| logger.warn("Operation failed: {}", .{e});
                            for (indent) |indent_ch| {
                                text_buffer.insert(indent_ch) catch |e| logger.warn("Operation failed: {}", .{e});
                            }
                            if (extra_indent) {
                                // Add 4 spaces
                                text_buffer.insert(' ') catch |e| logger.warn("Operation failed: {}", .{e});
                                text_buffer.insert(' ') catch |e| logger.warn("Operation failed: {}", .{e});
                                text_buffer.insert(' ') catch |e| logger.warn("Operation failed: {}", .{e});
                                text_buffer.insert(' ') catch |e| logger.warn("Operation failed: {}", .{e});
                            }
                            handled_specially = true;
                        }
                        // Auto-close brackets and quotes
                        else if (event.char) |ch| {
                            if (getClosingBracket(ch)) |close_ch| {
                                // Check: if next char = close_ch, just skip over
                                const cursor = text_buffer.cursor();
                                const next_ch = text_buffer.charAtConst(cursor);

                                if (next_ch != null and next_ch.? == close_ch and (ch == '"' or ch == '\'')) {
                                    // User types quote, but it already exists - skip over
                                    text_buffer.moveCursor(cursor + 1);
                                    handled_specially = true;
                                } else if (next_ch != null and next_ch.? == ch and (ch == ')' or ch == ']' or ch == '}')) {
                                    // User types closing bracket, but it already exists - skip over
                                    text_buffer.moveCursor(cursor + 1);
                                    handled_specially = true;
                                } else {
                                    // Delete selection if exists
                                    if (selection.getRange(text_buffer.cursor())) |range| {
                                        var del_i: usize = 0;
                                        text_buffer.moveCursor(range.start);
                                        while (del_i < range.end - range.start) : (del_i += 1) {
                                            text_buffer.deleteForward();
                                        }
                                        selection.clear();
                                    }
                                    // Insert opening and closing bracket/quote
                                    text_buffer.insert(ch) catch |e| logger.warn("Operation failed: {}", .{e});
                                    text_buffer.insert(close_ch) catch |e| logger.warn("Operation failed: {}", .{e});
                                    // Cursor between brackets
                                    const cur = text_buffer.cursor();
                                    if (cur > 0) text_buffer.moveCursor(cur - 1);
                                    handled_specially = true;
                                }
                            }
                        }
                    }

                    if (!handled_specially) {
                        handleKeyAction(event.key, event.char, &text_buffer, &wayland, &selection, 1);
                    }

                    // Plugin-based on_char (auto-close tags, etc.)
                    if (active_plugin_idx != null and event.char != null and !wayland.ctrl_held) {
                        const typed_char = event.char.?;
                        if (text_buffer.getText(allocator)) |source_text| {
                            defer allocator.free(source_text);
                            var char_buf: [256]u8 = undefined;
                            if (plugin_loader.onChar(active_plugin_idx.?, source_text[0..text_buffer.len()], @intCast(text_buffer.cursor()), typed_char, &char_buf)) |result| {
                                const cursor_before = text_buffer.cursor();

                                // First delete chars after cursor if needed
                                if (result.delete_after > 0) {
                                    var del_i: u16 = 0;
                                    while (del_i < result.delete_after) : (del_i += 1) {
                                        text_buffer.deleteForward();
                                    }
                                }

                                // Then insert new text
                                for (result.insert_text) |ch| {
                                    text_buffer.insert(ch) catch |e| logger.warn("Operation failed: {}", .{e});
                                }

                                // Move cursor back to original position
                                text_buffer.moveCursor(cursor_before);
                            }
                        } else |_| {}
                    }

                    // Check if really modified (compare with original)
                    if (text_buffer.len() != len_before) {
                        const cur_len = text_buffer.len();
                        if (cur_len == tab_original_lens[active_tab] and cur_len <= MAX_UNDO_SIZE) {
                            if (text_buffer.getText(allocator)) |txt| {
                                const matches = std.mem.eql(u8, txt[0..cur_len], tab_original_content[active_tab][0..cur_len]);
                                tab_modified[active_tab] = !matches;
                                allocator.free(txt);
                            } else |_| {
                                tab_modified[active_tab] = true;
                            }
                        } else {
                            tab_modified[active_tab] = true;
                        }
                    }
                    needs_redraw = true;
                }
            } else {
                // Release
                if (key_repeat.held_key == event.key) {
                    key_repeat.held_key = null;
                    key_repeat.held_char = null;
                }
                // Release for search
                search_key_repeat.release(event.key);
            }
        }

        // Key repeat logic - only if editor is focused
        if (editor_focused and key_repeat.held_key != null) {
            const key = key_repeat.held_key.?;
            const held_duration = now - key_repeat.press_time_ms;

            if (held_duration > REPEAT_DELAY_MS) {
                // Check acceleration (after 8 sec) - only for navigation
                if (isNavigationKey(key) and held_duration > ACCEL_START_MS) {
                    if (now - key_repeat.last_accel_ms > ACCEL_INTERVAL_MS) {
                        key_repeat.skip_lines *= 2;
                        key_repeat.last_accel_ms = now;
                    }
                }

                // Repeat at interval
                if (now - key_repeat.last_repeat_ms > REPEAT_RATE_MS) {
                    const len_before_repeat = text_buffer.len();
                    handleKeyAction(key, key_repeat.held_char, &text_buffer, &wayland, &selection, key_repeat.skip_lines);
                    if (text_buffer.len() != len_before_repeat) {
                        tab_modified[active_tab] = true;
                    }
                    key_repeat.last_repeat_ms = now;
                    needs_redraw = true;
                }
            }
        }

        // Key repeat for search field
        if (search_visible and !editor_focused and search_key_repeat.held_key != null) {
            const is_nav = text_input.isNavigationKey(search_key_repeat.held_key.?);
            if (search_key_repeat.shouldRepeat(now, is_nav)) |_| {
                const changed = text_input.handleTextFieldKey(&search_field, search_key_repeat.held_key.?, search_key_repeat.held_char);
                if (changed) {
                    search_match_count = performSearch(&text_buffer, search_field.getText(), &search_matches);
                    if (search_match_count > 0) {
                        search_current_match = findNearestMatch(search_matches[0..search_match_count], text_buffer.cursor());
                    }
                }
                needs_redraw = true;
            }
        }

        // Scroll to cursor ONLY on arrow key navigation
        if (just_navigated) {
            const cur_pos = text_buffer.cursorPositionConst();
            const char_w: i32 = @intCast(gpu.charWidth());
            const gutter_w: i32 = @intCast(scaleUI(GUTTER_WIDTH, zoom_level));
            const screen_width: i32 = @intCast(wayland.width);
            const scroll_margin: i32 = scaleI(50, zoom_level);
            const scroll_offset: i32 = scaleI(100, zoom_level);
            const gutter_padding: i32 = scaleI(12, zoom_level);

            // Cursor position on screen (entire field moves together)
            const cursor_screen_x = (gutter_w + gutter_padding - scroll_x) + @as(i32, @intCast(cur_pos.col)) * char_w;

            // Scroll right if cursor went past right edge
            if (cursor_screen_x > screen_width - scroll_margin) {
                scroll_x = gutter_w + gutter_padding + @as(i32, @intCast(cur_pos.col)) * char_w - screen_width + scroll_offset;
            }
            // Scroll left if cursor went past left edge
            if (cursor_screen_x < scroll_margin) {
                scroll_x = @max(0, gutter_w + gutter_padding + @as(i32, @intCast(cur_pos.col)) * char_w - scroll_offset);
            }
            just_navigated = false;
        }

        wayland.clearEvents();

        // Update folder expansion animations
        animation_active = false;
        for (0..folder_file_count) |anim_idx| {
            const target: f32 = if (folder_expanded[anim_idx]) 1.0 else 0.0;
            const current = folder_anim_progress[anim_idx];
            if (@abs(target - current) > 0.01) {
                // Smooth animation with easing
                const speed: f32 = 0.15;
                folder_anim_progress[anim_idx] = current + (target - current) * speed;
                animation_active = true;
                needs_redraw = true;
            } else {
                folder_anim_progress[anim_idx] = target;
            }
        }

        // Auto-correct scroll_y when content changes (with zoom)
        {
            const line_height_i32: i32 = @intCast(gpu.lineHeight());
            const editor_margin_i32: i32 = scaleI(@as(i32, EDITOR_MARGIN), zoom_level);
            const editor_padding_i32: i32 = scaleI(@as(i32, EDITOR_PADDING), zoom_level);
            const titlebar_h_i32: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom_level));
            const tab_bar_h_i32: i32 = @intCast(scaleUI(TAB_BAR_HEIGHT, zoom_level));
            const editor_top_i32: i32 = titlebar_h_i32 + editor_margin_i32;
            const editor_bottom_i32: i32 = @as(i32, @intCast(wayland.height)) - editor_margin_i32 - tab_bar_h_i32 - 4;
            const visible_height: i32 = editor_bottom_i32 - editor_top_i32 - editor_padding_i32 * 2;
            const total_lines: i32 = @intCast(g_cached_line_count);
            const content_height: i32 = total_lines * line_height_i32;
            const max_scroll_y: i32 = @max(0, content_height - visible_height);
            scroll_y = @max(0, @min(max_scroll_y, scroll_y));
        }

        // Poll LSP for responses
        lspPoll();
        // Check if completions arrived
        if (g_lsp_completion_visible and lspGetCompletions().len > 0) {
            needs_redraw = true;
        }

        // Redraw
        if (needs_redraw) {
            // Determine change type for optimization
            if (scroll_y != g_prev_scroll_y) {
                markFullRedraw(); // Scroll requires full redraw
            }

            // Check selection change
            const cur_sel = selection.getRange(text_buffer.cursor());
            const sel_changed = if (cur_sel) |r| (g_prev_selection_start != r.start or g_prev_selection_end != r.end) else (g_prev_selection_start != null);
            if (sel_changed) {
                markFullRedraw(); // Selection change requires redraw
            }

            // Ensure text cache is valid before rendering (for fast charAtConst access)
            var t1 = std.time.milliTimestamp();
            _ = text_buffer.getTextCached();
            var t2 = std.time.milliTimestamp();
            if (t2 - t1 > 10) logger.debug("[RENDER] getTextCached: {}ms\n", .{t2 - t1});

            // Build line index for O(1) line offset lookup
            t1 = std.time.milliTimestamp();
            buildLineIndex(&text_buffer);
            t2 = std.time.milliTimestamp();
            if (t2 - t1 > 10) logger.debug("[RENDER] buildLineIndex: {}ms\n", .{t2 - t1});
            // Pre-cache cursor position (expensive calculation done once per frame)
            updateCursorCache(&text_buffer);

            gpu.beginFrame();
            t1 = std.time.milliTimestamp();
            render(&gpu, &text_buffer, &wayland, &selection, scroll_x, scroll_y, ui.sidebar_visible, ui.sidebar_width, ui.sidebar_active_tab, ui.sidebar_tab_hovered, ui.open_folder_btn_hovered, ui.sidebar_resize_hovered, ui.menu_hover, ui.menu_open, ui.menu_item_hover, ui.settings_visible, ui.settings_active_tab, ui.settings_tab_hovered, ui.settings_checkbox_hovered, &folder_files, &folder_file_lens, folder_file_count, &folder_is_dir, &folder_expanded, &folder_anim_progress, &folder_indent, explorer_selected, explorer_hovered, explorer_scroll, current_folder_len, &tab_names, &tab_name_lens, &tab_modified, tab_count, active_tab, tab_hovered, tab_close_hovered, &tab_paths, &tab_path_lens, &tab_is_plugin, &tab_plugin_idx, plugin_hovered, search_visible, search_field.getText(), search_field.cursor, search_match_count, search_current_match, &search_matches, editor_focused);
            t2 = std.time.milliTimestamp();
            if (t2 - t1 > 16) logger.debug("[RENDER] render(): {}ms\n", .{t2 - t1});
            gpu.endFrame();

            // Tell Wayland which regions changed (damage reporting)
            // For now do full damage, can optimize later
            c.wl_surface_damage(wayland.surface, 0, 0, @intCast(wayland.width), @intCast(wayland.height));
            c.wl_surface_commit(wayland.surface);

            // Save state for next frame
            g_prev_scroll_y = scroll_y;
            g_prev_cursor_line = g_cursor_cache_line;
            if (cur_sel) |r| {
                g_prev_selection_start = r.start;
                g_prev_selection_end = r.end;
            } else {
                g_prev_selection_start = null;
                g_prev_selection_end = null;
            }
            clearDirty();
            needs_redraw = false;
        }
    }

}

fn isNavigationKey(key: u32) bool {
    return key == wl.KEY_LEFT or key == wl.KEY_RIGHT or
        key == wl.KEY_UP or key == wl.KEY_DOWN or
        key == wl.KEY_BACKSPACE or key == wl.KEY_DELETE;
}

fn getResizeEdge(x: i32, y: i32, width: u32, height: u32, zoom: f32) u32 {
    const edge_size: i32 = scaleI(8, zoom);
    const w: i32 = @intCast(width);
    const h: i32 = @intCast(height);

    // Exclude scrollbar zone (scrollbar_size=10, margin=4)
    const scrollbar_zone: i32 = scaleI(18, zoom); // 10 + 4 + margin
    const titlebar_h: i32 = @intCast(scaleUI(TITLEBAR_HEIGHT, zoom));
    const gutter_w: i32 = @intCast(scaleUI(GUTTER_WIDTH, zoom));
    const in_vbar_zone = x >= w - scrollbar_zone and y > titlebar_h and y < h - scrollbar_zone;
    const in_hbar_zone = y >= h - scrollbar_zone and x > gutter_w and x < w - scrollbar_zone;

    // If in scrollbar zone - don't resize
    if (in_vbar_zone or in_hbar_zone) return wl.RESIZE_NONE;

    const at_left = x < edge_size;
    const at_right = x >= w - edge_size;
    const at_top = y < edge_size;
    const at_bottom = y >= h - edge_size;

    if (at_top and at_left) return wl.RESIZE_TOP_LEFT;
    if (at_top and at_right) return wl.RESIZE_TOP_RIGHT;
    if (at_bottom and at_left) return wl.RESIZE_BOTTOM_LEFT;
    if (at_bottom and at_right) return wl.RESIZE_BOTTOM_RIGHT;
    if (at_top) return wl.RESIZE_TOP;
    if (at_bottom) return wl.RESIZE_BOTTOM;
    if (at_left) return wl.RESIZE_LEFT;
    if (at_right) return wl.RESIZE_RIGHT;

    return wl.RESIZE_NONE;
}

fn screenToTextPos(gpu: *const GpuRenderer, text_buffer: *const GapBuffer, x: i32, y: i32, sx: i32, sy: i32, sidebar_visible: bool, sidebar_width: i32) ?usize {
    const editor_margin: i32 = gpu.scaledI(10);
    const editor_padding: i32 = gpu.scaledI(16);
    const content_y: i32 = @as(i32, @intCast(gpu.scaled(TITLEBAR_HEIGHT))) + editor_margin + editor_padding;
    const editor_left: i32 = if (sidebar_visible) sidebar_width + editor_margin else editor_margin;
    const code_screen_x: i32 = editor_left + gpu.scaledI(4) + @as(i32, @intCast(gpu.scaled(GUTTER_WIDTH))) + editor_padding - sx;
    const cw: i32 = @intCast(gpu.charWidth());
    const lh: i32 = @intCast(gpu.lineHeight());

    const adjusted_y = y + sy;
    if (adjusted_y < content_y or x < code_screen_x) return null;

    const click_line: usize = @intCast(@divTrunc(adjusted_y - content_y, lh));
    const click_col: usize = @intCast(@max(0, @divTrunc(x - code_screen_x, cw)));

    const buf_len = text_buffer.len();

    // Get line count for bounds check
    const line_count = text_buffer.lineCount();
    if (click_line >= line_count) {
        return buf_len;
    }

    // Get line start in O(1) using buffer's fast lookup
    var pos = text_buffer.getLineOffsetFast(click_line);

    // Find position in line (only within one line - fast)
    // Use text_cache directly if available
    if (text_buffer.text_cache_valid) {
        const text = text_buffer.text_cache;
        var col: usize = 0;
        while (pos < text.len and col < click_col) {
            if (text[pos] == '\n') break;
            col += 1;
            pos += 1;
        }
    } else {
        var col: usize = 0;
        while (pos < buf_len and col < click_col) {
            const ch = text_buffer.charAtConst(pos);
            if (ch == '\n') break;
            col += 1;
            pos += 1;
        }
    }

    return pos;
}

fn handleKeyAction(key: u32, char: ?u8, text_buffer: *GapBuffer, wayland: *Wayland, selection: *SelectionState, skip: u32) void {
    const shift_held = wayland.shift_held;
    const ctrl_held = wayland.ctrl_held;

    // Ctrl+A - select all
    if (ctrl_held and key == wl.KEY_A) {
        selection.anchor = 0;
        text_buffer.moveCursor(text_buffer.len());
        return;
    }

    // Ctrl+C - copy to system clipboard
    if (ctrl_held and key == wl.KEY_C) {
        if (selection.getRange(text_buffer.cursor())) |range| {
            copyToClipboardSystem(text_buffer, range.start, range.end, wayland);
        }
        return;
    }

    // Ctrl+X - cut
    if (ctrl_held and key == wl.KEY_X) {
        if (selection.getRange(text_buffer.cursor())) |range| {
            copyToClipboardSystem(text_buffer, range.start, range.end, wayland);
            deleteRange(text_buffer, range.start, range.end);
            selection.clear();
        }
        return;
    }

    // Ctrl+V - paste from system clipboard
    if (ctrl_held and key == wl.KEY_V) {
        // Delete selection if exists
        if (selection.getRange(text_buffer.cursor())) |range| {
            deleteRange(text_buffer, range.start, range.end);
            selection.clear();
        }
        // Try to paste from system clipboard
        var paste_buf: [64 * 1024]u8 = undefined;
        if (wayland.pasteFromClipboard(&paste_buf)) |data| {
            text_buffer.insertSlice(data) catch |e| logger.warn("Operation failed: {}", .{e});
        } else if (clipboard_len > 0) {
            // Fallback to internal buffer
            text_buffer.insertSlice(clipboard_buffer[0..clipboard_len]) catch |e| logger.warn("Operation failed: {}", .{e});
        }
        return;
    }

    // Navigation keys with shift handling
    if (key == wl.KEY_LEFT or key == wl.KEY_RIGHT or key == wl.KEY_UP or key == wl.KEY_DOWN) {
        // If shift held, start/extend selection
        if (shift_held) {
            if (selection.anchor == null) {
                selection.anchor = text_buffer.cursor();
            }
        } else {
            // If there was selection without shift, jump to selection edge
            if (selection.getRange(text_buffer.cursor())) |range| {
                if (key == wl.KEY_LEFT or key == wl.KEY_UP) {
                    text_buffer.moveCursor(range.start);
                } else {
                    text_buffer.moveCursor(range.end);
                }
                selection.clear();
                return;
            }
            selection.clear();
        }

        // Execute movement
        if (key == wl.KEY_LEFT) {
            const pos = text_buffer.cursor();
            if (pos >= skip) text_buffer.moveCursor(pos - skip) else text_buffer.moveCursor(0);
        } else if (key == wl.KEY_RIGHT) {
            const pos = text_buffer.cursor();
            const new_pos = pos + skip;
            if (new_pos <= text_buffer.len()) text_buffer.moveCursor(new_pos) else text_buffer.moveCursor(text_buffer.len());
        } else if (key == wl.KEY_UP) {
            moveLines(text_buffer, skip, true);
        } else if (key == wl.KEY_DOWN) {
            moveLines(text_buffer, skip, false);
        }
        return;
    }

    // Backspace/Delete - delete selection if exists
    if (key == wl.KEY_BACKSPACE) {
        if (selection.getRange(text_buffer.cursor())) |range| {
            deleteRange(text_buffer, range.start, range.end);
            selection.clear();
        } else {
            var i: u32 = 0;
            while (i < skip) : (i += 1) text_buffer.deleteBack();
        }
        return;
    }

    if (key == wl.KEY_DELETE) {
        if (selection.getRange(text_buffer.cursor())) |range| {
            deleteRange(text_buffer, range.start, range.end);
            selection.clear();
        } else {
            var i: u32 = 0;
            while (i < skip) : (i += 1) text_buffer.deleteForward();
        }
        return;
    }

    if (key == wl.KEY_ESC) {
        wayland.running = false;
        return;
    }

    // Character input - replaces selection (but don't input with Ctrl)
    if (char) |ch| {
        if (ctrl_held) return; // Don't input characters when Ctrl is held
        if (selection.getRange(text_buffer.cursor())) |range| {
            deleteRange(text_buffer, range.start, range.end);
            selection.clear();
        }
        text_buffer.insert(ch) catch |e| logger.warn("Operation failed: {}", .{e});
    }
}

fn deleteRange(text_buffer: *GapBuffer, start: usize, end: usize) void {
    // Move cursor to range start and delete forward
    text_buffer.moveCursor(start);
    var i: usize = 0;
    while (i < end - start) : (i += 1) {
        text_buffer.deleteForward();
    }
}

/// Finds all occurrences of query in text_buffer and saves positions in matches
fn performSearch(text_buffer: *const GapBuffer, query: []const u8, matches: *[4096]usize) usize {
    if (query.len == 0) return 0;

    var match_count: usize = 0;
    const text_len = text_buffer.len();
    if (text_len < query.len) return 0;

    var pos: usize = 0;
    while (pos <= text_len - query.len) : (pos += 1) {
        var found = true;
        for (query, 0..) |qch, qi| {
            const tch = text_buffer.charAtConst(pos + qi) orelse {
                found = false;
                break;
            };
            // Case-insensitive comparison
            const q_lower = if (qch >= 'A' and qch <= 'Z') qch + 32 else qch;
            const t_lower = if (tch >= 'A' and tch <= 'Z') tch + 32 else tch;
            if (q_lower != t_lower) {
                found = false;
                break;
            }
        }
        if (found) {
            if (match_count < matches.len) {
                matches[match_count] = pos;
                match_count += 1;
            }
            // Skip found match
            pos += query.len - 1;
        }
    }
    return match_count;
}

/// Finds index of nearest match to cursor position
fn findNearestMatch(matches: []const usize, cursor_pos: usize) usize {
    if (matches.len == 0) return 0;

    var nearest: usize = 0;
    var min_dist: usize = if (cursor_pos >= matches[0]) cursor_pos - matches[0] else matches[0] - cursor_pos;

    for (matches, 0..) |m, i| {
        const dist = if (cursor_pos >= m) cursor_pos - m else m - cursor_pos;
        if (dist < min_dist) {
            min_dist = dist;
            nearest = i;
        }
    }
    return nearest;
}

fn copyToClipboard(text_buffer: *const GapBuffer, start: usize, end: usize) void {
    const len = end - start;
    if (len > clipboard_buffer.len) {
        clipboard_len = clipboard_buffer.len;
    } else {
        clipboard_len = len;
    }

    var i: usize = 0;
    while (i < clipboard_len) : (i += 1) {
        if (text_buffer.charAtConst(start + i)) |ch| {
            clipboard_buffer[i] = ch;
        }
    }
}

fn copyToClipboardSystem(text_buffer: *const GapBuffer, start: usize, end: usize, wayland: *Wayland) void {
    const len = end - start;
    const actual_len = @min(len, clipboard_buffer.len);

    // Copy to internal buffer for fallback
    var i: usize = 0;
    while (i < actual_len) : (i += 1) {
        if (text_buffer.charAtConst(start + i)) |ch| {
            clipboard_buffer[i] = ch;
        }
    }
    clipboard_len = actual_len;

    // Copy to system clipboard
    wayland.copyToClipboard(clipboard_buffer[0..clipboard_len]);
}

fn moveLines(text_buffer: *GapBuffer, lines: u32, up: bool) void {
    const cur_pos = text_buffer.cursorPositionConst();
    var target_line: usize = cur_pos.line;

    if (up) {
        if (cur_pos.line >= lines) {
            target_line = cur_pos.line - lines;
        } else {
            target_line = 0;
        }
    } else {
        target_line = cur_pos.line + lines;
    }

    // Find position in target line
    var pos: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (pos < text_buffer.len()) : (pos += 1) {
        if (line == target_line and col >= cur_pos.col) break;
        if (text_buffer.charAtConst(pos) == '\n') {
            if (line == target_line) break;
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    }

    text_buffer.moveCursor(pos);
}

fn render(gpu: *GpuRenderer, text_buffer: *const GapBuffer, wayland: *const Wayland, selection: *const SelectionState, scroll_x: i32, scroll_y: i32, sidebar_visible: bool, sidebar_width: i32, sidebar_active_tab: usize, sidebar_tab_hovered: i32, open_folder_btn_hovered: bool, sidebar_resize_hovered: bool, menu_hover: i32, menu_open: i32, menu_item_hover: i32, settings_visible: bool, settings_active_tab: u8, settings_tab_hovered: i8, settings_checkbox_hovered: bool, folder_files: *const [256][256]u8, folder_file_lens: *const [256]usize, folder_file_count: usize, folder_is_dir: *const [256]bool, folder_expanded: *const [256]bool, folder_anim_progress: *const [256]f32, folder_indent: *const [256]u8, explorer_selected: i32, explorer_hovered: i32, explorer_scroll: i32, current_folder_len: usize, tab_names: *const [16][64]u8, tab_name_lens: *const [16]usize, tab_modified: *const [16]bool, tab_count: usize, active_tab: usize, tab_hovered: i32, tab_close_hovered: i32, tab_paths: *const [16][512]u8, tab_path_lens: *const [16]usize, tab_is_plugin: *const [16]bool, tab_plugin_idx: *const [16]usize, plugin_hovered: i32, search_visible: bool, search_query: []const u8, search_cursor: usize, search_match_count: usize, search_current_match: usize, search_matches: *const [4096]usize, editor_focused: bool) void {
    // Transparent background for rounded corners
    gpu.clear(0x00000000);

    // Get scaled UI element sizes
    const zoom = gpu.getZoom();
    const titlebar_h = gpu.scaled(TITLEBAR_HEIGHT);
    const tab_bar_h: u32 = @intCast(g_tab_bar_height);
    const corner_r = gpu.scaled(CORNER_RADIUS);
    const gutter_w = gpu.scaled(GUTTER_WIDTH);
    const ui_margin = gpu.scaledI(@as(i32, EDITOR_MARGIN));
    const ui_padding = gpu.scaledI(@as(i32, EDITOR_PADDING));

    // Rounded window background
    gpu.fillRoundedRect(0, 0, wayland.width, wayland.height, corner_r, COLOR_BG);

    // Titlebar with menu
    drawTitlebar(gpu, wayland.width, wayland.mouse_x, wayland.mouse_y, menu_hover, wayland.maximized, zoom);

    const line_height: i32 = @intCast(gpu.lineHeight());
    const char_width: i32 = @intCast(gpu.charWidth());

    // Editor starts after titlebar and sidebar (with padding)
    const editor_margin: i32 = ui_margin;
    const editor_padding: i32 = ui_padding;
    const titlebar_gap: i32 = ui_margin; // 10px gap from titlebar
    const editor_top: i32 = @as(i32, @intCast(titlebar_h)) + titlebar_gap;
    const editor_left: i32 = if (sidebar_visible) sidebar_width + editor_margin else editor_margin;
    const editor_right: i32 = @as(i32, @intCast(wayland.width)) - editor_margin;
    // Bottom panel reduces editor height
    const panel_space: i32 = if (g_bottom_panel_visible) g_bottom_panel_height + 4 else 0;
    const editor_bottom: i32 = @as(i32, @intCast(wayland.height)) - editor_margin - @as(i32, @intCast(tab_bar_h)) - 10 - panel_space;
    const editor_w: u32 = @intCast(editor_right - editor_left);
    const editor_h: u32 = @intCast(@max(100, editor_bottom - editor_top));

    // Soft shadow for editor
    gpu.drawSoftShadow(editor_left, editor_top, editor_w, editor_h, 12, 3, 4, 20, 70);

    // Rounded text field background
    gpu.fillRoundedRect(editor_left, editor_top, editor_w, editor_h, 12, COLOR_GUTTER);

    // Enable scissor to clip content to editor bounds
    gpu.setScissor(editor_left, editor_top, editor_w, editor_h);

    // Check if plugin tab is open
    if (tab_is_plugin[active_tab]) {
        // === Rendering plugin details ===
        const plugin_idx_render = tab_plugin_idx[active_tab];
        const loader = plugins.getLoader();
        if (plugin_idx_render < loader.plugin_count) {
            const plugin_info = &loader.plugins[plugin_idx_render].info;

            var py: i32 = editor_top + editor_padding + 10;
            const px: i32 = editor_left + editor_padding + 20;

            // Plugin title
            const pname = plugin_info.getName();
            gpu.drawUIText(pname, px, py, 0xFFffffff);
            py += 30;

            // Version
            const pversion = plugin_info.getVersion();
            if (pversion.len > 0) {
                gpu.drawUIText("Version: ", px, py, COLOR_TEXT_DIM);
                gpu.drawUIText(pversion, px + 80, py, COLOR_TEXT);
                py += 24;
            }

            // Author
            const pauthor = plugin_info.getAuthor();
            if (pauthor.len > 0) {
                gpu.drawUIText("Author: ", px, py, COLOR_TEXT_DIM);
                gpu.drawUIText(pauthor, px + 80, py, COLOR_TEXT);
                py += 24;
            }

            // Extensions
            const pext = plugin_info.getExtensions();
            if (pext.len > 0) {
                gpu.drawUIText("Extensions: ", px, py, COLOR_TEXT_DIM);
                gpu.drawUIText(pext, px + 110, py, COLOR_ACCENT);
                py += 24;
            }

            py += 16;

            // Description
            const pdesc = plugin_info.getDescription();
            if (pdesc.len > 0) {
                gpu.drawUIText("Description:", px, py, COLOR_TEXT_DIM);
                py += 22;
                // Simple line wrapping (every 80 characters)
                var desc_start: usize = 0;
                var line_count: usize = 0;
                while (desc_start < pdesc.len and line_count < 10) : (line_count += 1) {
                    const remaining = pdesc.len - desc_start;
                    const line_len = @min(remaining, 80);
                    gpu.drawUIText(pdesc[desc_start..][0..line_len], px + 10, py, COLOR_TEXT);
                    py += 20;
                    desc_start += line_len;
                }
            }

            py += 30;

            // Capabilities
            gpu.drawUIText("Capabilities:", px, py, COLOR_TEXT_DIM);
            py += 24;
            if (plugin_info.has_syntax) {
                gpu.drawUIText("  • Syntax Highlighting", px, py, 0xFF6bff6b);
                py += 20;
            }
            if (plugin_info.has_lsp) {
                gpu.drawUIText("  • LSP Support", px, py, 0xFF6bff6b);
                py += 20;
            }
            if (plugin_info.has_run) {
                gpu.drawUIText("  • Run Command", px, py, 0xFF6bff6b);
                py += 20;
            }

            py += 40;

            // === Management Buttons ===
            const btn_w: i32 = 100;
            const btn_h: i32 = 28;
            const btn_spacing: i32 = 12;

            // Get plugin path for management operations
            const plugin_path = loader.plugins[plugin_idx_render].path;

            // Check if plugin is disabled
            const is_disabled = plugins.isPluginDisabled(plugin_path[0..loader.plugins[plugin_idx_render].path_len]);

            // Disable/Enable button
            const disable_btn_x = px;
            const disable_btn_y = py;
            g_plugin_disable_btn_rect = .{ .x = disable_btn_x, .y = disable_btn_y, .w = btn_w, .h = btn_h };

            // Check hover
            g_plugin_disable_btn_hovered = wayland.mouse_x >= disable_btn_x and
                wayland.mouse_x < disable_btn_x + btn_w and
                wayland.mouse_y >= disable_btn_y and
                wayland.mouse_y < disable_btn_y + btn_h;

            if (g_plugin_disable_btn_hovered) {
                const glow_color: u32 = if (is_disabled) 0xFF6bff6b else 0xFFd0a080;
                gpu.drawGlow(disable_btn_x, disable_btn_y, @intCast(btn_w), @intCast(btn_h), 4, glow_color, 12);
            }
            const disable_btn_bg: u32 = if (g_plugin_disable_btn_hovered)
                (if (is_disabled) 0xFF3a5a3a else 0xFF4a4a4a)
            else
                (if (is_disabled) 0xFF2a4a2a else 0xFF3a3a3a);

            gpu.fillRoundedRect(disable_btn_x, disable_btn_y, @intCast(btn_w), @intCast(btn_h), 4, disable_btn_bg);
            const disable_text = if (is_disabled) "Enable" else "Disable";
            const disable_text_x = disable_btn_x + @divTrunc(btn_w - @as(i32, @intCast(disable_text.len * 8)), 2);
            gpu.drawUIText(disable_text, disable_text_x, disable_btn_y + 6, if (is_disabled) 0xFF6bff6b else COLOR_TEXT);

            // Uninstall button
            const uninstall_btn_x = px + btn_w + btn_spacing;
            const uninstall_btn_y = py;
            g_plugin_uninstall_btn_rect = .{ .x = uninstall_btn_x, .y = uninstall_btn_y, .w = btn_w, .h = btn_h };

            g_plugin_uninstall_btn_hovered = wayland.mouse_x >= uninstall_btn_x and
                wayland.mouse_x < uninstall_btn_x + btn_w and
                wayland.mouse_y >= uninstall_btn_y and
                wayland.mouse_y < uninstall_btn_y + btn_h;

            if (g_plugin_uninstall_btn_hovered) {
                gpu.drawGlow(uninstall_btn_x, uninstall_btn_y, @intCast(btn_w), @intCast(btn_h), 4, 0xFFff6b6b, 12);
            }
            const uninstall_btn_bg: u32 = if (g_plugin_uninstall_btn_hovered) 0xFF6a3a3a else 0xFF4a2a2a;
            gpu.fillRoundedRect(uninstall_btn_x, uninstall_btn_y, @intCast(btn_w), @intCast(btn_h), 4, uninstall_btn_bg);
            const uninstall_text = "Uninstall";
            const uninstall_text_x = uninstall_btn_x + @divTrunc(btn_w - @as(i32, @intCast(uninstall_text.len * 8)), 2);
            gpu.drawUIText(uninstall_text, uninstall_text_x, uninstall_btn_y + 6, 0xFFff6b6b);
        }
        gpu.clearScissor();
    } else {
    // Entire text field moves together with scroll_x
    const field_offset_x: i32 = editor_left - scroll_x;
    const gutter_x: i32 = field_offset_x + 4; // +4 for left gutter padding
    const gutter_w_i: i32 = @intCast(gutter_w);
    const code_start_x: i32 = gutter_x + gutter_w_i + editor_padding;

    // Separator between line numbers and code
    const sep_x: i32 = gutter_x + gutter_w_i;
    if (sep_x >= editor_left and sep_x < editor_right) {
        const sep_height: u32 = @intCast(@as(i32, @intCast(editor_h)) - editor_padding * 2);
        gpu.fillRect(sep_x, editor_top + editor_padding, 1, sep_height, COLOR_ACCENT_DIM);
    }

    // Use pre-cached cursor position (computed before render call)
    const cursor_pos = .{ .line = g_cursor_cache_line, .col = g_cursor_cache_col };
    const sel_range = selection.getRange(text_buffer.cursor());

    // === VIRTUALIZATION: Draw only visible lines + buffer ===
    const visible_height: i32 = editor_bottom - editor_top - editor_padding * 2;
    const render_buffer: usize = 12; // Line buffer above and below
    const raw_first_line: i32 = @divTrunc(scroll_y, line_height);
    const first_visible_line: usize = @intCast(@max(0, raw_first_line - @as(i32, @intCast(render_buffer))));
    const visible_line_count: usize = @as(usize, @intCast(@max(1, @divTrunc(visible_height, line_height)))) + render_buffer * 2;

    // Syntax highlighting state
    const current_file_type: FileType = if (tab_count > 0 and tab_path_lens[active_tab] > 0)
        detectFileType(tab_paths[active_tab][0..tab_path_lens[active_tab]])
    else
        .unknown;
    var in_multiline_comment: bool = false;
    var tokens_buf: [128]Token = undefined;
    var line_buf: [2048]u8 = undefined;

    // Get offset of first visible line - O(1) via buffer's line_starts
    const line_offset: usize = text_buffer.getLineOffsetFast(first_visible_line);

    // Update global cache for compatibility
    const buf_len = text_buffer.len();
    if (buf_len != g_cached_buf_len) {
        g_cached_buf_len = buf_len;
        g_cached_line_count = text_buffer.lineCount();
        // Don't recalculate max line length every frame - too expensive
        // g_cached_max_line_len = text_buffer.maxLineLengthConst();
    }
    if (first_visible_line > 0) {
        g_cached_line = first_visible_line;
        g_cached_offset = line_offset;
    } else {
        g_cached_line = 0;
        g_cached_offset = 0;
    }

    // Use cached values
    const total_lines: usize = g_cached_line_count;

    // Draw only visible lines
    var current_line: usize = first_visible_line;
    var i: usize = line_offset;
    const last_visible_line = first_visible_line + visible_line_count;
    const buffer_total = text_buffer.len();

    const lines_start = std.time.milliTimestamp();
    var lines_drawn: usize = 0;
    var total_copy_time: i64 = 0;

    while (current_line < last_visible_line and current_line < total_lines) {
        lines_drawn += 1;
        // Protection from infinite loop
        if (i >= buffer_total) break;

        // Get line
        const copy_start = std.time.milliTimestamp();
        const line_result = text_buffer.copyLineConst(i, &line_buf);
        total_copy_time += std.time.milliTimestamp() - copy_start;
        const line_len = line_result.line_len;

        // Protection from infinite loop - offset must advance
        if (line_result.next_offset <= i and line_len == 0) break;

        // Calculate Y position
        const y: i32 = editor_top + editor_padding + @as(i32, @intCast(current_line)) * line_height - scroll_y;

        // Skip lines outside visible area
        if (y + line_height >= editor_top and y < editor_bottom) {
            // Current line highlight
            if (current_line == cursor_pos.line) {
                const hl_x = @max(editor_left + 8, sep_x + 1);
                const hl_end = editor_right - 8;
                if (hl_x < hl_end) {
                    gpu.fillRoundedRect(hl_x, y, @intCast(hl_end - hl_x), @intCast(line_height), 4, 0xFF252525);
                }
            }

            // Selection
            if (sel_range) |range| {
                const line_start_offset = i;
                const line_end_offset = i + line_len;
                if (range.start < line_end_offset and range.end > line_start_offset) {
                    const sel_start_in_line = if (range.start > line_start_offset) range.start - line_start_offset else 0;
                    const sel_end_in_line = if (range.end < line_end_offset) range.end - line_start_offset else line_len;

                    const sel_x: i32 = code_start_x + @as(i32, @intCast(sel_start_in_line)) * char_width;
                    const sel_width: u32 = @intCast((sel_end_in_line - sel_start_in_line) * @as(usize, @intCast(char_width)));

                    if (sel_width > 0) {
                        gpu.fillRect(sel_x, y, sel_width, @intCast(line_height), COLOR_SELECTION);
                    }
                }
            }

            // Search match highlight
            if (search_visible and search_match_count > 0 and search_query.len > 0) {
                const line_start_offset = i;
                const line_end_offset = i + line_len;
                for (search_matches[0..search_match_count], 0..) |match_pos, match_idx| {
                    const match_end = match_pos + search_query.len;
                    // Check if match falls on current line
                    if (match_pos < line_end_offset and match_end > line_start_offset) {
                        const match_start_in_line = if (match_pos > line_start_offset) match_pos - line_start_offset else 0;
                        const match_end_in_line = if (match_end < line_end_offset) match_end - line_start_offset else line_len;

                        const match_x: i32 = code_start_x + @as(i32, @intCast(match_start_in_line)) * char_width;
                        const match_width: u32 = @intCast((match_end_in_line - match_start_in_line) * @as(usize, @intCast(char_width)));

                        if (match_width > 0) {
                            // Current match - brighter
                            const match_color: u32 = if (match_idx == search_current_match) 0xFF4a6a40 else 0xFF3a4a35;
                            gpu.fillRect(match_x, y, match_width, @intCast(line_height), match_color);
                        }
                    }
                }
            }

            // Line number
            const num_x: i32 = gutter_x + 4;
            var num_buf: [8]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, "{d: >4}", .{current_line + 1}) catch "????";
            const num_color = if (current_line == cursor_pos.line) COLOR_ACCENT else COLOR_TEXT_DIM;
            gpu.drawText(num_str, num_x, y, num_color);

            // Line text with syntax highlighting (with caching)
            if (line_len > 0) {
                const line_hash = simpleHash(line_buf[0..line_len]);
                const cache_idx = current_line % MAX_CACHED_LINES;
                var cache_entry = &g_token_cache[cache_idx];

                if (current_file_type == .zig) {
                    // Check cache
                    var token_count: usize = 0;
                    var cached_tokens: []Token = undefined;

                    if (cache_entry.line_hash == line_hash and !cache_entry.is_plugin and cache_entry.count > 0 and cache_entry.in_multiline_comment == in_multiline_comment) {
                        // Use cache
                        token_count = cache_entry.count;
                        cached_tokens = cache_entry.tokens[0..token_count];
                    } else {
                        // Tokenize and cache
                        const result = tokenizeLine(line_buf[0..line_len], &tokens_buf, in_multiline_comment);
                        in_multiline_comment = result.still_in_comment;
                        token_count = result.count;

                        // Save to cache
                        if (token_count <= MAX_TOKENS_PER_LINE) {
                            @memcpy(cache_entry.tokens[0..token_count], tokens_buf[0..token_count]);
                            cache_entry.count = @intCast(token_count);
                            cache_entry.line_hash = line_hash;
                            cache_entry.is_plugin = false;
                            cache_entry.in_multiline_comment = !result.still_in_comment; // State BEFORE line
                        }
                        cached_tokens = tokens_buf[0..token_count];
                    }

                    if (token_count > 0) {
                        var last_end: usize = 0;
                        for (cached_tokens) |token| {
                            if (token.start > last_end) {
                                const space_x = code_start_x + @as(i32, @intCast(last_end)) * char_width;
                                gpu.drawText(line_buf[last_end..token.start], space_x, y, COLOR_TEXT);
                            }
                            const token_x = code_start_x + @as(i32, @intCast(token.start)) * char_width;
                            const token_color = getTokenColor(token.token_type);
                            gpu.drawText(line_buf[token.start .. token.start + token.len], token_x, y, token_color);
                            last_end = token.start + token.len;
                        }
                        if (last_end < line_len) {
                            const rest_x = code_start_x + @as(i32, @intCast(last_end)) * char_width;
                            gpu.drawText(line_buf[last_end..line_len], rest_x, y, COLOR_TEXT);
                        }
                    } else {
                        gpu.drawText(line_buf[0..line_len], code_start_x, y, COLOR_TEXT);
                    }
                } else {
                    // Try to highlighting via WASM plugin
                    const loader = plugins.getLoader();
                    const file_path_for_plugin = if (tab_path_lens[active_tab] > 0)
                        tab_paths[active_tab][0..tab_path_lens[active_tab]]
                    else
                        "";

                    if (loader.findPluginForFile(file_path_for_plugin)) |plugin_idx| {
                        var token_count: usize = 0;
                        var cached_plugin_tokens: []plugins.WasmToken = undefined;

                        // Check cache for plugin
                        if (cache_entry.line_hash == line_hash and cache_entry.is_plugin and cache_entry.count > 0) {
                            token_count = cache_entry.count;
                            cached_plugin_tokens = cache_entry.plugin_tokens[0..token_count];
                        } else {
                            // Tokenize via plugin
                            var plugin_tokens: [256]plugins.WasmToken = undefined;
                            token_count = loader.tokenize(plugin_idx, line_buf[0..line_len], &plugin_tokens);

                            // Save to cache
                            if (token_count <= MAX_TOKENS_PER_LINE) {
                                @memcpy(cache_entry.plugin_tokens[0..token_count], plugin_tokens[0..token_count]);
                                cache_entry.count = @intCast(token_count);
                                cache_entry.line_hash = line_hash;
                                cache_entry.is_plugin = true;
                            }
                            cached_plugin_tokens = plugin_tokens[0..token_count];
                        }

                        if (token_count > 0) {
                            var last_end: usize = 0;
                            for (cached_plugin_tokens) |ptok| {
                                const tok_start: usize = @intCast(ptok.start);
                                const tok_len: usize = @intCast(ptok.len);

                                if (tok_start > last_end) {
                                    const space_x = code_start_x + @as(i32, @intCast(last_end)) * char_width;
                                    gpu.drawText(line_buf[last_end..tok_start], space_x, y, COLOR_TEXT);
                                }

                                const tok_type = plugin_api.mapSimpleToken(ptok.kind);
                                const tok_color = plugin_api.getDefaultTokenColor(tok_type);
                                const token_x = code_start_x + @as(i32, @intCast(tok_start)) * char_width;
                                const tok_end = @min(tok_start + tok_len, line_len);
                                gpu.drawText(line_buf[tok_start..tok_end], token_x, y, tok_color);
                                last_end = tok_end;
                            }
                            if (last_end < line_len) {
                                const rest_x = code_start_x + @as(i32, @intCast(last_end)) * char_width;
                                gpu.drawText(line_buf[last_end..line_len], rest_x, y, COLOR_TEXT);
                            }
                        } else {
                            gpu.drawText(line_buf[0..line_len], code_start_x, y, COLOR_TEXT);
                        }
                    } else {
                        gpu.drawText(line_buf[0..line_len], code_start_x, y, COLOR_TEXT);
                    }
                }
            }

            // Bracket matching highlight (for Zig files)
            if (current_file_type == .zig and editor_focused) {
                const cursor_byte_pos = text_buffer.cursor();
                // Check bracket under or before cursor
                const check_positions = [_]usize{
                    cursor_byte_pos,
                    if (cursor_byte_pos > 0) cursor_byte_pos - 1 else cursor_byte_pos,
                };

                for (check_positions) |check_pos| {
                    if (findMatchingBracket(text_buffer, check_pos)) |match_pos| {
                        // Find positions to highlight
                        const pos1_info = getByteLineCol(text_buffer, check_pos);
                        const pos2_info = getByteLineCol(text_buffer, match_pos);

                        // Highlight if on current line
                        if (pos1_info.line == current_line) {
                            const bx1 = code_start_x + @as(i32, @intCast(pos1_info.col)) * char_width;
                            gpu.fillRect(bx1, y, @intCast(char_width), @intCast(line_height), 0x40ffb4a2);
                        }
                        if (pos2_info.line == current_line) {
                            const bx2 = code_start_x + @as(i32, @intCast(pos2_info.col)) * char_width;
                            gpu.fillRect(bx2, y, @intCast(char_width), @intCast(line_height), 0x40ffb4a2);
                        }
                        break;
                    }
                }
            }

            // Cursor (only if editor is focused)
            if (current_line == cursor_pos.line and editor_focused) {
                const cursor_x = code_start_x + @as(i32, @intCast(cursor_pos.col)) * char_width;
                gpu.fillRoundedRect(cursor_x, y, 2, @intCast(line_height), 1, COLOR_CURSOR);
            }

            // Line separator (if visibility > 0)
            if (g_line_visibility > 0.01) {
                const line_sep_y = y + line_height - 1;
                const line_sep_x = code_start_x;
                const line_sep_w: u32 = @intCast(@max(1, editor_right - line_sep_x - 8));
                // Alpha based on visibility (0-255)
                const alpha: u32 = @intFromFloat(g_line_visibility * 40); // max 40 alpha for subtle effect
                const line_color: u32 = (alpha << 24) | 0x808080; // Gray with variable alpha
                gpu.fillRect(line_sep_x, line_sep_y, line_sep_w, 1, line_color);
            }
        }

        // Move to next line
        i = line_result.next_offset;
        current_line += 1;
    }

    const lines_end = std.time.milliTimestamp();
    if (lines_end - lines_start > 10) {
        logger.debug("[RENDER] Lines: {}ms total, copy={}ms, {} lines\n", .{lines_end - lines_start, total_copy_time, lines_drawn});
    }

    // For scrollbars use cached value
    const max_line_len: usize = g_cached_max_line_len;

    // Disable scissor after rendering editor content
    gpu.clearScissor();

    // === Scrollbars (inside editor) ===
    const scrollbar_size: u32 = gpu.scaled(8);
    const scrollbar_padding: i32 = gpu.scaledI(4);
    const mouse_x = wayland.mouse_x;
    const mouse_y = wayland.mouse_y;

    // Horizontal scrollbar (at bottom of editor block)
    const full_content_width: i32 = @as(i32, @intCast(gutter_w)) + gpu.scaledI(12) + @as(i32, @intCast(max_line_len)) * char_width + char_width * 10;
    const full_visible_width: i32 = @as(i32, @intCast(editor_w)) - @as(i32, @intCast(scrollbar_size)) - gpu.scaledI(16);

    if (full_content_width > full_visible_width or scroll_x > 0) {
        const hbar_y: i32 = editor_bottom - @as(i32, @intCast(scrollbar_size)) - scrollbar_padding;
        const hbar_width: u32 = editor_w - scrollbar_size - gpu.scaled(16);
        const hbar_x: i32 = editor_left + gpu.scaledI(8);

        // Check hover
        const hbar_hovered = mouse_x >= hbar_x and mouse_x < hbar_x + @as(i32, @intCast(hbar_width)) and
            mouse_y >= hbar_y and mouse_y < hbar_y + @as(i32, @intCast(scrollbar_size));

        // Background (highlighted on hover)
        const hbar_bg: u32 = if (hbar_hovered) 0xFF3a3a3a else 0xFF2a2a2a;
        gpu.fillRoundedRect(hbar_x, hbar_y, hbar_width, scrollbar_size, 5, hbar_bg);

        // Thumb (size proportional to visible area)
        const total_w = @max(full_content_width, full_visible_width);
        const thumb_ratio = @min(1.0, @as(f32, @floatFromInt(full_visible_width)) / @as(f32, @floatFromInt(total_w)));
        const thumb_w: u32 = @max(24, @as(u32, @intFromFloat(@as(f32, @floatFromInt(hbar_width)) * thumb_ratio)));
        const max_scroll_x_local = @max(1, total_w - full_visible_width);
        const scroll_pct_x = @min(1.0, @as(f32, @floatFromInt(scroll_x)) / @as(f32, @floatFromInt(max_scroll_x_local)));
        const thumb_x: i32 = hbar_x + @as(i32, @intFromFloat(scroll_pct_x * @as(f32, @floatFromInt(hbar_width - thumb_w))));

        // Thumb highlight on hover
        const thumb_hovered = mouse_x >= thumb_x and mouse_x < thumb_x + @as(i32, @intCast(thumb_w)) and
            mouse_y >= hbar_y and mouse_y < hbar_y + @as(i32, @intCast(scrollbar_size));
        const hthumb_color: u32 = if (thumb_hovered) 0xFFffc4b2 else COLOR_ACCENT;

        gpu.fillRoundedRect(thumb_x, hbar_y, thumb_w, scrollbar_size, 5, hthumb_color);
    }

    // Vertical scrollbar (right inside editor)
    const content_height: i32 = @as(i32, @intCast(total_lines)) * line_height;
    const vbar_visible_h: i32 = @as(i32, @intCast(editor_h)) - @as(i32, @intCast(scrollbar_size)) - 16;

    if (content_height > vbar_visible_h) {
        const vbar_x: i32 = editor_right - @as(i32, @intCast(scrollbar_size)) - scrollbar_padding;
        const vbar_y: i32 = editor_top + 8;
        const vbar_height: u32 = editor_h - scrollbar_size - 16;

        // Check hover
        const vbar_hovered = mouse_x >= vbar_x and mouse_x < vbar_x + @as(i32, @intCast(scrollbar_size)) and
            mouse_y >= vbar_y and mouse_y < vbar_y + @as(i32, @intCast(vbar_height));

        // Background
        const vbar_bg: u32 = if (vbar_hovered) 0xFF3a3a3a else 0xFF2a2a2a;
        gpu.fillRoundedRect(vbar_x, vbar_y, scrollbar_size, vbar_height, 5, vbar_bg);

        // Thumb
        const total_h = @max(content_height, vbar_visible_h);
        const vthumb_ratio = @min(1.0, @as(f32, @floatFromInt(vbar_visible_h)) / @as(f32, @floatFromInt(total_h)));
        const vthumb_h: u32 = @max(24, @as(u32, @intFromFloat(@as(f32, @floatFromInt(vbar_height)) * vthumb_ratio)));
        const max_scroll_y = @max(1, total_h - vbar_visible_h);
        const scroll_pct_y = @min(1.0, @as(f32, @floatFromInt(scroll_y)) / @as(f32, @floatFromInt(max_scroll_y)));
        const vthumb_y: i32 = vbar_y + @as(i32, @intFromFloat(scroll_pct_y * @as(f32, @floatFromInt(vbar_height - vthumb_h))));

        // Thumb highlight on hover
        const vthumb_hovered = mouse_x >= vbar_x and mouse_x < vbar_x + @as(i32, @intCast(scrollbar_size)) and
            mouse_y >= vthumb_y and mouse_y < vthumb_y + @as(i32, @intCast(vthumb_h));
        const vthumb_color: u32 = if (vthumb_hovered) 0xFFffc4b2 else COLOR_ACCENT;

        gpu.fillRoundedRect(vbar_x, vthumb_y, scrollbar_size, vthumb_h, 5, vthumb_color);
    }
    } // end else (not plugin tab)

    // === Sidebar (rounded block with soft shadow) ===
    if (sidebar_visible) {
        const sidebar_margin_s: i32 = ui_margin;
        const sidebar_padding: i32 = ui_padding;
        const sidebar_x: i32 = sidebar_margin_s;
        const sidebar_y: i32 = @as(i32, @intCast(titlebar_h)) + ui_margin; // 10px from titlebar
        const sidebar_w: u32 = @intCast(sidebar_width - sidebar_margin_s * 2);
        const sidebar_h: u32 = wayland.height - titlebar_h - @as(u32, @intCast(sidebar_margin_s)) * 2;

        // Soft shadow for sidebar
        gpu.drawSoftShadow(sidebar_x, sidebar_y, sidebar_w, sidebar_h, 12, 3, 4, 20, 80);

        // Main block - dark gray with light peach tint
        gpu.fillRoundedRect(sidebar_x, sidebar_y, sidebar_w, sidebar_h, 12, 0xFF252220);

        // === Resize bar (right edge of sidebar) - small handle in center ===
        // Handle is drawn at end of sidebar block

        // === Sidebar Tabs (with SVG icons) ===
        const stab_y: i32 = sidebar_y + 8;
        const stab_h: u32 = 24;
        const tab_w: u32 = 32; // Square tabs for icons
        var stab_x: i32 = sidebar_x + 8;

        const tab_icons_list = [_]icons.IconType{ .files, .search, .git, .plugin };

        for (tab_icons_list, 0..) |icon_type, tab_i| {
            const is_active = sidebar_active_tab == tab_i;
            const is_hovered = sidebar_tab_hovered == @as(i32, @intCast(tab_i));
            const icon_color: u32 = if (is_active) 0xFFd0a080 else if (is_hovered) 0xFFa08060 else 0xFF707070;

            // Tab background + glow on hover
            if (is_active) {
                gpu.fillRoundedRect(stab_x, stab_y, tab_w, stab_h, 6, 0xFF3d3028);
            } else if (is_hovered) {
                gpu.drawGlow(stab_x, stab_y, tab_w, stab_h, 6, 0xFFd0a080, 15);
                gpu.fillRoundedRect(stab_x, stab_y, tab_w, stab_h, 6, 0xFF302820);
            }

            // SVG icon
            icons.drawIcon(gpu, icon_type, stab_x + 8, stab_y + 4, 16, icon_color);

            stab_x += @as(i32, @intCast(tab_w)) + 4;
        }

        // Separator under tabs
        gpu.fillRect(sidebar_x + 8, stab_y + @as(i32, @intCast(stab_h)) + 4, sidebar_w - 16, 1, 0xFF3a3530);

        // Header - active tab name
        const header_y = stab_y + @as(i32, @intCast(stab_h)) + 12;
        const header_text = if (sidebar_active_tab == 0) "EXPLORER" else if (sidebar_active_tab == 1) "SEARCH" else if (sidebar_active_tab == 2) "SOURCE CONTROL" else "PLUGINS";
        gpu.drawUIText(header_text, sidebar_x + sidebar_padding, header_y, 0xFFb08060);

        // File manager buttons (only when folder is open)
        if (sidebar_active_tab == 0 and current_folder_len > 0) {
            const btn_size: u32 = 22;
            const icon_size: u32 = 16;
            const btn_spacing: i32 = 2;
            const btns_y: i32 = header_y - 4;
            var btn_x: i32 = sidebar_x + @as(i32, @intCast(sidebar_w)) - sidebar_padding - @as(i32, @intCast(btn_size)) * 3 - btn_spacing * 2;

            // New File button
            if (g_fm_add_file_btn_hovered) {
                gpu.drawGlow(btn_x, btns_y, btn_size, btn_size, 4, 0xFFd0a080, 12);
                gpu.fillRoundedRect(btn_x, btns_y, btn_size, btn_size, 4, 0xFF3a3a3a);
            }
            const new_file_color: u32 = if (g_fm_add_file_btn_hovered) COLOR_ACCENT else COLOR_TEXT_DIM;
            icons.drawIcon(gpu, .file, btn_x + 3, btns_y + 3, icon_size, new_file_color);
            btn_x += @as(i32, @intCast(btn_size)) + btn_spacing;

            // New Folder button
            if (g_fm_add_folder_btn_hovered) {
                gpu.drawGlow(btn_x, btns_y, btn_size, btn_size, 4, 0xFFd0a080, 12);
                gpu.fillRoundedRect(btn_x, btns_y, btn_size, btn_size, 4, 0xFF3a3a3a);
            }
            const new_folder_color: u32 = if (g_fm_add_folder_btn_hovered) COLOR_ACCENT else COLOR_TEXT_DIM;
            icons.drawIcon(gpu, .folder_open, btn_x + 3, btns_y + 3, icon_size, new_folder_color);
            btn_x += @as(i32, @intCast(btn_size)) + btn_spacing;

            // Delete button (only if something selected)
            if (explorer_selected >= 0) {
                if (g_fm_delete_btn_hovered) {
                    gpu.drawGlow(btn_x, btns_y, btn_size, btn_size, 4, 0xFFff6b6b, 12);
                    gpu.fillRoundedRect(btn_x, btns_y, btn_size, btn_size, 4, 0xFF3a2a2a);
                }
                const delete_color: u32 = if (g_fm_delete_btn_hovered) 0xFFff6b6b else COLOR_TEXT_DIM;
                icons.drawIcon(gpu, .close, btn_x + 3, btns_y + 3, icon_size, delete_color);
            }
        }

        if (sidebar_active_tab == 0 and current_folder_len == 0) {
            // Empty state Explorer with Open Folder button
            const btn_y: i32 = sidebar_y + @as(i32, @intCast(sidebar_h / 2)) - 20;
            const btn_x: i32 = sidebar_x + 10;
            const btn_w: u32 = sidebar_w - 20;
            const btn_h: u32 = 36;

            // Glow + Button background
            if (open_folder_btn_hovered) {
                gpu.drawGlow(btn_x, btn_y, btn_w, btn_h, 8, 0xFFd0a080, 15);
            }
            const btn_bg: u32 = if (open_folder_btn_hovered) 0xFF4d4038 else 0xFF3d3028;
            gpu.fillRoundedRect(btn_x, btn_y, btn_w, btn_h, 8, btn_bg);

            // Button border (on hover) - full border
            if (open_folder_btn_hovered) {
                // Top line
                gpu.fillRect(btn_x + 4, btn_y, btn_w - 8, 1, 0xFFd0a080);
                // Bottom line
                gpu.fillRect(btn_x + 4, btn_y + @as(i32, @intCast(btn_h)) - 1, btn_w - 8, 1, 0xFFd0a080);
                // Left line
                gpu.fillRect(btn_x, btn_y + 4, 1, btn_h - 8, 0xFFd0a080);
                // Right line
                gpu.fillRect(btn_x + @as(i32, @intCast(btn_w)) - 1, btn_y + 4, 1, btn_h - 8, 0xFFd0a080);
                // Corners (small squares for rounding)
                gpu.fillRect(btn_x + 1, btn_y + 2, 1, 2, 0xFFd0a080);
                gpu.fillRect(btn_x + 2, btn_y + 1, 2, 1, 0xFFd0a080);
                gpu.fillRect(btn_x + @as(i32, @intCast(btn_w)) - 2, btn_y + 2, 1, 2, 0xFFd0a080);
                gpu.fillRect(btn_x + @as(i32, @intCast(btn_w)) - 4, btn_y + 1, 2, 1, 0xFFd0a080);
                gpu.fillRect(btn_x + 1, btn_y + @as(i32, @intCast(btn_h)) - 4, 1, 2, 0xFFd0a080);
                gpu.fillRect(btn_x + 2, btn_y + @as(i32, @intCast(btn_h)) - 2, 2, 1, 0xFFd0a080);
                gpu.fillRect(btn_x + @as(i32, @intCast(btn_w)) - 2, btn_y + @as(i32, @intCast(btn_h)) - 4, 1, 2, 0xFFd0a080);
                gpu.fillRect(btn_x + @as(i32, @intCast(btn_w)) - 4, btn_y + @as(i32, @intCast(btn_h)) - 2, 2, 1, 0xFFd0a080);
            }

            // Folder icon (SVG)
            const icon_x = btn_x + 10;
            const icon_y = btn_y + 8;
            icons.drawIcon(gpu, .folder_open, icon_x, icon_y, 16, 0xFFd0a080);

            // Button text
            const text_color: u32 = if (open_folder_btn_hovered) 0xFFffffff else 0xFFd0a080;
            gpu.drawUIText("Open Folder", btn_x + 32, btn_y + 10, text_color);

            // Подсказка снизу
            gpu.drawUIText("or use Ctrl+O", btn_x + 20, btn_y + 48, COLOR_TEXT_DIM);
        } else if (sidebar_active_tab == 0) {
            // === Files Tab Content ===
            // Область для списка файлов (учитываем высоту табов + header)
            const files_area_y: i32 = sidebar_y + 8 + 24 + 12 + 20; // tabs + separator + header
            const files_area_h: i32 = @as(i32, @intCast(sidebar_h)) - 8 - 24 - 12 - 20 - 8;
            const file_item_h: i32 = 28;
            const indent_size: i32 = 16;

            // Calculate общую высоту контента
            var total_content_h: i32 = 0;
            for (0..folder_file_count) |calc_idx| {
                _ = folder_indent[calc_idx]; // nesting level
                total_content_h += file_item_h;
            }

            // Draw файлы
            var draw_y: i32 = files_area_y - explorer_scroll;
            for (0..folder_file_count) |file_idx| {
                const item_y = draw_y;
                const is_visible = item_y >= files_area_y - file_item_h and item_y < files_area_y + files_area_h;

                if (is_visible) {
                    const is_selected = explorer_selected == @as(i32, @intCast(file_idx));
                    const is_hovered = explorer_hovered == @as(i32, @intCast(file_idx));
                    const is_directory = folder_is_dir[file_idx];
                    const indent: i32 = @as(i32, folder_indent[file_idx]) * indent_size;

                    // Background элемента (красивый блок)
                    const item_x: i32 = sidebar_x + 6 + indent;
                    const item_w: u32 = @intCast(@max(10, @as(i32, @intCast(sidebar_w)) - 12 - indent));

                    if (is_selected) {
                        // Тёмно-персиковый для выделенного
                        gpu.fillRoundedRect(item_x, item_y, item_w, @intCast(file_item_h - 2), 6, 0xFF3d3028);
                    } else if (is_hovered) {
                        // Glow + фон для hover
                        gpu.drawGlow(item_x, item_y, item_w, @intCast(file_item_h - 2), 6, 0xFFd0a080, 12);
                        gpu.fillRoundedRect(item_x, item_y, item_w, @intCast(file_item_h - 2), 6, 0xFF302820);
                    }

                    // Иконка раскрытия для папок
                    const text_x = item_x + 8;
                    const text_y = item_y + 6;

                    if (is_directory) {
                        const is_expanded = folder_expanded[file_idx];
                        const anim = folder_anim_progress[file_idx];

                        // Треугольник-индикатор (поворачивается при анимации)
                        const arrow_x = text_x;
                        const arrow_y = text_y + 4;
                        const arrow_size: i32 = 6;

                        if (anim > 0.5) {
                            // Развёрнуто - стрелка вниз
                            gpu.drawUIText("v", arrow_x, text_y, COLOR_ACCENT);
                        } else {
                            // Свёрнуто - стрелка вправо
                            gpu.drawUIText(">", arrow_x, text_y, COLOR_ACCENT);
                        }
                        _ = arrow_y;
                        _ = arrow_size;
                        _ = is_expanded;

                        // Имя папки (или поле ввода при переименовании)
                        if (g_rename_mode and file_idx == g_rename_idx) {
                            // Draw rename input field for folder
                            const input_x = text_x + 14;
                            const input_w = item_w - 24;
                            const input_h: u32 = 18;

                            // Input field background with accent border effect
                            gpu.fillRoundedRect(input_x - 3, text_y - 5, input_w + 2, input_h + 2, 4, COLOR_ACCENT);
                            gpu.fillRoundedRect(input_x - 2, text_y - 4, input_w, input_h, 3, COLOR_BG);

                            // Draw input text
                            const rename_text = g_rename_field.getText();
                            const cursor_pos = g_rename_field.cursor;
                            const max_display = @min(rename_text.len, @as(usize, @intCast(input_w)) / 8);
                            gpu.drawUIText(rename_text[0..max_display], input_x, text_y - 2, COLOR_TEXT);

                            // Draw cursor
                            const cursor_x = input_x + @as(i32, @intCast(cursor_pos)) * 8;
                            gpu.fillRect(cursor_x, text_y - 3, 1, 14, COLOR_CURSOR);
                        } else {
                            const name_len = folder_file_lens[file_idx];
                            const max_chars = @divTrunc(@as(usize, @intCast(item_w)) - 30, 7);
                            const display_len = @min(name_len, max_chars);
                            gpu.drawUIText(folder_files[file_idx][0..display_len], text_x + 14, text_y, if (is_selected or is_hovered) COLOR_ACCENT else COLOR_TEXT);
                        }
                    } else {
                        // Обычный файл с SVG иконкой по расширению
                        const file_name = folder_files[file_idx][0..folder_file_lens[file_idx]];
                        const file_icon_type = icons.getIconForExtension(file_name);

                        // Draw SVG иконку (16x16)
                        icons.drawIcon(gpu, file_icon_type, text_x, text_y - 2, 20, 0xFFFFFFFF);

                        // Check if this item is being renamed
                        if (g_rename_mode and file_idx == g_rename_idx) {
                            // Draw rename input field
                            const input_x = text_x + 24;
                            const input_w = item_w - 32;
                            const input_h: u32 = 18;

                            // Input field background with accent border effect
                            gpu.fillRoundedRect(input_x - 3, text_y - 5, input_w + 2, input_h + 2, 4, COLOR_ACCENT);
                            gpu.fillRoundedRect(input_x - 2, text_y - 4, input_w, input_h, 3, COLOR_BG);

                            // Draw input text
                            const rename_text = g_rename_field.getText();
                            const cursor_pos = g_rename_field.cursor;
                            const max_display = @min(rename_text.len, @as(usize, @intCast(input_w)) / 8);
                            gpu.drawUIText(rename_text[0..max_display], input_x, text_y - 2, COLOR_TEXT);

                            // Draw cursor
                            const cursor_x = input_x + @as(i32, @intCast(cursor_pos)) * 8;
                            gpu.fillRect(cursor_x, text_y - 3, 1, 14, COLOR_CURSOR);
                        } else {
                            // File name after icon (normal display)
                            const name_len = folder_file_lens[file_idx];
                            const max_chars = @divTrunc(@as(usize, @intCast(item_w)) - 30, 7);
                            const display_len = @min(name_len, max_chars);
                            gpu.drawUIText(folder_files[file_idx][0..display_len], text_x + 24, text_y, if (is_selected or is_hovered) COLOR_TEXT else COLOR_TEXT_DIM);
                        }
                    }
                }

                draw_y += file_item_h;
            }

            // Скроллбар explorer (если нужен)
            if (total_content_h > files_area_h) {
                const scrollbar_x: i32 = sidebar_x + @as(i32, @intCast(sidebar_w)) - 10;
                const scrollbar_h: u32 = @intCast(files_area_h - 8);
                const thumb_ratio = @as(f32, @floatFromInt(files_area_h)) / @as(f32, @floatFromInt(total_content_h));
                const thumb_h: u32 = @max(20, @as(u32, @intFromFloat(@as(f32, @floatFromInt(scrollbar_h)) * thumb_ratio)));
                const scroll_pct = @as(f32, @floatFromInt(explorer_scroll)) / @as(f32, @floatFromInt(@max(1, total_content_h - files_area_h)));
                const thumb_y: i32 = files_area_y + 4 + @as(i32, @intFromFloat(scroll_pct * @as(f32, @floatFromInt(scrollbar_h - thumb_h))));

                // Scrollbar background
                gpu.fillRoundedRect(scrollbar_x, files_area_y + 4, 6, scrollbar_h, 3, 0xFF2a2a2a);
                // Thumb
                gpu.fillRoundedRect(scrollbar_x, thumb_y, 6, thumb_h, 3, COLOR_ACCENT_DIM);
            }
        } else if (sidebar_active_tab == 1) {
            // === Search Tab Content ===
            const search_area_y: i32 = sidebar_y + 8 + 24 + 12 + 20;
            const search_padding: i32 = 12;

            // Search input field
            const input_x: i32 = sidebar_x + search_padding;
            const input_y: i32 = search_area_y + 10;
            const input_w: u32 = sidebar_w - @as(u32, @intCast(search_padding)) * 2;
            const input_h: u32 = 28;

            // Input background
            const input_bg: u32 = if (g_search_active) 0xFF3a3a3a else 0xFF2a2a2a;
            gpu.fillRoundedRect(input_x, input_y, input_w, input_h, 6, input_bg);

            // Border when active
            if (g_search_active) {
                gpu.fillRect(input_x, input_y, input_w, 1, COLOR_ACCENT);
                gpu.fillRect(input_x, input_y + @as(i32, @intCast(input_h)) - 1, input_w, 1, COLOR_ACCENT);
                gpu.fillRect(input_x, input_y, 1, input_h, COLOR_ACCENT);
                gpu.fillRect(input_x + @as(i32, @intCast(input_w)) - 1, input_y, 1, input_h, COLOR_ACCENT);
            }

            // Search icon
            icons.drawIcon(gpu, .search, input_x + 6, input_y + 6, 16, COLOR_TEXT_DIM);

            // Input text or placeholder
            const query_text = g_search_field.getText();
            if (query_text.len > 0) {
                gpu.drawUIText(query_text, input_x + 28, input_y + 6, COLOR_TEXT);
            } else {
                gpu.drawUIText("Search in files...", input_x + 28, input_y + 6, COLOR_TEXT_DIM);
            }

            // Cursor when active
            if (g_search_active) {
                const cursor_x = input_x + 28 + @as(i32, @intCast(g_search_field.cursor * 8));
                gpu.fillRect(cursor_x, input_y + 5, 1, 18, COLOR_ACCENT);
            }

            // Results area
            const results_y: i32 = input_y + @as(i32, @intCast(input_h)) + 12;
            const results_h: i32 = @as(i32, @intCast(sidebar_h)) - (results_y - sidebar_y) - 10;

            if (g_current_folder_len == 0) {
                gpu.drawUIText("Open a folder first", sidebar_x + search_padding, results_y + 20, COLOR_TEXT_DIM);
            } else if (g_search_result_count == 0 and query_text.len > 0) {
                gpu.drawUIText("No results found", sidebar_x + search_padding, results_y + 20, COLOR_TEXT_DIM);
            } else if (g_search_result_count > 0) {
                // Show result count
                var count_buf: [32]u8 = undefined;
                const count_text = std.fmt.bufPrint(&count_buf, "{d} results", .{g_search_result_count}) catch "results";
                gpu.drawUIText(count_text, sidebar_x + search_padding, results_y, COLOR_TEXT_DIM);

                // Results list
                const result_item_h: i32 = 48;
                const visible_results = @divTrunc(results_h - 20, result_item_h);
                var result_y: i32 = results_y + 20;

                const start_idx: usize = @intCast(@max(0, g_search_result_scroll));
                const end_idx = @min(g_search_result_count, start_idx + @as(usize, @intCast(visible_results)));

                for (start_idx..end_idx) |ri| {
                    const result = &g_search_results[ri];
                    const is_hovered = g_search_result_hovered == @as(i32, @intCast(ri));

                    // Background on hover
                    if (is_hovered) {
                        gpu.drawGlow(sidebar_x + 8, result_y, sidebar_w - 16, @intCast(result_item_h - 4), 6, 0xFFd0a080, 10);
                        gpu.fillRoundedRect(sidebar_x + 8, result_y, sidebar_w - 16, @intCast(result_item_h - 4), 6, 0xFF302820);
                    }

                    // File name (extract from path)
                    const file_path = result.file_path[0..result.file_path_len];
                    var file_name: []const u8 = file_path;
                    if (std.mem.lastIndexOf(u8, file_path, "/")) |idx| {
                        file_name = file_path[idx + 1 ..];
                    }
                    const name_color: u32 = if (is_hovered) COLOR_ACCENT else COLOR_TEXT;
                    gpu.drawUIText(file_name, sidebar_x + 14, result_y + 4, name_color);

                    // Line number
                    var line_buf: [16]u8 = undefined;
                    const line_text = std.fmt.bufPrint(&line_buf, ":{d}", .{result.line_num}) catch "";
                    gpu.drawUIText(line_text, sidebar_x + 14 + @as(i32, @intCast(file_name.len * 8)), result_y + 4, COLOR_TEXT_DIM);

                    // Line content (truncated)
                    const content = result.line_content[0..result.line_content_len];
                    const max_content_chars: usize = @intCast(@divTrunc(@as(i32, @intCast(sidebar_w)) - 28, 7));
                    const display_content = content[0..@min(content.len, max_content_chars)];
                    gpu.drawUIText(display_content, sidebar_x + 14, result_y + 22, COLOR_TEXT_DIM);

                    result_y += result_item_h;
                }
            }
        } else if (sidebar_active_tab == 2) {
            // === Source Control Tab Content ===
            const git_area_y: i32 = sidebar_y + 8 + 24 + 12 + 20;
            gpu.drawUIText("IDK", sidebar_x + 12, git_area_y + 40, COLOR_TEXT_DIM);
            gpu.drawUIText("i make it in future", sidebar_x + 12, git_area_y + 60, COLOR_TEXT_DIM);
        } else if (sidebar_active_tab == 3) {
            // === Plugins Tab Content ===
            const plugins_area_y: i32 = sidebar_y + 8 + 24 + 12 + 20;
            const plugins_padding: i32 = 12;

            // Заголовок "Installed"
            gpu.drawUIText("INSTALLED", sidebar_x + plugins_padding, plugins_area_y, COLOR_TEXT_DIM);

            // Get loaded plugins
            const loader = plugins.getLoader();
            const plugin_count = loader.plugin_count;

            // Track Y position for both active and disabled plugins
            var plugin_y: i32 = plugins_area_y + 30;
            var visible_plugin_idx: i32 = 0;

            if (plugin_count == 0) {
                // Пустой список
                gpu.drawUIText("No plugins loaded", sidebar_x + plugins_padding, plugin_y, COLOR_TEXT_DIM);
                gpu.drawUIText("Put .wasm files in", sidebar_x + plugins_padding, plugin_y + 18, COLOR_TEXT_DIM);
                gpu.drawUIText("~/.mncode/plugins/", sidebar_x + plugins_padding, plugin_y + 36, COLOR_ACCENT);
                plugin_y += 70;
            } else {
                // Список загруженных плагинов
                for (0..plugin_count) |pi| {
                    if (loader.getPlugin(pi)) |plugin| {
                        if (plugin.state == .active) {
                            const is_hovered = (plugin_hovered == visible_plugin_idx);

                            // Background плагина (светлее при hover) + glow
                            if (is_hovered) {
                                gpu.drawGlow(sidebar_x + 8, plugin_y, sidebar_w - 16, 50, 6, 0xFFd0a080, 15);
                            }
                            const bg_color: u32 = if (is_hovered) 0xFF403830 else 0xFF302820;
                            gpu.fillRoundedRect(sidebar_x + 8, plugin_y, sidebar_w - 16, 50, 6, bg_color);

                            // Иконка (определяем по расширениям)
                            const exts = plugin.info.getExtensions();
                            if (std.mem.indexOf(u8, exts, ".py") != null) {
                                icons.drawIcon(gpu, .file_py, sidebar_x + 14, plugin_y + 8, 16, 0xFF3572A5);
                            } else {
                                icons.drawIcon(gpu, .plugin, sidebar_x + 14, plugin_y + 8, 16, COLOR_ACCENT);
                            }

                            // Имя плагина
                            const name = plugin.info.getName();
                            const name_color: u32 = if (is_hovered) 0xFFFFFFFF else COLOR_TEXT;
                            if (name.len > 0) {
                                gpu.drawUIText(name, sidebar_x + 36, plugin_y + 8, name_color);
                            } else {
                                gpu.drawUIText("Unknown", sidebar_x + 36, plugin_y + 8, name_color);
                            }

                            // Extensions
                            if (exts.len > 0) {
                                gpu.drawUIText(exts, sidebar_x + 36, plugin_y + 26, COLOR_TEXT_DIM);
                            }

                            plugin_y += 58;
                            visible_plugin_idx += 1;
                        }
                    }
                }
            }

            // === DISABLED PLUGINS SECTION ===
            const disabled_plugins = plugins.getDisabledPlugins();
            if (disabled_plugins.len > 0) {
                // Divider
                plugin_y += 10;
                gpu.fillRect(sidebar_x + plugins_padding, plugin_y, sidebar_w - plugins_padding * 2, 1, COLOR_ACCENT_DIM);
                plugin_y += 15;

                // Section header
                gpu.drawUIText("DISABLED", sidebar_x + plugins_padding, plugin_y, 0xFF666666);
                plugin_y += 25;

                // List disabled plugins
                for (disabled_plugins, 0..) |*dp, di| {
                    const is_hovered = g_disabled_plugin_hovered == @as(i32, @intCast(di));

                    // Background with glow on hover
                    if (is_hovered) {
                        gpu.drawGlow(sidebar_x + 8, plugin_y, sidebar_w - 16, 36, 6, 0xFFd0a080, 12);
                    }
                    const bg_color: u32 = if (is_hovered) 0xFF353030 else 0xFF252525;
                    gpu.fillRoundedRect(sidebar_x + 8, plugin_y, sidebar_w - 16, 36, 6, bg_color);

                    // Disabled icon
                    const icon_color: u32 = if (is_hovered) 0xFF888888 else 0xFF555555;
                    icons.drawIcon(gpu, .plugin, sidebar_x + 14, plugin_y + 10, 16, icon_color);

                    // Name (grayed out, lighter on hover)
                    const dname = dp.getName();
                    const name_color: u32 = if (is_hovered) 0xFF999999 else 0xFF666666;
                    if (dname.len > 0) {
                        gpu.drawUIText(dname, sidebar_x + 36, plugin_y + 10, name_color);
                    }

                    plugin_y += 44;
                }
            }

            // Разделитель и путь к папке плагинов
            const info_y: i32 = sidebar_y + @as(i32, @intCast(sidebar_h)) - 60;
            gpu.fillRect(sidebar_x + plugins_padding, info_y, sidebar_w - plugins_padding * 2, 1, COLOR_ACCENT_DIM);
            gpu.drawUIText("Plugins folder:", sidebar_x + plugins_padding, info_y + 10, COLOR_TEXT_DIM);
            gpu.drawUIText("~/.mncode/plugins/", sidebar_x + plugins_padding, info_y + 28, COLOR_TEXT_DIM);
        }

        // Resize handle - small handle in center, changes color on hover
        const handle_x: i32 = sidebar_x + @as(i32, @intCast(sidebar_w)) - 3;
        const handle_y: i32 = sidebar_y + @divTrunc(@as(i32, @intCast(sidebar_h)), 2) - 20;
        const handle_color: u32 = if (sidebar_resize_hovered) 0xFFd0a080 else COLOR_ACCENT_DIM;
        gpu.fillRoundedRect(handle_x, handle_y, 4, 40, 2, handle_color);
    }

    // === Tab Bar (bottom of window, with soft shadow) ===
    {
        // Tab bar начинается сразу после editor block с отступом 10px
        const tab_bar_y: i32 = editor_bottom + 10;
        const tab_bar_x: i32 = editor_left;
        const tab_bar_w: u32 = editor_w;

        // Мягкая тень для tab bar
        gpu.drawSoftShadow(tab_bar_x, tab_bar_y, tab_bar_w, tab_bar_h, 10, 3, 4, 20, 70);

        // Background tab bar
        gpu.fillRoundedRect(tab_bar_x, tab_bar_y, tab_bar_w, tab_bar_h, 10, COLOR_SURFACE);

        // Draw вкладки
        var tab_x: i32 = tab_bar_x + gpu.scaledI(8);
        const tab_h: u32 = tab_bar_h - gpu.scaled(10);
        const tab_y: i32 = tab_bar_y + gpu.scaledI(5);

        const tab_bar_right: i32 = tab_bar_x + @as(i32, @intCast(tab_bar_w));

        for (0..tab_count) |tab_idx| {
            const name_len = tab_name_lens[tab_idx];
            if (name_len == 0) continue;

            // Ширина вкладки: иконка + имя + отступы + кнопка закрытия
            const text_width: i32 = @as(i32, @intCast(name_len)) * 8;
            const tab_w: u32 = @intCast(@max(140, text_width + 70)); // Увеличенные табы

            // Оптимизация: пропускаем табы за пределами видимой области
            if (tab_x + @as(i32, @intCast(tab_w)) < tab_bar_x) {
                tab_x += @as(i32, @intCast(tab_w)) + 4;
                continue;
            }
            if (tab_x > tab_bar_right) {
                break; // Все последующие табы тоже невидимы
            }

            const is_active = tab_idx == active_tab;
            const is_hovered = tab_hovered == @as(i32, @intCast(tab_idx));
            const is_modified = tab_modified[tab_idx];
            const is_close_hovered = tab_close_hovered == @as(i32, @intCast(tab_idx));

            // Get SVG иконку файла для вкладки
            const tab_file_name = tab_names[tab_idx][0..name_len];
            const tab_icon_type = icons.getIconForExtension(tab_file_name);

            // Background вкладки - только при active или hover + glow
            if (is_active) {
                gpu.fillRoundedRect(tab_x, tab_y, tab_w, tab_h, 8, COLOR_ACCENT_DIM);
            } else if (is_hovered) {
                gpu.drawGlow(tab_x, tab_y, tab_w, tab_h, 8, 0xFFd0a080, 12);
                gpu.fillRoundedRect(tab_x, tab_y, tab_w, tab_h, 8, 0xFF2a2a2a);
            }

            // Индикатор несохранённых изменений (кружок)
            const icon_offset: i32 = if (is_modified) 20 else 10;
            if (is_modified) {
                gpu.fillRoundedRect(tab_x + 8, tab_y + @as(i32, @intCast(tab_h / 2)) - 3, 6, 6, 3, COLOR_ACCENT);
            }

            // SVG icon файла (20x20)
            const icon_y_pos = tab_y + @divTrunc(@as(i32, @intCast(tab_h)) - 20, 2);
            icons.drawIcon(gpu, tab_icon_type, tab_x + icon_offset, icon_y_pos, 20, 0xFFFFFFFF);

            // Имя вкладки (белый текст) - центрирование по вертикали
            const text_x = tab_x + icon_offset + 26;
            const font_h = gpu.uiLineHeight();
            const text_y_pos = tab_y + @divTrunc(@as(i32, @intCast(tab_h)) - @as(i32, @intCast(font_h)), 2) + 2;
            const text_color: u32 = if (is_active) 0xFFFFFFFF else if (is_hovered) 0xFFe0e0e0 else COLOR_TEXT_DIM;
            gpu.drawUIText(tab_names[tab_idx][0..name_len], text_x, text_y_pos, text_color);

            // Кнопка закрытия (×) + glow при hover
            const close_x = tab_x + @as(i32, @intCast(tab_w)) - 22;
            const close_y = tab_y + @divTrunc(@as(i32, @intCast(tab_h)), 2) - 6;
            const close_color: u32 = if (is_close_hovered) COLOR_BTN_CLOSE else COLOR_TEXT_DIM;
            if (is_hovered or is_active) {
                if (is_close_hovered) {
                    gpu.drawGlow(close_x - 2, close_y - 2, 16, 16, 4, 0xFFff6b6b, 12);
                }
                icons.drawIcon(gpu, .close, close_x, close_y, 12, close_color);
            }

            // Разделитель между вкладками
            if (tab_idx + 1 < tab_count and !is_active) {
                gpu.fillRect(tab_x + @as(i32, @intCast(tab_w)) + 1, tab_y + 6, 1, tab_h - 12, 0xFF3a3a3a);
            }

            tab_x += @as(i32, @intCast(tab_w)) + 4;
        }

        // Кнопка "+" для новой вкладки - квадратная, центрированная
        const plus_btn_size: u32 = gpu.scaled(24);
        const plus_x = tab_x + 4;
        const plus_y = tab_y + @divTrunc(@as(i32, @intCast(tab_h)) - @as(i32, @intCast(plus_btn_size)), 2);
        const plus_hovered = wayland.mouse_x >= plus_x and wayland.mouse_x < plus_x + @as(i32, @intCast(plus_btn_size)) and
            wayland.mouse_y >= plus_y and wayland.mouse_y < plus_y + @as(i32, @intCast(plus_btn_size));
        if (plus_hovered) {
            gpu.drawGlow(plus_x, plus_y, plus_btn_size, plus_btn_size, 6, 0xFFd0a080, 15);
            gpu.fillRoundedRect(plus_x, plus_y, plus_btn_size, plus_btn_size, 6, 0xFF2a2a2a);
        }
        const plus_color: u32 = if (plus_hovered) COLOR_ACCENT else COLOR_TEXT_DIM;
        const icon_size: u32 = gpu.scaled(14);
        const icon_x = plus_x + @divTrunc(@as(i32, @intCast(plus_btn_size)) - @as(i32, @intCast(icon_size)), 2);
        const icon_y = plus_y + @divTrunc(@as(i32, @intCast(plus_btn_size)) - @as(i32, @intCast(icon_size)), 2);
        icons.drawIcon(gpu, .plus, icon_x, icon_y, icon_size, plus_color);

        // === Right-side buttons (Run, Panel) ===
        const right_btn_size: u32 = gpu.scaled(28);
        const right_btn_y: i32 = tab_y;

        // Panel toggle button (terminal icon)
        const panel_btn_x: i32 = tab_bar_right - @as(i32, @intCast(right_btn_size)) - gpu.scaledI(8);
        g_panel_btn_hovered = wayland.mouse_x >= panel_btn_x and wayland.mouse_x < panel_btn_x + @as(i32, @intCast(right_btn_size)) and
            wayland.mouse_y >= right_btn_y and wayland.mouse_y < right_btn_y + @as(i32, @intCast(tab_h));
        if (g_panel_btn_hovered) {
            gpu.drawGlow(panel_btn_x, right_btn_y, right_btn_size, tab_h, gpu.scaled(8), 0xFFd0a080, 12);
        }
        const panel_btn_bg: u32 = if (g_panel_btn_hovered) 0xFF2a2a2a else if (g_bottom_panel_visible) COLOR_ACCENT_DIM else 0xFF1e1e1e;
        gpu.fillRoundedRect(panel_btn_x, right_btn_y, right_btn_size, tab_h, gpu.scaled(8), panel_btn_bg);
        const panel_icon_color: u32 = if (g_bottom_panel_visible) COLOR_ACCENT else if (g_panel_btn_hovered) COLOR_TEXT else COLOR_TEXT_DIM;
        icons.drawIcon(gpu, .terminal, panel_btn_x + gpu.scaledI(6), right_btn_y + gpu.scaledI(8), gpu.scaled(16), panel_icon_color);

        // Run button (play icon)
        const run_btn_x: i32 = panel_btn_x - @as(i32, @intCast(right_btn_size)) - gpu.scaledI(4);
        g_run_btn_hovered = wayland.mouse_x >= run_btn_x and wayland.mouse_x < run_btn_x + @as(i32, @intCast(right_btn_size)) and
            wayland.mouse_y >= right_btn_y and wayland.mouse_y < right_btn_y + @as(i32, @intCast(tab_h));
        if (g_run_btn_hovered) {
            gpu.drawGlow(run_btn_x, right_btn_y, right_btn_size, tab_h, gpu.scaled(8), 0xFF6bff6b, 12);
        }
        const run_btn_bg: u32 = if (g_run_btn_hovered) 0xFF2a4a2a else 0xFF1e1e1e; // Зеленоватый при hover
        gpu.fillRoundedRect(run_btn_x, right_btn_y, right_btn_size, tab_h, gpu.scaled(8), run_btn_bg);
        const run_icon_color: u32 = if (g_run_btn_hovered) 0xFF6bff6b else COLOR_TEXT_DIM; // Зелёный при hover
        icons.drawIcon(gpu, .play, run_btn_x + gpu.scaledI(6), right_btn_y + gpu.scaledI(8), gpu.scaled(16), run_icon_color);
    }

    // === Bottom Panel (Output/Problems) ===
    if (g_bottom_panel_visible) {
        const bp_x: i32 = editor_left;
        const bp_y: i32 = editor_bottom + 4;
        const bp_w: u32 = editor_w;
        const bp_h: u32 = @intCast(g_bottom_panel_height);

        // Background панели
        gpu.fillRoundedRect(bp_x, bp_y, bp_w, bp_h, 10, COLOR_SURFACE);

        // Resize handle (horizontal bar on top)
        const resize_handle_y: i32 = bp_y;
        const resize_handle_w: u32 = 60;
        const resize_handle_x: i32 = bp_x + @as(i32, @intCast(bp_w / 2 - resize_handle_w / 2));
        gpu.fillRoundedRect(resize_handle_x, resize_handle_y + 2, resize_handle_w, 4, 2, COLOR_ACCENT_DIM);

        // Tabs: Output, Problems
        const bp_tab_y: i32 = bp_y + 10;
        const bp_tab_h: u32 = 26;

        // Output tab
        const output_tab_x: i32 = bp_x + 12;
        const output_tab_w: u32 = 70;
        const output_tab_active = g_bottom_panel_tab == 0;
        const output_tab_hovered = !output_tab_active and
            wayland.mouse_x >= output_tab_x and wayland.mouse_x < output_tab_x + @as(i32, @intCast(output_tab_w)) and
            wayland.mouse_y >= bp_tab_y and wayland.mouse_y < bp_tab_y + @as(i32, @intCast(bp_tab_h));
        if (output_tab_hovered) {
            gpu.drawGlow(output_tab_x, bp_tab_y, output_tab_w, bp_tab_h, 6, 0xFFd0a080, 10);
        }
        const output_tab_bg: u32 = if (output_tab_active) COLOR_ACCENT_DIM else if (output_tab_hovered) 0xFF2a2a2a else 0xFF1e1e1e;
        gpu.fillRoundedRect(output_tab_x, bp_tab_y, output_tab_w, bp_tab_h, 6, output_tab_bg);
        const output_text_color: u32 = if (output_tab_active or output_tab_hovered) COLOR_TEXT else COLOR_TEXT_DIM;
        gpu.drawUIText("Output", output_tab_x + 12, bp_tab_y + 5, output_text_color);

        // Problems tab
        const problems_tab_x: i32 = output_tab_x + @as(i32, @intCast(output_tab_w)) + 4;
        const problems_tab_w: u32 = 80;
        const problems_tab_active = g_bottom_panel_tab == 1;
        const problems_tab_hovered = !problems_tab_active and
            wayland.mouse_x >= problems_tab_x and wayland.mouse_x < problems_tab_x + @as(i32, @intCast(problems_tab_w)) and
            wayland.mouse_y >= bp_tab_y and wayland.mouse_y < bp_tab_y + @as(i32, @intCast(bp_tab_h));
        if (problems_tab_hovered) {
            gpu.drawGlow(problems_tab_x, bp_tab_y, problems_tab_w, bp_tab_h, 6, 0xFFd0a080, 10);
        }
        const problems_tab_bg: u32 = if (problems_tab_active) COLOR_ACCENT_DIM else if (problems_tab_hovered) 0xFF2a2a2a else 0xFF1e1e1e;
        gpu.fillRoundedRect(problems_tab_x, bp_tab_y, problems_tab_w, bp_tab_h, 6, problems_tab_bg);
        const problems_text_color: u32 = if (problems_tab_active or problems_tab_hovered) COLOR_TEXT else COLOR_TEXT_DIM;
        gpu.drawUIText("Problems", problems_tab_x + 8, bp_tab_y + 5, problems_text_color);

        // Terminal tab
        const term_tab_x: i32 = problems_tab_x + @as(i32, @intCast(problems_tab_w)) + 4;
        const term_tab_w: u32 = 80;
        const term_tab_active = g_bottom_panel_tab == 2;
        const term_tab_hovered = !term_tab_active and
            wayland.mouse_x >= term_tab_x and wayland.mouse_x < term_tab_x + @as(i32, @intCast(term_tab_w)) and
            wayland.mouse_y >= bp_tab_y and wayland.mouse_y < bp_tab_y + @as(i32, @intCast(bp_tab_h));
        if (term_tab_hovered) {
            gpu.drawGlow(term_tab_x, bp_tab_y, term_tab_w, bp_tab_h, 6, 0xFFd0a080, 10);
        }
        const term_tab_bg: u32 = if (term_tab_active) COLOR_ACCENT_DIM else if (term_tab_hovered) 0xFF2a2a2a else 0xFF1e1e1e;
        gpu.fillRoundedRect(term_tab_x, bp_tab_y, term_tab_w, bp_tab_h, 6, term_tab_bg);
        const term_text_color: u32 = if (term_tab_active or term_tab_hovered) COLOR_TEXT else COLOR_TEXT_DIM;
        gpu.drawUIText("Terminal", term_tab_x + 8, bp_tab_y + 5, term_text_color);

        // Close button with hover effect + glow
        const close_btn_x: i32 = bp_x + @as(i32, @intCast(bp_w)) - 32;
        const close_btn_y: i32 = bp_tab_y + 3;
        // Check hover
        g_close_btn_hovered = wayland.mouse_x >= close_btn_x - 2 and wayland.mouse_x < close_btn_x + 18 and
            wayland.mouse_y >= close_btn_y - 2 and wayland.mouse_y < close_btn_y + 18;
        const close_btn_color: u32 = if (g_close_btn_hovered) COLOR_BTN_CLOSE else COLOR_TEXT_DIM;
        if (g_close_btn_hovered) {
            gpu.drawGlow(close_btn_x - 2, close_btn_y - 2, 20, 20, 4, 0xFFff6b6b, 12);
            gpu.fillRoundedRect(close_btn_x - 2, close_btn_y - 2, 20, 20, 4, 0xFF3a3a3a);
        }
        icons.drawIcon(gpu, .close, close_btn_x, close_btn_y, 16, close_btn_color);

        // Разделитель
        gpu.fillRect(bp_x + 8, bp_tab_y + @as(i32, @intCast(bp_tab_h)) + 6, bp_w - 16, 1, 0xFF3a3a3a);

        // Контент панели
        const content_y: i32 = bp_tab_y + @as(i32, @intCast(bp_tab_h)) + 14;
        const content_x: i32 = bp_x + 12;

        if (g_bottom_panel_tab == 0) {
            // Output tab content
            if (g_output_line_count == 0) {
                gpu.drawUIText("No output", content_x, content_y, COLOR_TEXT_DIM);
            } else {
                // Exit code indicator
                if (g_run_exit_code != 0) {
                    var exit_buf: [32]u8 = undefined;
                    const exit_msg = std.fmt.bufPrint(&exit_buf, "Exit code: {d}", .{g_run_exit_code}) catch "Exit code: ?";
                    gpu.drawUIText(exit_msg, bp_x + @as(i32, @intCast(bp_w)) - 120, bp_tab_y + 8, 0xFFff6b6b);
                }

                var out_y: i32 = content_y;
                const max_visible_lines: usize = @intCast(@max(1, @divTrunc(bp_h - 50, 18)));
                var line_idx: usize = 0;
                while (line_idx < g_output_line_count and line_idx < max_visible_lines) : (line_idx += 1) {
                    if (g_output_line_lens[line_idx] > 0) {
                        // Цвет строки по типу
                        const line_color: u32 = switch (g_output_line_types[line_idx]) {
                            1 => 0xFFcca700, // warning - жёлтый
                            2 => 0xFFff6b6b, // error - красный
                            else => COLOR_TEXT, // normal
                        };
                        gpu.drawUIText(g_output_lines[line_idx][0..g_output_line_lens[line_idx]], content_x, out_y, line_color);
                    }
                    out_y += 18;
                }
            }
        } else if (g_bottom_panel_tab == 1) {
            // Problems tab content
            gpu.drawUIText("No problems", content_x, content_y, COLOR_TEXT_DIM);
        } else if (g_bottom_panel_tab == 2) {
            // Terminal tab content
            const term = shell.getShell();

            if (!term.isRunning()) {
                // Centered "not running" message with icon hint
                const msg = "Press Enter to start terminal";
                const icon_y = content_y + @as(i32, @intCast(bp_h / 3));
                icons.drawIcon(gpu, .terminal, content_x + @as(i32, @intCast(bp_w / 2)) - 60, icon_y - 10, 24, 0xFF404040);
                gpu.drawUIText(msg, content_x + @as(i32, @intCast(bp_w / 2)) - 100, icon_y + 20, COLOR_TEXT_DIM);
            } else {
                // Terminal output area dimensions
                const scrollbar_w: u32 = 10;
                const output_w = bp_w - 24 - scrollbar_w;
                const input_h: i32 = 36;
                const output_area_h: i32 = @as(i32, @intCast(bp_h)) - 45 - input_h;
                const max_lines: usize = @intCast(@max(1, @divTrunc(output_area_h, 18)));

                // Draw terminal output background (darker area)
                gpu.fillRoundedRect(content_x - 4, content_y - 4, output_w + 8, @intCast(output_area_h + 8), 6, 0xFF151515);

                // Draw terminal output with scroll support
                var term_lines: [64][]const u8 = undefined;
                const line_count = term.getLines(&term_lines, @min(max_lines, 64));

                var term_y: i32 = content_y;
                for (term_lines[0..line_count]) |line| {
                    if (line.len > 0) {
                        const display_len = @min(line.len, 200);
                        // Parse color hints from output
                        const line_color: u32 = if (std.mem.indexOf(u8, line[0..display_len], "error") != null)
                            0xFFff6b6b
                        else if (std.mem.indexOf(u8, line[0..display_len], "warning") != null or std.mem.indexOf(u8, line[0..display_len], "warn") != null)
                            0xFFcca700
                        else if (std.mem.indexOf(u8, line[0..display_len], "success") != null or std.mem.indexOf(u8, line[0..display_len], "ok") != null)
                            0xFF6bff6b
                        else
                            COLOR_TEXT;
                        gpu.drawUIText(line[0..display_len], content_x, term_y, line_color);
                    }
                    term_y += 18;
                }

                // Scrollbar
                const scroll_info = term.getScrollInfo();
                const total_lines = scroll_info.total;
                const visible_lines = max_lines;
                const scroll_offset = scroll_info.offset;

                if (total_lines > visible_lines) {
                    const scrollbar_x: i32 = content_x + @as(i32, @intCast(output_w)) + 4;
                    const scrollbar_h: u32 = @intCast(output_area_h);

                    // Track
                    gpu.fillRoundedRect(scrollbar_x, content_y - 4, scrollbar_w, scrollbar_h, 4, 0xFF1a1a1a);

                    // Thumb
                    const visible_ratio = @as(f32, @floatFromInt(visible_lines)) / @as(f32, @floatFromInt(total_lines));
                    const thumb_h: u32 = @max(20, @as(u32, @intFromFloat(@as(f32, @floatFromInt(scrollbar_h)) * visible_ratio)));
                    const scroll_range = total_lines - visible_lines;
                    const scroll_ratio: f32 = if (scroll_range > 0) @as(f32, @floatFromInt(scroll_offset)) / @as(f32, @floatFromInt(scroll_range)) else 0;
                    // Invert because scroll_offset 0 = bottom (show latest)
                    const thumb_y_offset: i32 = @intFromFloat(@as(f32, @floatFromInt(scrollbar_h - thumb_h)) * (1.0 - scroll_ratio));
                    const thumb_y: i32 = content_y - 4 + thumb_y_offset;

                    gpu.fillRoundedRect(scrollbar_x + 2, thumb_y, scrollbar_w - 4, thumb_h, 3, 0xFF505050);
                }

                // Input field at bottom (improved style)
                const input_y: i32 = bp_y + @as(i32, @intCast(bp_h)) - input_h;
                const input_bg: u32 = if (g_terminal_focused) 0xFF2a2a2a else 0xFF222222;
                gpu.fillRoundedRect(content_x - 4, input_y - 2, bp_w - 24, 30, 6, input_bg);

                // Focus indicator
                if (g_terminal_focused) {
                    gpu.fillRect(content_x - 4, input_y - 2, 3, 30, COLOR_ACCENT);
                }

                // Prompt with shell path hint
                const prompt_color: u32 = if (g_terminal_focused) COLOR_ACCENT else COLOR_TEXT_DIM;
                gpu.drawUIText(">", content_x + 2, input_y + 6, prompt_color);

                // Input text
                const term_text = g_terminal_field.getText();
                if (term_text.len > 0) {
                    gpu.drawUIText(term_text, content_x + 18, input_y + 6, COLOR_TEXT);
                } else if (!g_terminal_focused) {
                    gpu.drawUIText("Type command... (↑↓ history, PgUp/PgDn scroll)", content_x + 18, input_y + 6, COLOR_TEXT_DIM);
                }

                // Cursor (blinking effect via time)
                if (g_terminal_focused) {
                    const cursor_x: i32 = content_x + 18 + @as(i32, @intCast(g_terminal_field.cursor * 8));
                    gpu.fillRect(cursor_x, input_y + 6, 2, 16, COLOR_CURSOR);
                }

                // Scroll indicator if scrolled up
                if (scroll_offset > 0) {
                    var scroll_hint_buf: [32]u8 = undefined;
                    const scroll_hint = std.fmt.bufPrint(&scroll_hint_buf, "↑ {d} lines hidden", .{scroll_offset}) catch "↑ scrolled";
                    const hint_x: i32 = content_x + @as(i32, @intCast(output_w)) - 120;
                    gpu.fillRoundedRect(hint_x - 4, content_y - 4, 130, 20, 4, 0xCC1a1a1a);
                    gpu.drawUIText(scroll_hint, hint_x, content_y, COLOR_ACCENT);
                }
            }
        }
    }

    // === Search bar (on top of editor) ===
    if (search_visible) {
        const search_bar_h: u32 = gpu.scaled(36);
        const search_bar_w: u32 = gpu.scaled(320);
        const search_bar_x: i32 = @as(i32, @intCast(wayland.width)) - @as(i32, @intCast(search_bar_w)) - gpu.scaledI(20);
        const search_bar_y: i32 = @as(i32, @intCast(titlebar_h)) + gpu.scaledI(10);

        // Тень
        gpu.fillRoundedRect(search_bar_x + 2, search_bar_y + 2, search_bar_w, search_bar_h, gpu.scaled(8), 0xFF0a0a0a);
        // Background
        gpu.fillRoundedRect(search_bar_x, search_bar_y, search_bar_w, search_bar_h, gpu.scaled(8), COLOR_SURFACE);

        // Иконка поиска
        icons.drawIcon(gpu, .search, search_bar_x + gpu.scaledI(10), search_bar_y + gpu.scaledI(10), gpu.scaled(16), COLOR_TEXT_DIM);

        // Поле ввода (фон)
        const input_x: i32 = search_bar_x + gpu.scaledI(32);
        const input_y: i32 = search_bar_y + gpu.scaledI(6);
        const input_w: u32 = gpu.scaled(180);
        const input_h: u32 = gpu.scaled(24);
        gpu.fillRoundedRect(input_x, input_y, input_w, input_h, gpu.scaled(4), 0xFF252525);

        // Текст запроса
        if (search_query.len > 0) {
            gpu.drawText(search_query, input_x + gpu.scaledI(6), input_y + gpu.scaledI(4), COLOR_TEXT);
        } else {
            gpu.drawUIText("Search...", input_x + gpu.scaledI(6), input_y + gpu.scaledI(4), COLOR_TEXT_DIM);
        }

        // Курсор в поле ввода (мигающий эффект можно добавить позже)
        const cursor_x_search: i32 = input_x + gpu.scaledI(6) + @as(i32, @intCast(search_cursor)) * @as(i32, @intCast(gpu.charWidth()));
        gpu.fillRect(cursor_x_search, input_y + gpu.scaledI(4), 2, gpu.scaled(16), COLOR_ACCENT);

        // Счётчик совпадений
        const counter_x: i32 = input_x + @as(i32, @intCast(input_w)) + gpu.scaledI(8);
        var counter_buf: [16]u8 = undefined;
        const counter_str = if (search_match_count > 0)
            std.fmt.bufPrint(&counter_buf, "{d}/{d}", .{ search_current_match + 1, search_match_count }) catch "?/?"
        else
            std.fmt.bufPrint(&counter_buf, "0/0", .{}) catch "0/0";
        gpu.drawUIText(counter_str, counter_x, search_bar_y + gpu.scaledI(10), if (search_match_count > 0) COLOR_TEXT else COLOR_TEXT_DIM);

        // Кнопки навигации (< и >)
        const btn_y: i32 = search_bar_y + gpu.scaledI(6);
        const btn_size: u32 = gpu.scaled(24);
        const prev_btn_x: i32 = search_bar_x + @as(i32, @intCast(search_bar_w)) - gpu.scaledI(56);
        const next_btn_x: i32 = search_bar_x + @as(i32, @intCast(search_bar_w)) - gpu.scaledI(28);

        // Prev button (<)
        gpu.fillRoundedRect(prev_btn_x, btn_y, btn_size, btn_size, gpu.scaled(4), 0xFF353535);
        gpu.drawUIText("<", prev_btn_x + gpu.scaledI(8), btn_y + gpu.scaledI(4), COLOR_TEXT);

        // Next button (>)
        gpu.fillRoundedRect(next_btn_x, btn_y, btn_size, btn_size, gpu.scaled(4), 0xFF353535);
        gpu.drawUIText(">", next_btn_x + gpu.scaledI(8), btn_y + gpu.scaledI(4), COLOR_TEXT);
    }

    // === Dropdown menus (on top of sidebar) ===
    if (menu_open >= 0) {
        const menu_block_x: i32 = gpu.scaledI(8);
        const menu_block_y: i32 = @divTrunc(@as(i32, @intCast(titlebar_h)) - gpu.scaledI(26), 2);
        const menu_section_w: i32 = gpu.scaledI(46); // 140 / 3

        // Позиция dropdown
        const dropdown_x: i32 = menu_block_x + menu_open * menu_section_w;
        const dropdown_y: i32 = menu_block_y + gpu.scaledI(26) + gpu.scaledI(2);
        const dropdown_w: u32 = gpu.scaled(160);

        // Общие размеры для меню
        const menu_item_h: u32 = gpu.scaled(28);
        const menu_padding: u32 = gpu.scaled(8);
        const menu_inner_pad: i32 = gpu.scaledI(4);
        const menu_text_pad_y: i32 = gpu.scaledI(6);
        const menu_text_pad_x: i32 = gpu.scaledI(12);
        const menu_corner: u32 = gpu.scaled(8);
        const menu_item_corner: u32 = gpu.scaled(4);
        const menu_char_w: i32 = gpu.scaledI(9);

        // Items for each menu
        if (menu_open == 0) {
            // File menu
            const file_items = [_][]const u8{ "New", "Open File", "Open Folder", "Save", "Save As...", "Close Tab" };
            const file_shortcuts = [_]?[]const u8{ "Ctrl+N", "Ctrl+O", null, "Ctrl+S", "Ctrl+Shift+S", "Ctrl+W" };
            const dropdown_h: u32 = @as(u32, file_items.len) * menu_item_h + menu_padding;

            // Мягкая тень
            gpu.drawSoftShadow(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, 0, 4, 16, 90);
            // Background
            gpu.fillRoundedRect(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, COLOR_SURFACE);

            // Items
            var item_y: i32 = dropdown_y + menu_inner_pad;
            for (file_items, 0..) |item, idx| {
                const is_hovered = menu_item_hover == @as(i32, @intCast(idx));
                if (is_hovered) {
                    gpu.fillRoundedRect(dropdown_x + menu_inner_pad, item_y, dropdown_w - menu_padding, menu_item_h, menu_item_corner, COLOR_SELECTION);
                }
                const text_y = item_y + menu_text_pad_y;
                gpu.drawUIText(item, dropdown_x + menu_text_pad_x, text_y, if (is_hovered) COLOR_ACCENT else COLOR_TEXT);
                if (file_shortcuts[idx]) |sc| {
                    const sc_x: i32 = dropdown_x + @as(i32, @intCast(dropdown_w)) - @as(i32, @intCast(sc.len)) * menu_char_w - menu_text_pad_x;
                    gpu.drawUIText(sc, sc_x, text_y, COLOR_TEXT_DIM);
                }
                item_y += @intCast(menu_item_h);
            }
        } else if (menu_open == 1) {
            // Edit menu
            const edit_items = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste", "Search", "Settings" };
            const edit_shortcuts = [_]?[]const u8{ "Ctrl+Z", "Ctrl+Y", "Ctrl+X", "Ctrl+C", "Ctrl+V", "Ctrl+F", null };
            const dropdown_h: u32 = @as(u32, edit_items.len) * menu_item_h + menu_padding;

            // Мягкая тень
            gpu.drawSoftShadow(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, 0, 4, 16, 90);
            // Background
            gpu.fillRoundedRect(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, COLOR_SURFACE);

            var item_y: i32 = dropdown_y + menu_inner_pad;
            for (edit_items, 0..) |item, idx| {
                const is_hovered = menu_item_hover == @as(i32, @intCast(idx));
                if (is_hovered) {
                    gpu.fillRoundedRect(dropdown_x + menu_inner_pad, item_y, dropdown_w - menu_padding, menu_item_h, menu_item_corner, COLOR_SELECTION);
                }
                const text_y = item_y + menu_text_pad_y;
                gpu.drawUIText(item, dropdown_x + menu_text_pad_x, text_y, if (is_hovered) COLOR_ACCENT else COLOR_TEXT);
                if (edit_shortcuts[idx]) |sc| {
                    const sc_x: i32 = dropdown_x + @as(i32, @intCast(dropdown_w)) - @as(i32, @intCast(sc.len)) * menu_char_w - menu_text_pad_x;
                    gpu.drawUIText(sc, sc_x, text_y, COLOR_TEXT_DIM);
                }
                item_y += @intCast(menu_item_h);
            }
        } else if (menu_open == 2) {
            // View menu
            const view_items = [_][]const u8{ "Explorer", "Zoom In", "Zoom Out", "Reset Zoom", "---", "75%", "90%", "100%", "125%", "150%" };
            const view_shortcuts = [_]?[]const u8{ "Ctrl+B", "Ctrl++", "Ctrl+-", "Ctrl+0", null, null, null, null, null, null };
            const dropdown_h: u32 = @as(u32, view_items.len) * menu_item_h + menu_padding;

            // Мягкая тень
            gpu.drawSoftShadow(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, 0, 4, 16, 90);
            // Background
            gpu.fillRoundedRect(dropdown_x, dropdown_y, dropdown_w, dropdown_h, menu_corner, COLOR_SURFACE);

            var item_y: i32 = dropdown_y + menu_inner_pad;
            for (view_items, 0..) |item, idx| {
                // Separator
                if (std.mem.eql(u8, item, "---")) {
                    gpu.fillRect(dropdown_x + menu_text_pad_x, item_y + menu_text_pad_x, dropdown_w - gpu.scaled(24), 1, COLOR_ACCENT_DIM);
                    item_y += @intCast(menu_item_h);
                    continue;
                }

                const is_hovered = menu_item_hover == @as(i32, @intCast(idx));
                if (is_hovered) {
                    gpu.fillRoundedRect(dropdown_x + menu_inner_pad, item_y, dropdown_w - menu_padding, menu_item_h, menu_item_corner, COLOR_SELECTION);
                }
                const text_y = item_y + menu_text_pad_y;
                gpu.drawUIText(item, dropdown_x + menu_text_pad_x, text_y, if (is_hovered) COLOR_ACCENT else COLOR_TEXT);
                if (view_shortcuts[idx]) |sc| {
                    const sc_x: i32 = dropdown_x + @as(i32, @intCast(dropdown_w)) - @as(i32, @intCast(sc.len)) * menu_char_w - menu_text_pad_x;
                    gpu.drawUIText(sc, sc_x, text_y, COLOR_TEXT_DIM);
                }
                item_y += @intCast(menu_item_h);
            }
        }
    }

    // === Settings popup (закругленный с мягкой тенью) ===
    if (settings_visible) {
        const popup_w: u32 = 400;
        const popup_h: u32 = 300;
        const popup_x: i32 = @divTrunc(@as(i32, @intCast(wayland.width)) - @as(i32, @intCast(popup_w)), 2);
        const popup_y: i32 = @divTrunc(@as(i32, @intCast(wayland.height)) - @as(i32, @intCast(popup_h)), 2);

        // Мягкая тень
        gpu.drawSoftShadow(popup_x, popup_y, popup_w, popup_h, 12, 0, 8, 24, 100);

        // Background popup
        gpu.fillRoundedRect(popup_x, popup_y, popup_w, popup_h, 12, COLOR_SURFACE);

        // Title
        gpu.drawUIText("Settings", popup_x + 16, popup_y + 14, COLOR_TEXT);

        // Close button (закругленный, с hover + glow)
        const close_btn_x: i32 = popup_x + @as(i32, @intCast(popup_w)) - 36;
        const close_btn_y: i32 = popup_y + 8;
        const close_hovered = wayland.mouse_x >= close_btn_x and wayland.mouse_x < close_btn_x + 24 and
            wayland.mouse_y >= close_btn_y and wayland.mouse_y < close_btn_y + 24;
        if (close_hovered) {
            gpu.drawGlow(close_btn_x, close_btn_y, 24, 24, 6, 0xFFff6b6b, 12);
        }
        const close_bg: u32 = if (close_hovered) 0xFF4a3030 else COLOR_BG;
        const close_color: u32 = if (close_hovered) COLOR_BTN_CLOSE else COLOR_TEXT_DIM;
        gpu.fillRoundedRect(close_btn_x, close_btn_y, 24, 24, 6, close_bg);
        icons.drawIcon(gpu, .close, close_btn_x + 4, close_btn_y + 4, 16, close_color);

        // Separator
        gpu.fillRoundedRect(popup_x + 12, popup_y + 40, popup_w - 24, 1, 1, COLOR_ACCENT_DIM);

        // Tabs
        const tab_y = popup_y + 52;

        // About tab
        if (settings_tab_hovered == 0 and settings_active_tab != 0) {
            gpu.drawGlow(popup_x + 12, tab_y, 70, 28, 6, 0xFFd0a080, 10);
        }
        const about_tab_color: u32 = if (settings_active_tab == 0) COLOR_ACCENT_DIM else if (settings_tab_hovered == 0) COLOR_BTN_HOVER else COLOR_BG;
        gpu.fillRoundedRect(popup_x + 12, tab_y, 70, 28, 6, about_tab_color);
        gpu.drawUIText("About", popup_x + 26, tab_y + 7, if (settings_active_tab == 0 or settings_tab_hovered == 0) COLOR_ACCENT else COLOR_TEXT_DIM);

        // Additional tab
        if (settings_tab_hovered == 1 and settings_active_tab != 1) {
            gpu.drawGlow(popup_x + 90, tab_y, 90, 28, 6, 0xFFd0a080, 10);
        }
        const additional_tab_color: u32 = if (settings_active_tab == 1) COLOR_ACCENT_DIM else if (settings_tab_hovered == 1) COLOR_BTN_HOVER else COLOR_BG;
        gpu.fillRoundedRect(popup_x + 90, tab_y, 90, 28, 6, additional_tab_color);
        gpu.drawUIText("Additional", popup_x + 100, tab_y + 7, if (settings_active_tab == 1 or settings_tab_hovered == 1) COLOR_ACCENT else COLOR_TEXT_DIM);

        // UI tab
        if (settings_tab_hovered == 2 and settings_active_tab != 2) {
            gpu.drawGlow(popup_x + 188, tab_y, 50, 28, 6, 0xFFd0a080, 10);
        }
        const ui_tab_color: u32 = if (settings_active_tab == 2) COLOR_ACCENT_DIM else if (settings_tab_hovered == 2) COLOR_BTN_HOVER else COLOR_BG;
        gpu.fillRoundedRect(popup_x + 188, tab_y, 50, 28, 6, ui_tab_color);
        gpu.drawUIText("UI", popup_x + 202, tab_y + 7, if (settings_active_tab == 2 or settings_tab_hovered == 2) COLOR_ACCENT else COLOR_TEXT_DIM);

        const content_y = popup_y + 100;

        if (settings_active_tab == 0) {
            // About content
            gpu.drawUIText(PROJECT_NAME, popup_x + 16, content_y, COLOR_ACCENT);
            gpu.drawUIText("Version:", popup_x + 16, content_y + 28, COLOR_TEXT_DIM);
            gpu.drawUIText(PROJECT_VERSION, popup_x + 90, content_y + 28, COLOR_TEXT);
            gpu.drawUIText("A minimal code editor", popup_x + 16, content_y + 56, COLOR_TEXT_DIM);
            gpu.drawUIText("written in Zig", popup_x + 16, content_y + 76, COLOR_TEXT_DIM);
        } else if (settings_active_tab == 1) {
            // Additional content - Scrolling Inertia checkbox
            const checkbox_x = popup_x + 16;
            const checkbox_y = content_y;
            const checkbox_size: u32 = 18;

            // Hover background for entire row + glow
            if (settings_checkbox_hovered) {
                gpu.drawGlow(popup_x + 12, checkbox_y - 4, popup_w - 24, 44, 6, 0xFFd0a080, 10);
                gpu.fillRoundedRect(popup_x + 12, checkbox_y - 4, popup_w - 24, 44, 6, COLOR_BTN_HOVER);
            }

            // Checkbox border (outer) - brighter on hover
            const border_color: u32 = if (settings_checkbox_hovered) COLOR_ACCENT else COLOR_TEXT_DIM;
            gpu.fillRoundedRect(checkbox_x, checkbox_y, checkbox_size, checkbox_size, 4, border_color);
            // Checkbox background (внутренний)
            gpu.fillRoundedRect(checkbox_x + 1, checkbox_y + 1, checkbox_size - 2, checkbox_size - 2, 3, COLOR_BG);

            // Checkmark if enabled
            if (g_scroll_inertia) {
                gpu.fillRoundedRect(checkbox_x + 4, checkbox_y + 4, checkbox_size - 8, checkbox_size - 8, 2, COLOR_ACCENT);
            }

            // Label - brighter on hover
            const label_color: u32 = if (settings_checkbox_hovered) COLOR_ACCENT else COLOR_TEXT;
            gpu.drawUIText("Scrolling Inertia", checkbox_x + 26, checkbox_y + 2, label_color);
            gpu.drawUIText("Smooth momentum scrolling", popup_x + 16, checkbox_y + 24, COLOR_TEXT_DIM);

            // === Scroll Speed Slider ===
            const slider_y = checkbox_y + 60;
            gpu.drawUIText("Scroll Speed", popup_x + 16, slider_y, COLOR_TEXT);
            gpu.drawUIText("Adjust scrolling speed multiplier", popup_x + 16, slider_y + 20, COLOR_TEXT_DIM);

            // Render слайдер
            const slider_track_y = slider_y + 44;
            const slider_x = popup_x + 16;
            const slider_w: i32 = @as(i32, @intCast(popup_w)) - 80;

            // Background трека
            gpu.fillRoundedRect(slider_x, slider_track_y + 6, @intCast(slider_w), 8, 4, 0xFF2a2a2a);

            // Заполненная часть
            const normalized = (g_scroll_speed_slider.value - g_scroll_speed_slider.min_value) / (g_scroll_speed_slider.max_value - g_scroll_speed_slider.min_value);
            const filled_w: u32 = @intFromFloat(@as(f32, @floatFromInt(slider_w)) * normalized);
            if (filled_w > 4) {
                gpu.fillRoundedRect(slider_x, slider_track_y + 6, filled_w, 8, 4, COLOR_ACCENT_DIM);
            }

            // Ручка слайдера
            const handle_x: i32 = slider_x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(slider_w - 16)) * normalized));
            const handle_color: u32 = if (g_scroll_speed_slider.is_dragging) COLOR_ACCENT else if (g_scroll_speed_slider.is_hovered) 0xFFdddddd else 0xFFaaaaaa;
            gpu.fillRoundedRect(handle_x, slider_track_y, 16, 20, 4, handle_color);

            // Значение справа
            var speed_buf: [16]u8 = undefined;
            const speed_str = std.fmt.bufPrint(&speed_buf, "{d:.1}x", .{g_scroll_speed_slider.value}) catch "?";
            gpu.drawUIText(speed_str, slider_x + slider_w + 10, slider_track_y + 2, COLOR_TEXT);

            // Update позицию слайдера для обработки событий
            g_scroll_speed_slider.x = slider_x;
            g_scroll_speed_slider.y = slider_track_y;
            g_scroll_speed_slider.width = slider_w;
            g_scroll_speed_slider.height = 20;
        } else if (settings_active_tab == 2) {
            // UI content - Line Visibility slider
            gpu.drawUIText("Line Separators", popup_x + 16, content_y, COLOR_TEXT);
            gpu.drawUIText("Visibility of line separators between rows", popup_x + 16, content_y + 20, COLOR_TEXT_DIM);

            // Render slider
            const slider_track_y = content_y + 44;
            const slider_x = popup_x + 16;
            const slider_w: i32 = @as(i32, @intCast(popup_w)) - 80;

            // Background track
            gpu.fillRoundedRect(slider_x, slider_track_y + 6, @intCast(slider_w), 8, 4, 0xFF2a2a2a);

            // Filled part
            const normalized = g_line_visibility_slider.value; // Already 0-1
            const filled_w: u32 = @intFromFloat(@as(f32, @floatFromInt(slider_w)) * normalized);
            if (filled_w > 4) {
                gpu.fillRoundedRect(slider_x, slider_track_y + 6, filled_w, 8, 4, COLOR_ACCENT_DIM);
            }

            // Slider handle
            const handle_x: i32 = slider_x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(slider_w - 16)) * normalized));
            const handle_color: u32 = if (g_line_visibility_slider.is_dragging) COLOR_ACCENT else if (g_line_visibility_slider.is_hovered) 0xFFdddddd else 0xFFaaaaaa;
            gpu.fillRoundedRect(handle_x, slider_track_y, 16, 20, 4, handle_color);

            // Value on the right (0% - 100%)
            var vis_buf: [16]u8 = undefined;
            const vis_str = std.fmt.bufPrint(&vis_buf, "{d:.0}%", .{g_line_visibility_slider.value * 100}) catch "?";
            gpu.drawUIText(vis_str, slider_x + slider_w + 10, slider_track_y + 2, COLOR_TEXT);

            // Update slider position for event handling
            g_line_visibility_slider.x = slider_x;
            g_line_visibility_slider.y = slider_track_y;
            g_line_visibility_slider.width = slider_w;
            g_line_visibility_slider.height = 20;
        }
    }

    // === Confirm Dialog (on top of everything) ===
    if (g_confirm_dialog.visible) {
        // Update hover states
        _ = g_confirm_dialog.update(wayland.mouse_x, wayland.mouse_y, false, false);
        // Draw the dialog
        g_confirm_dialog.draw(gpu);
    }

    // === LSP Completion Popup ===
    if (g_lsp_completion_visible) {
        const completions = lspGetCompletions();
        if (completions.len > 0) {
            const popup_w: u32 = 300;
            const item_h: u32 = 24;
            const max_items: usize = @min(completions.len, 10);
            const popup_h: u32 = @as(u32, @intCast(max_items)) * item_h + 8;

            const popup_x = g_lsp_completion_x;
            const popup_y = g_lsp_completion_y;

            // Background with shadow
            gpu.fillRoundedRect(popup_x + 4, popup_y + 4, popup_w, popup_h, 6, 0x40000000);
            gpu.fillRoundedRect(popup_x, popup_y, popup_w, popup_h, 6, 0xFF2d2d2d);
            gpu.fillRoundedRect(popup_x + 1, popup_y + 1, popup_w - 2, popup_h - 2, 5, 0xFF252525);

            // Items
            var y_pos: i32 = popup_y + 4;
            for (0..max_items) |i| {
                const item = &completions[i];
                const is_selected = (@as(i32, @intCast(i)) == g_lsp_completion_selected);

                // Selection highlight
                if (is_selected) {
                    gpu.fillRoundedRect(popup_x + 4, y_pos, popup_w - 8, item_h - 2, 4, COLOR_ACCENT_DIM);
                }

                // Kind icon (simplified)
                // LSP CompletionItemKind: 1=Text, 2=Method, 3=Function, 4=Constructor,
                // 5=Field, 6=Variable, 7=Class, 8=Interface, 9=Module, 10=Property, 14=Keyword
                const kind_char: []const u8 = switch (item.kind) {
                    2 => "m", // method
                    3 => "f", // function
                    5, 10 => "p", // field/property
                    6 => "v", // variable
                    7 => "C", // class
                    9 => "M", // module
                    14 => "k", // keyword
                    else => "·",
                };
                const kind_color: u32 = switch (item.kind) {
                    2, 3 => SYN_FUNCTION, // function/method
                    5, 10 => SYN_FIELD, // field
                    6 => SYN_BUILTIN, // variable
                    7 => SYN_TYPE, // class
                    14 => SYN_KEYWORD, // keyword
                    else => COLOR_TEXT_DIM,
                };
                gpu.drawUIText(kind_char, popup_x + 8, y_pos + 4, kind_color);

                // Label
                const label = item.getLabel();
                const label_color: u32 = if (is_selected) COLOR_TEXT else COLOR_TEXT_DIM;
                gpu.drawUIText(label, popup_x + 24, y_pos + 4, label_color);

                // Detail (if fits)
                const detail = item.getDetail();
                if (detail.len > 0 and detail.len < 30) {
                    gpu.drawUIText(detail, popup_x + @as(i32, @intCast(popup_w)) - 8 - @as(i32, @intCast(detail.len * 7)), y_pos + 4, COLOR_TEXT_DIM);
                }

                y_pos += @as(i32, @intCast(item_h));
            }

            // Scrollbar hint if more items
            if (completions.len > 10) {
                var hint_buf: [16]u8 = undefined;
                const hint = std.fmt.bufPrint(&hint_buf, "+{d} more", .{completions.len - 10}) catch "...";
                gpu.drawUIText(hint, popup_x + @as(i32, @intCast(popup_w)) - 60, popup_y + @as(i32, @intCast(popup_h)) - 16, COLOR_TEXT_DIM);
            }
        } else {
            g_lsp_completion_visible = false;
        }
    }

    // === LSP Diagnostics underlines ===
    if (g_lsp_diagnostics_visible and lspIsConnected()) {
        const diagnostics = lspGetDiagnostics();
        _ = diagnostics; // TODO: Draw diagnostic underlines in editor
    }
}

fn drawTitlebar(gpu: *GpuRenderer, width: u32, mouse_x: i32, mouse_y: i32, menu_hover: i32, is_maximized: bool, zoom: f32) void {
    // Get масштабированные размеры
    const titlebar_h = gpu.scaled(TITLEBAR_HEIGHT);
    const corner_r = gpu.scaled(CORNER_RADIUS);
    _ = zoom; // Пока не используется напрямую

    // Titlebar background (скруглён сверху)
    gpu.fillRoundedRect(0, 0, width, titlebar_h + corner_r, corner_r, COLOR_SURFACE);
    // Перекрываем нижнюю часть чтобы убрать скругление снизу
    gpu.fillRect(0, @as(i32, @intCast(titlebar_h)) - 2, width, corner_r + 2, COLOR_SURFACE);

    // === Menu block слева - единый блок как window controls ===
    const menu_width: u32 = gpu.scaled(140);
    const menu_height: u32 = gpu.scaled(26);
    const menu_x: i32 = gpu.scaledI(8);
    const menu_y: i32 = @divTrunc(@as(i32, @intCast(titlebar_h)) - @as(i32, @intCast(menu_height)), 2);
    const menu_section: i32 = @divTrunc(@as(i32, @intCast(menu_width)), 3);

    // Background блока меню (закруглённый)
    gpu.fillRoundedRect(menu_x, menu_y, menu_width, menu_height, 6, COLOR_BG);

    const text_cy = menu_y + @divTrunc(@as(i32, @intCast(menu_height)) - 14, 2); // UI font height ~14

    // File секция (левая - закруглена слева)
    if (menu_hover == 0) {
        gpu.fillRoundedRect(menu_x, menu_y, @intCast(menu_section), menu_height, 6, COLOR_BTN_HOVER);
        gpu.fillRect(menu_x + menu_section - 6, menu_y, 6, menu_height, COLOR_BTN_HOVER);
    }
    const file_text_w: i32 = @intCast(gpu.uiTextWidth("File"));
    const file_text_x = menu_x + @divTrunc(menu_section - file_text_w, 2);
    gpu.drawUIText("File", file_text_x, text_cy, if (menu_hover == 0) COLOR_ACCENT else COLOR_TEXT_DIM);

    // Edit секция (центр - без закруглений)
    if (menu_hover == 1) {
        gpu.fillRect(menu_x + menu_section, menu_y, @intCast(menu_section), menu_height, COLOR_BTN_HOVER);
    }
    const edit_text_w: i32 = @intCast(gpu.uiTextWidth("Edit"));
    const edit_text_x = menu_x + menu_section + @divTrunc(menu_section - edit_text_w, 2);
    gpu.drawUIText("Edit", edit_text_x, text_cy, if (menu_hover == 1) COLOR_ACCENT else COLOR_TEXT_DIM);

    // View секция (правая - закруглена справа)
    if (menu_hover == 2) {
        gpu.fillRoundedRect(menu_x + menu_section * 2 - 6, menu_y, @intCast(menu_section + 6), menu_height, 6, COLOR_BTN_HOVER);
        gpu.fillRect(menu_x + menu_section * 2, menu_y, 6, menu_height, COLOR_BTN_HOVER);
    }
    const view_text_w: i32 = @intCast(gpu.uiTextWidth("View"));
    const view_text_x = menu_x + menu_section * 2 + @divTrunc(menu_section - view_text_w, 2);
    gpu.drawUIText("View", view_text_x, text_cy, if (menu_hover == 2) COLOR_ACCENT else COLOR_TEXT_DIM);

    // Разделители между секциями меню
    gpu.fillRect(menu_x + menu_section, menu_y + 5, 1, menu_height - 10, COLOR_TEXT_DIM);
    gpu.fillRect(menu_x + menu_section * 2, menu_y + 5, 1, menu_height - 10, COLOR_TEXT_DIM);

    // === Window controls - единая кнопка справа с 3 секциями ===
    const ctrl_width: u32 = gpu.scaled(90);
    const ctrl_height: u32 = gpu.scaled(26);
    const ctrl_x: i32 = @as(i32, @intCast(width)) - @as(i32, @intCast(ctrl_width)) - gpu.scaledI(8);
    const ctrl_y: i32 = @divTrunc(@as(i32, @intCast(titlebar_h)) - @as(i32, @intCast(ctrl_height)), 2);
    const section_width: i32 = @divTrunc(@as(i32, @intCast(ctrl_width)), 3);

    const in_ctrl = mouse_y >= ctrl_y and
        mouse_y < ctrl_y + @as(i32, @intCast(ctrl_height)) and
        mouse_x >= ctrl_x and
        mouse_x < ctrl_x + @as(i32, @intCast(ctrl_width));

    // Background кнопки (скруглённый)
    gpu.fillRoundedRect(ctrl_x, ctrl_y, ctrl_width, ctrl_height, 6, COLOR_BG);

    // Determine which section is under cursor
    var hover_section: i32 = -1;
    if (in_ctrl) {
        const rel_x = mouse_x - ctrl_x;
        hover_section = @divTrunc(rel_x, section_width);
    }

    const icon_size: i32 = gpu.scaledI(20);

    // Секция 0: Minimize (слева)
    const min_x = ctrl_x;
    if (hover_section == 0) {
        gpu.fillRoundedRect(min_x, ctrl_y, @intCast(section_width), ctrl_height, 6, COLOR_BTN_HOVER);
    }
    const min_icon_x = min_x + @divTrunc(section_width - icon_size, 2);
    const min_icon_y = ctrl_y + @divTrunc(@as(i32, @intCast(ctrl_height)) - icon_size, 2);
    icons.drawIcon(gpu, .window_minimize, min_icon_x, min_icon_y, @intCast(icon_size), if (hover_section == 0) COLOR_ACCENT else COLOR_TEXT_DIM);

    // Секция 1: Maximize/Restore (центр)
    const max_x = ctrl_x + section_width;
    if (hover_section == 1) {
        gpu.fillRect(max_x, ctrl_y, @intCast(section_width), ctrl_height, COLOR_BTN_HOVER);
    }
    const max_icon_x = max_x + @divTrunc(section_width - icon_size, 2);
    const max_icon_y = ctrl_y + @divTrunc(@as(i32, @intCast(ctrl_height)) - icon_size, 2);
    const max_icon_type: icons.IconType = if (is_maximized) .window_restore else .window_maximize;
    icons.drawIcon(gpu, max_icon_type, max_icon_x, max_icon_y, @intCast(icon_size), if (hover_section == 1) COLOR_ACCENT else COLOR_TEXT_DIM);

    // Секция 2: Close (справа)
    const close_x = ctrl_x + section_width * 2;
    if (hover_section == 2) {
        gpu.fillRoundedRect(close_x, ctrl_y, @intCast(section_width), ctrl_height, 6, 0xFF4a2020);
    }
    const close_icon_x = close_x + @divTrunc(section_width - icon_size, 2);
    const close_icon_y = ctrl_y + @divTrunc(@as(i32, @intCast(ctrl_height)) - icon_size, 2);
    icons.drawIcon(gpu, .window_close, close_icon_x, close_icon_y, @intCast(icon_size), if (hover_section == 2) COLOR_BTN_CLOSE else COLOR_TEXT_DIM);

    // Разделители между секциями
    gpu.fillRect(ctrl_x + section_width, ctrl_y + 5, 1, ctrl_height - 10, COLOR_TEXT_DIM);
    gpu.fillRect(ctrl_x + section_width * 2, ctrl_y + 5, 1, ctrl_height - 10, COLOR_TEXT_DIM);
}

// === File Operations ===

/// Create new file in folder
fn createNewFile(
    folder_path: []const u8,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    // Generate unique filename
    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "untitled_{d}.txt", .{g_new_file_counter}) catch return;
    g_new_file_counter += 1;

    // Build full path
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ folder_path, name }) catch return;

    // Create empty file
    const file = std.fs.cwd().createFile(path, .{}) catch return;
    file.close();

    // Refresh folder listing
    listFolderContentsTree(folder_path, files, file_lens, file_count, is_dir, expanded, anim_progress, indent, parent, full_path, full_path_lens);
}

/// Create new folder
fn createNewFolder(
    folder_path: []const u8,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    // Generate unique folder name
    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "new_folder_{d}", .{g_new_folder_counter}) catch return;
    g_new_folder_counter += 1;

    // Build full path
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ folder_path, name }) catch return;

    // Create folder
    std.fs.cwd().makeDir(path) catch return;

    // Refresh folder listing
    listFolderContentsTree(folder_path, files, file_lens, file_count, is_dir, expanded, anim_progress, indent, parent, full_path, full_path_lens);
}

/// Delete file or folder
fn deleteFileOrFolder(
    folder_path: []const u8,
    target_path: []const u8,
    is_directory: bool,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    if (is_directory) {
        // Delete directory recursively
        std.fs.cwd().deleteTree(target_path) catch return;
    } else {
        // Delete file
        std.fs.cwd().deleteFile(target_path) catch return;
    }

    // Refresh folder listing
    listFolderContentsTree(folder_path, files, file_lens, file_count, is_dir, expanded, anim_progress, indent, parent, full_path, full_path_lens);
}

/// Rename file or folder
fn renameFileOrFolder(
    folder_path: []const u8,
    old_path: []const u8,
    new_name: []const u8,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    // Find parent directory of old_path
    var parent_end: usize = old_path.len;
    while (parent_end > 0 and old_path[parent_end - 1] != '/') {
        parent_end -= 1;
    }

    // Build new path: parent dir + new name
    var new_path_buf: [512]u8 = undefined;
    const new_path = std.fmt.bufPrint(&new_path_buf, "{s}{s}", .{ old_path[0..parent_end], new_name }) catch return;

    // Rename using std.fs
    std.fs.cwd().rename(old_path, new_path) catch return;

    // Refresh folder listing
    listFolderContentsTree(folder_path, files, file_lens, file_count, is_dir, expanded, anim_progress, indent, parent, full_path, full_path_lens);
}

fn openFolderDialog(
    folder_path: *[1024]u8,
    folder_len: *usize,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    // Use zenity to select folder
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "zenity", "--file-selection", "--directory", "--title=Open Folder" },
    }) catch return;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        // Убираем trailing newline
        var len = result.stdout.len;
        while (len > 0 and (result.stdout[len - 1] == '\n' or result.stdout[len - 1] == '\r')) {
            len -= 1;
        }
        if (len > 0 and len < 1024) {
            @memcpy(folder_path[0..len], result.stdout[0..len]);
            folder_len.* = len;
            // Sync to global for search
            @memcpy(g_current_folder[0..len], result.stdout[0..len]);
            g_current_folder_len = len;
            listFolderContentsTree(folder_path[0..len], files, file_lens, file_count, is_dir, expanded, anim_progress, indent, parent, full_path, full_path_lens);
        }
    }
}

fn listFolderContentsTree(
    path: []const u8,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    file_count.* = 0;

    // Reset всех состояний
    for (0..256) |reset_idx| {
        expanded[reset_idx] = false;
        anim_progress[reset_idx] = 0.0;
        indent[reset_idx] = 0;
        parent[reset_idx] = -1;
        full_path_lens[reset_idx] = 0;
    }

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (file_count.* >= 256) break;
        if (entry.name[0] == '.') continue; // Skip скрытые файлы

        const idx = file_count.*;
        const name_len = @min(entry.name.len, 255);
        @memcpy(files[idx][0..name_len], entry.name[0..name_len]);
        file_lens[idx] = name_len;
        is_dir[idx] = entry.kind == .directory;

        // Build полный путь
        const base_len = path.len;
        @memcpy(full_path[idx][0..base_len], path);
        full_path[idx][base_len] = '/';
        @memcpy(full_path[idx][base_len + 1 .. base_len + 1 + name_len], entry.name[0..name_len]);
        full_path_lens[idx] = base_len + 1 + name_len;

        indent[idx] = 0;
        parent[idx] = -1;
        file_count.* += 1;
    }

    // Sort: папки сначала, потом по имени
    sortFolderContents(files, file_lens, file_count.*, is_dir, full_path, full_path_lens, indent, parent);
}

fn sortFolderContents(
    files: *[256][256]u8,
    file_lens: *[256]usize,
    count: usize,
    is_dir: *[256]bool,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
    indent: *[256]u8,
    parent: *[256]i16,
) void {
    // Простая сортировка пузырьком (папки сначала, потом алфавит)
    var swapped = true;
    while (swapped) {
        swapped = false;
        var sort_i: usize = 0;
        while (sort_i + 1 < count) : (sort_i += 1) {
            var should_swap = false;

            // Папки идут первыми
            if (!is_dir[sort_i] and is_dir[sort_i + 1]) {
                should_swap = true;
            } else if (is_dir[sort_i] == is_dir[sort_i + 1]) {
                // Одинаковый тип - сравниваем по имени
                const len_a = file_lens[sort_i];
                const len_b = file_lens[sort_i + 1];
                const min_len = @min(len_a, len_b);
                var cmp_idx: usize = 0;
                while (cmp_idx < min_len) : (cmp_idx += 1) {
                    const a = std.ascii.toLower(files[sort_i][cmp_idx]);
                    const b = std.ascii.toLower(files[sort_i + 1][cmp_idx]);
                    if (a > b) {
                        should_swap = true;
                        break;
                    } else if (a < b) {
                        break;
                    }
                }
                if (cmp_idx == min_len and len_a > len_b) {
                    should_swap = true;
                }
            }

            if (should_swap) {
                // Swap all arrays
                var tmp_name: [256]u8 = undefined;
                @memcpy(&tmp_name, &files[sort_i]);
                @memcpy(&files[sort_i], &files[sort_i + 1]);
                @memcpy(&files[sort_i + 1], &tmp_name);

                const tmp_len = file_lens[sort_i];
                file_lens[sort_i] = file_lens[sort_i + 1];
                file_lens[sort_i + 1] = tmp_len;

                const tmp_dir = is_dir[sort_i];
                is_dir[sort_i] = is_dir[sort_i + 1];
                is_dir[sort_i + 1] = tmp_dir;

                var tmp_path: [512]u8 = undefined;
                @memcpy(&tmp_path, &full_path[sort_i]);
                @memcpy(&full_path[sort_i], &full_path[sort_i + 1]);
                @memcpy(&full_path[sort_i + 1], &tmp_path);

                const tmp_path_len = full_path_lens[sort_i];
                full_path_lens[sort_i] = full_path_lens[sort_i + 1];
                full_path_lens[sort_i + 1] = tmp_path_len;

                const tmp_indent = indent[sort_i];
                indent[sort_i] = indent[sort_i + 1];
                indent[sort_i + 1] = tmp_indent;

                const tmp_parent = parent[sort_i];
                parent[sort_i] = parent[sort_i + 1];
                parent[sort_i + 1] = tmp_parent;

                swapped = true;
            }
        }
    }
}

fn expandFolder(
    idx: usize,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    const parent_path = full_path[idx][0..full_path_lens[idx]];
    const parent_indent = indent[idx];

    // Open директорию
    var dir = std.fs.cwd().openDir(parent_path, .{ .iterate = true }) catch return;
    defer dir.close();

    // Collect дочерние элементы во временный буфер
    var temp_names: [64][256]u8 = undefined;
    var temp_lens: [64]usize = undefined;
    var temp_is_dir: [64]bool = undefined;
    var temp_full_path: [64][512]u8 = undefined;
    var temp_full_path_lens: [64]usize = undefined;
    var temp_count: usize = 0;

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (temp_count >= 64) break;
        if (entry.name[0] == '.') continue;

        const name_len = @min(entry.name.len, 255);
        @memcpy(temp_names[temp_count][0..name_len], entry.name[0..name_len]);
        temp_lens[temp_count] = name_len;
        temp_is_dir[temp_count] = entry.kind == .directory;

        // Полный путь
        const base_len = parent_path.len;
        @memcpy(temp_full_path[temp_count][0..base_len], parent_path);
        temp_full_path[temp_count][base_len] = '/';
        @memcpy(temp_full_path[temp_count][base_len + 1 .. base_len + 1 + name_len], entry.name[0..name_len]);
        temp_full_path_lens[temp_count] = base_len + 1 + name_len;

        temp_count += 1;
    }

    if (temp_count == 0) return;

    // Sort временный буфер (папки сначала, потом алфавит)
    var swapped = true;
    while (swapped) {
        swapped = false;
        var sort_i: usize = 0;
        while (sort_i + 1 < temp_count) : (sort_i += 1) {
            var should_swap = false;
            if (!temp_is_dir[sort_i] and temp_is_dir[sort_i + 1]) {
                should_swap = true;
            } else if (temp_is_dir[sort_i] == temp_is_dir[sort_i + 1]) {
                const len_a = temp_lens[sort_i];
                const len_b = temp_lens[sort_i + 1];
                const min_len = @min(len_a, len_b);
                var cmp_idx: usize = 0;
                while (cmp_idx < min_len) : (cmp_idx += 1) {
                    const a = std.ascii.toLower(temp_names[sort_i][cmp_idx]);
                    const b = std.ascii.toLower(temp_names[sort_i + 1][cmp_idx]);
                    if (a > b) {
                        should_swap = true;
                        break;
                    } else if (a < b) {
                        break;
                    }
                }
            }

            if (should_swap) {
                var tmp_name: [256]u8 = undefined;
                @memcpy(&tmp_name, &temp_names[sort_i]);
                @memcpy(&temp_names[sort_i], &temp_names[sort_i + 1]);
                @memcpy(&temp_names[sort_i + 1], &tmp_name);

                const tmp_len = temp_lens[sort_i];
                temp_lens[sort_i] = temp_lens[sort_i + 1];
                temp_lens[sort_i + 1] = tmp_len;

                const tmp_dir = temp_is_dir[sort_i];
                temp_is_dir[sort_i] = temp_is_dir[sort_i + 1];
                temp_is_dir[sort_i + 1] = tmp_dir;

                var tmp_path: [512]u8 = undefined;
                @memcpy(&tmp_path, &temp_full_path[sort_i]);
                @memcpy(&temp_full_path[sort_i], &temp_full_path[sort_i + 1]);
                @memcpy(&temp_full_path[sort_i + 1], &tmp_path);

                const tmp_path_len = temp_full_path_lens[sort_i];
                temp_full_path_lens[sort_i] = temp_full_path_lens[sort_i + 1];
                temp_full_path_lens[sort_i + 1] = tmp_path_len;

                swapped = true;
            }
        }
    }

    // Insert after idx
    const insert_pos = idx + 1;
    const elements_to_move = file_count.* - insert_pos;

    // Check, что есть место
    if (file_count.* + temp_count > 256) {
        const max_to_add = 256 - file_count.*;
        if (max_to_add == 0) return;
        temp_count = max_to_add;
    }

    // Shift существующие элементы вправо
    if (elements_to_move > 0) {
        var move_i: usize = elements_to_move;
        while (move_i > 0) {
            move_i -= 1;
            const src = insert_pos + move_i;
            const dst = insert_pos + temp_count + move_i;

            @memcpy(&files[dst], &files[src]);
            file_lens[dst] = file_lens[src];
            is_dir[dst] = is_dir[src];
            expanded[dst] = expanded[src];
            anim_progress[dst] = anim_progress[src];
            indent[dst] = indent[src];
            parent[dst] = parent[src];
            @memcpy(&full_path[dst], &full_path[src]);
            full_path_lens[dst] = full_path_lens[src];
        }

        // Update parent references
        for (0..file_count.* + temp_count) |upd_i| {
            if (parent[upd_i] >= @as(i16, @intCast(insert_pos))) {
                parent[upd_i] += @intCast(temp_count);
            }
        }
    }

    // Insert новые элементы
    for (0..temp_count) |add_i| {
        const dst = insert_pos + add_i;
        @memcpy(&files[dst], &temp_names[add_i]);
        file_lens[dst] = temp_lens[add_i];
        is_dir[dst] = temp_is_dir[add_i];
        expanded[dst] = false;
        anim_progress[dst] = 0.0;
        indent[dst] = parent_indent + 1;
        parent[dst] = @intCast(idx);
        @memcpy(&full_path[dst], &temp_full_path[add_i]);
        full_path_lens[dst] = temp_full_path_lens[add_i];
    }

    file_count.* += temp_count;
}

fn collapseFolder(
    idx: usize,
    files: *[256][256]u8,
    file_lens: *[256]usize,
    file_count: *usize,
    is_dir: *[256]bool,
    expanded: *[256]bool,
    anim_progress: *[256]f32,
    indent: *[256]u8,
    parent: *[256]i16,
    full_path: *[256][512]u8,
    full_path_lens: *[256]usize,
) void {
    // Find all child elements (direct and nested)
    var children_to_remove: usize = 0;

    // Count how many elements to delete
    var check_idx = idx + 1;
    while (check_idx < file_count.*) : (check_idx += 1) {
        // Check if element is descendant of idx
        var current_parent = parent[check_idx];
        var is_descendant = false;
        while (current_parent >= 0) {
            if (@as(usize, @intCast(current_parent)) == idx) {
                is_descendant = true;
                break;
            }
            current_parent = parent[@intCast(current_parent)];
        }
        if (is_descendant) {
            children_to_remove += 1;
        } else {
            break; // Дети идут подряд, так что можно выйти
        }
    }

    if (children_to_remove == 0) return;

    // Delete дочерние элементы, сдвигая оставшиеся влево
    const remove_start = idx + 1;
    const remaining = file_count.* - remove_start - children_to_remove;

    for (0..remaining) |move_i| {
        const src = remove_start + children_to_remove + move_i;
        const dst = remove_start + move_i;

        @memcpy(&files[dst], &files[src]);
        file_lens[dst] = file_lens[src];
        is_dir[dst] = is_dir[src];
        expanded[dst] = expanded[src];
        anim_progress[dst] = anim_progress[src];
        indent[dst] = indent[src];
        parent[dst] = parent[src];
        @memcpy(&full_path[dst], &full_path[src]);
        full_path_lens[dst] = full_path_lens[src];
    }

    // Update parent references
    for (0..file_count.* - children_to_remove) |upd_i| {
        if (parent[upd_i] > @as(i16, @intCast(idx + children_to_remove))) {
            parent[upd_i] -= @intCast(children_to_remove);
        }
    }

    file_count.* -= children_to_remove;
}

fn saveFile(path: []const u8, buffer: *const GapBuffer) void {
    const file = std.fs.cwd().createFile(path, .{}) catch return;
    defer file.close();

    // Write содержимое буфера
    var write_idx: usize = 0;
    while (write_idx < buffer.len()) : (write_idx += 1) {
        if (buffer.charAtConst(write_idx)) |ch| {
            _ = file.write(&[_]u8{ch}) catch return;
        }
    }
}

fn saveFileDialog(file_path: *[1024]u8, file_len: *usize, buffer: *const GapBuffer) void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "zenity", "--file-selection", "--save", "--confirm-overwrite", "--title=Save As" },
    }) catch return;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        var len = result.stdout.len;
        while (len > 0 and (result.stdout[len - 1] == '\n' or result.stdout[len - 1] == '\r')) {
            len -= 1;
        }
        if (len > 0 and len < 1024) {
            @memcpy(file_path[0..len], result.stdout[0..len]);
            file_len.* = len;
            saveFile(file_path[0..len], buffer);
        }
    }
}

fn loadFile(path: []const u8, buffer: *GapBuffer) void {
    const start = std.time.milliTimestamp();

    // Use memory-mapped file loading (instant for any file size)
    if (!buffer.loadFileMmap(path)) {
        logger.info("[LOAD] mmap failed, using lazy loader\n", .{});
        _ = g_lazy_loader.startLoad(path, buffer);
    }

    const elapsed = std.time.milliTimestamp() - start;
    logger.info("[LOAD] File loaded in {}ms, size={}, lines={}\n", .{elapsed, buffer.len(), buffer.lineCount()});
}

// ============================================================================
// LSP INTEGRATION
// ============================================================================

/// Start LSP server for the current file (based on plugin)
fn lspStartForFile(file_path: []const u8) void {
    // Stop existing connection
    if (g_lsp_conn_id >= 0) {
        lsp.getClient().stopServer(g_lsp_conn_id);
        g_lsp_conn_id = -1;
    }

    // Find plugin for this file
    const loader = plugins.getLoader();
    const plugin_idx = loader.findPluginForFile(file_path) orelse return;
    const plugin = loader.getPlugin(plugin_idx) orelse return;

    // Check if plugin has LSP support
    if (!plugin.info.has_lsp) return;

    const lsp_cmd = plugin.info.getLspCommand();
    const lsp_args = plugin.info.getLspArgs();

    if (lsp_cmd.len == 0) return;

    // Get workspace root (use current folder or file's directory)
    var root_path: [512]u8 = undefined;
    var root_len: usize = 0;

    if (g_current_folder_len > 0) {
        @memcpy(root_path[0..g_current_folder_len], g_current_folder[0..g_current_folder_len]);
        root_len = g_current_folder_len;
    } else {
        // Use file's directory
        if (std.mem.lastIndexOfScalar(u8, file_path, '/')) |idx| {
            @memcpy(root_path[0..idx], file_path[0..idx]);
            root_len = idx;
        }
    }

    if (root_len == 0) return;

    // Start LSP server
    g_lsp_conn_id = lsp.getClient().startServer(lsp_cmd, lsp_args, root_path[0..root_len]);
    g_lsp_file_version = 1;
}

/// Notify LSP that file was opened
fn lspDidOpen(file_path: []const u8, buffer: *GapBuffer) void {
    if (g_lsp_conn_id < 0) return;

    // Build file URI
    var uri_buf: [600]u8 = undefined;
    const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{file_path}) catch return;

    // Get language ID from plugin
    const loader = plugins.getLoader();
    const plugin_idx = loader.findPluginForFile(file_path) orelse return;
    const plugin = loader.getPlugin(plugin_idx) orelse return;
    const lang_id = plugin.info.getLanguageId();

    if (lang_id.len == 0) return;

    // Get buffer content
    var content_buf: [65536]u8 = undefined;
    const content_len = buffer.copyTo(&content_buf);

    lsp.getClient().didOpen(g_lsp_conn_id, uri, lang_id, content_buf[0..content_len]) catch |e| logger.warn("Operation failed: {}", .{e});
}

/// Notify LSP that file content changed
fn lspDidChange(file_path: []const u8, buffer: *GapBuffer) void {
    if (g_lsp_conn_id < 0) return;

    // Build file URI
    var uri_buf: [600]u8 = undefined;
    const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{file_path}) catch return;

    // Get buffer content
    var content_buf: [65536]u8 = undefined;
    const content_len = buffer.copyTo(&content_buf);

    g_lsp_file_version += 1;
    lsp.getClient().didChange(g_lsp_conn_id, uri, g_lsp_file_version, content_buf[0..content_len]) catch |e| logger.warn("Operation failed: {}", .{e});
}

/// Request completion at cursor position
fn lspRequestCompletion(file_path: []const u8, line: u32, col: u32) void {
    if (g_lsp_conn_id < 0) return;

    var uri_buf: [600]u8 = undefined;
    const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{file_path}) catch return;

    _ = lsp.getClient().requestCompletion(g_lsp_conn_id, uri, line, col) catch |e| logger.warn("Operation failed: {}", .{e});
}

/// Request hover info at cursor position
fn lspRequestHover(file_path: []const u8, line: u32, col: u32) void {
    if (g_lsp_conn_id < 0) return;

    var uri_buf: [600]u8 = undefined;
    const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{file_path}) catch return;

    _ = lsp.getClient().requestHover(g_lsp_conn_id, uri, line, col) catch |e| logger.warn("Operation failed: {}", .{e});
}

/// Request go to definition
fn lspRequestDefinition(file_path: []const u8, line: u32, col: u32) void {
    if (g_lsp_conn_id < 0) return;

    var uri_buf: [600]u8 = undefined;
    const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{file_path}) catch return;

    _ = lsp.getClient().requestDefinition(g_lsp_conn_id, uri, line, col) catch |e| logger.warn("Operation failed: {}", .{e});
}

/// Poll LSP for messages
fn lspPoll() void {
    lsp.getClient().poll();
}

/// Get completions from LSP
fn lspGetCompletions() []const lsp.CompletionItem {
    return lsp.getClient().getCompletions();
}

/// Get diagnostics from LSP
fn lspGetDiagnostics() []const lsp.Diagnostic {
    return lsp.getClient().getDiagnostics();
}

/// Check if LSP is connected
fn lspIsConnected() bool {
    return g_lsp_conn_id >= 0;
}

/// Stop LSP connection
fn lspStop() void {
    if (g_lsp_conn_id >= 0) {
        lsp.getClient().stopServer(g_lsp_conn_id);
        g_lsp_conn_id = -1;
    }
}

fn openFileDialog(
    buffer: *GapBuffer,
    tab_names: *[16][64]u8,
    tab_name_lens: *[16]usize,
    tab_paths: *[16][512]u8,
    tab_path_lens: *[16]usize,
    tab_modified: *[16]bool,
    tab_count: *usize,
    active_tab: *usize,
    tab_scroll_x: *[16]i32,
    tab_scroll_y: *[16]i32,
    scroll_x: *i32,
    scroll_y: *i32,
    selection: *SelectionState,
    tab_original_content: *[16][64 * 1024]u8,
    tab_original_lens: *[16]usize,
    undo_count: *usize,
    redo_count: *usize,
    allocator: std.mem.Allocator,
) void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "zenity", "--file-selection", "--title=Open File" },
    }) catch return;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        var len = result.stdout.len;
        while (len > 0 and (result.stdout[len - 1] == '\n' or result.stdout[len - 1] == '\r')) {
            len -= 1;
        }
        if (len > 0 and len < 512 and tab_count.* < 16) {
            // Check if already open этот файл
            for (0..tab_count.*) |check_idx| {
                if (tab_path_lens[check_idx] == len) {
                    var same = true;
                    for (0..len) |char_idx| {
                        if (tab_paths[check_idx][char_idx] != result.stdout[char_idx]) {
                            same = false;
                            break;
                        }
                    }
                    if (same) {
                        // Файл уже открыт - переключаемся на него
                        tab_scroll_x[active_tab.*] = scroll_x.*;
                        tab_scroll_y[active_tab.*] = scroll_y.*;
                        active_tab.* = check_idx;
                        buffer.clear();
                        loadFile(tab_paths[check_idx][0..len], buffer);
                        scroll_x.* = tab_scroll_x[check_idx];
                        scroll_y.* = tab_scroll_y[check_idx];
                        selection.clear();
                        return;
                    }
                }
            }

            // Save скролл текущей вкладки
            tab_scroll_x[active_tab.*] = scroll_x.*;
            tab_scroll_y[active_tab.*] = scroll_y.*;

            // Create new tab
            const new_idx = tab_count.*;
            @memcpy(tab_paths[new_idx][0..len], result.stdout[0..len]);
            tab_path_lens[new_idx] = len;

            // Extract имя файла из пути
            var name_start: usize = 0;
            for (0..len) |path_i| {
                if (result.stdout[path_i] == '/') {
                    name_start = path_i + 1;
                }
            }
            const name_len = @min(len - name_start, 63);
            @memcpy(tab_names[new_idx][0..name_len], result.stdout[name_start .. name_start + name_len]);
            tab_name_lens[new_idx] = name_len;
            tab_modified[new_idx] = false;
            tab_scroll_x[new_idx] = 0;
            tab_scroll_y[new_idx] = 0;

            active_tab.* = new_idx;
            tab_count.* += 1;

            // Load файл
            buffer.clear();
            loadFile(tab_paths[new_idx][0..len], buffer);
            scroll_x.* = 0;
            scroll_y.* = 0;
            selection.clear();

            // Save original content for modification tracking
            const content_len = @min(buffer.len(), 64 * 1024);
            if (buffer.getText(allocator)) |txt| {
                @memcpy(tab_original_content[new_idx][0..content_len], txt[0..content_len]);
                tab_original_lens[new_idx] = content_len;
                allocator.free(txt);
            } else |_| {
                tab_original_lens[new_idx] = 0;
            }

            // Clear undo/redo for new file
            undo_count.* = 0;
            redo_count.* = 0;
        }
    }
}

fn saveFileDialogTab(
    buffer: *const GapBuffer,
    tab_paths: *[16][512]u8,
    tab_path_lens: *[16]usize,
    tab_names: *[16][64]u8,
    tab_name_lens: *[16]usize,
    tab_modified: *[16]bool,
    active_tab: usize,
) void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "zenity", "--file-selection", "--save", "--confirm-overwrite", "--title=Save As" },
    }) catch return;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        var len = result.stdout.len;
        while (len > 0 and (result.stdout[len - 1] == '\n' or result.stdout[len - 1] == '\r')) {
            len -= 1;
        }
        if (len > 0 and len < 512) {
            @memcpy(tab_paths[active_tab][0..len], result.stdout[0..len]);
            tab_path_lens[active_tab] = len;

            // Extract имя файла из пути
            var name_start: usize = 0;
            for (0..len) |path_i| {
                if (result.stdout[path_i] == '/') {
                    name_start = path_i + 1;
                }
            }
            const name_len = @min(len - name_start, 63);
            @memcpy(tab_names[active_tab][0..name_len], result.stdout[name_start .. name_start + name_len]);
            tab_name_lens[active_tab] = name_len;

            saveFile(tab_paths[active_tab][0..len], buffer);
            tab_modified[active_tab] = false;
        }
    }
}
