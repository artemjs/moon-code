const std = @import("std");

/// Simple hash function for cache invalidation
pub fn simpleHash(data: []const u8) u32 {
    var hash: u32 = 5381;
    for (data) |byte| {
        hash = ((hash << 5) +% hash) +% byte;
    }
    return hash;
}

/// Change type for redraw optimization
pub const DirtyType = enum {
    none, // Nothing changed
    cursor_only, // Only cursor moved
    line_range, // Line range changed
    full, // Full redraw needed
};

/// Cursor position cache
pub const CursorCache = struct {
    const Self = @This();

    pos: usize = 0, // Cursor position for which cache is valid
    line: usize = 0,
    col: usize = 0,
    valid: bool = false,

    pub fn init() Self {
        return Self{};
    }

    /// Invalidate the cache
    pub fn invalidate(self: *Self) void {
        self.valid = false;
    }

    /// Update cache with new cursor position
    pub fn update(self: *Self, pos: usize, line: usize, col: usize) void {
        self.pos = pos;
        self.line = line;
        self.col = col;
        self.valid = true;
    }

    /// Check if cache is valid for given position
    pub fn isValidFor(self: *const Self, pos: usize) bool {
        return self.valid and self.pos == pos;
    }

    /// Get cached line/col if valid
    pub fn get(self: *const Self, pos: usize) ?struct { line: usize, col: usize } {
        if (self.isValidFor(pos)) {
            return .{ .line = self.line, .col = self.col };
        }
        return null;
    }
};

/// Line index for O(1) access to line offset
pub const LineIndex = struct {
    const Self = @This();
    pub const MAX_LINES = 100000; // Support up to 100k lines

    offsets: [MAX_LINES]usize = [_]usize{0} ** MAX_LINES,
    count: usize = 0,
    valid: bool = false,
    buf_len: usize = 0, // Buffer length when index was built

    pub fn init() Self {
        return Self{};
    }

    /// Invalidate the index
    pub fn invalidate(self: *Self) void {
        self.valid = false;
    }

    /// Check if index is valid for given buffer length
    pub fn isValidFor(self: *const Self, current_buf_len: usize) bool {
        return self.valid and self.buf_len == current_buf_len;
    }

    /// Get line offset by line number
    pub fn getLineOffset(self: *const Self, line_num: usize) ?usize {
        if (!self.valid or line_num >= self.count) return null;
        return self.offsets[line_num];
    }

    /// Build index from text
    pub fn build(self: *Self, text: []const u8) void {
        self.count = 1;
        self.offsets[0] = 0;

        for (text, 0..) |c, i| {
            if (c == '\n' and self.count < MAX_LINES) {
                self.offsets[self.count] = i + 1;
                self.count += 1;
            }
        }

        self.buf_len = text.len;
        self.valid = true;
    }

    /// Get total line count
    pub fn lineCount(self: *const Self) usize {
        return if (self.valid) self.count else 0;
    }
};

/// Dirty region tracking for optimized rendering
pub const DirtyTracking = struct {
    const Self = @This();

    dirty_type: DirtyType = .full,
    line_start: usize = 0,
    line_end: usize = 0,
    prev_scroll_y: i32 = 0,
    prev_cursor_line: usize = 0,
    prev_selection_start: ?usize = null,
    prev_selection_end: ?usize = null,

    pub fn init() Self {
        return Self{};
    }

    /// Mark entire buffer as dirty
    pub fn markFull(self: *Self) void {
        self.dirty_type = .full;
    }

    /// Mark cursor movement only
    pub fn markCursorOnly(self: *Self) void {
        if (self.dirty_type == .none) {
            self.dirty_type = .cursor_only;
        }
    }

    /// Mark a line range as dirty
    pub fn markLineRange(self: *Self, start: usize, end: usize) void {
        switch (self.dirty_type) {
            .none, .cursor_only => {
                self.dirty_type = .line_range;
                self.line_start = start;
                self.line_end = end;
            },
            .line_range => {
                // Expand existing range
                self.line_start = @min(self.line_start, start);
                self.line_end = @max(self.line_end, end);
            },
            .full => {}, // Already full redraw
        }
    }

    /// Clear dirty state after rendering
    pub fn clear(self: *Self) void {
        self.dirty_type = .none;
    }

    /// Check if full redraw is needed
    pub fn needsFullRedraw(self: *const Self) bool {
        return self.dirty_type == .full;
    }

    /// Update scroll tracking
    pub fn updateScroll(self: *Self, scroll_y: i32) void {
        if (scroll_y != self.prev_scroll_y) {
            self.markFull();
            self.prev_scroll_y = scroll_y;
        }
    }

    /// Update cursor tracking
    pub fn updateCursor(self: *Self, cursor_line: usize) void {
        if (cursor_line != self.prev_cursor_line) {
            self.markLineRange(
                @min(self.prev_cursor_line, cursor_line),
                @max(self.prev_cursor_line, cursor_line),
            );
            self.prev_cursor_line = cursor_line;
        }
    }

    /// Update selection tracking
    pub fn updateSelection(self: *Self, start: ?usize, end: ?usize) void {
        if (start != self.prev_selection_start or end != self.prev_selection_end) {
            self.markFull(); // Selection change requires full redraw
            self.prev_selection_start = start;
            self.prev_selection_end = end;
        }
    }
};

/// Token for syntax highlighting (basic representation)
pub const Token = struct {
    start: usize = 0,
    length: usize = 0,
    token_type: u8 = 0,
};

/// Cached tokens for a single line
pub const CachedLineTokens = struct {
    const Self = @This();
    pub const MAX_TOKENS = 128;

    tokens: [MAX_TOKENS]Token = undefined,
    count: u16 = 0,
    line_hash: u32 = 0, // Line content hash for invalidation
    in_multiline_comment: bool = false, // State at line start

    pub fn init() Self {
        return Self{};
    }

    /// Invalidate this line's cache
    pub fn invalidate(self: *Self) void {
        self.count = 0;
        self.line_hash = 0;
    }

    /// Check if cache is valid for given line content
    pub fn isValidFor(self: *const Self, line_content: []const u8) bool {
        return self.count > 0 and self.line_hash == simpleHash(line_content);
    }

    /// Get tokens slice
    pub fn getTokens(self: *const Self) []const Token {
        return self.tokens[0..self.count];
    }
};

/// Token cache for all visible lines
pub const TokenCache = struct {
    const Self = @This();
    pub const MAX_CACHED_LINES = 10000;

    lines: [MAX_CACHED_LINES]CachedLineTokens = [_]CachedLineTokens{CachedLineTokens.init()} ** MAX_CACHED_LINES,
    valid: bool = false,
    file_hash: u64 = 0, // For invalidation when file changes

    pub fn init() Self {
        return Self{};
    }

    /// Invalidate entire cache
    pub fn invalidate(self: *Self) void {
        self.valid = false;
        self.file_hash = 0;
    }

    /// Invalidate a specific line
    pub fn invalidateLine(self: *Self, line_num: usize) void {
        if (line_num < MAX_CACHED_LINES) {
            self.lines[line_num].invalidate();
        }
    }

    /// Invalidate a range of lines
    pub fn invalidateRange(self: *Self, start: usize, end: usize) void {
        const s = @min(start, MAX_CACHED_LINES);
        const e = @min(end, MAX_CACHED_LINES);
        for (self.lines[s..e]) |*line| {
            line.invalidate();
        }
    }

    /// Get cached tokens for a line
    pub fn getLine(self: *Self, line_num: usize) ?*CachedLineTokens {
        if (line_num >= MAX_CACHED_LINES) return null;
        return &self.lines[line_num];
    }
};

/// Combined buffer cache state
/// Extracted from main.zig lines 100-156
pub const BufferCache = struct {
    const Self = @This();

    // Line cache
    cached_line: usize = 0,
    cached_offset: usize = 0,
    cached_buf_len: usize = 0,
    cached_line_count: usize = 1,
    cached_max_line_len: usize = 0,

    // Sub-caches
    cursor: CursorCache = CursorCache.init(),
    line_index: LineIndex = LineIndex.init(),
    dirty: DirtyTracking = DirtyTracking.init(),
    tokens: TokenCache = TokenCache.init(),

    // Frame timing
    last_frame_time: i64 = 0,

    pub fn init() Self {
        return Self{};
    }

    /// Invalidate all caches
    pub fn invalidateAll(self: *Self) void {
        self.cursor.invalidate();
        self.line_index.invalidate();
        self.tokens.invalidate();
        self.dirty.markFull();
    }

    /// Invalidate caches after text edit
    pub fn onTextEdit(self: *Self, edit_line: usize) void {
        self.cursor.invalidate();
        self.line_index.invalidate();
        self.tokens.invalidateRange(edit_line, TokenCache.MAX_CACHED_LINES);
        self.dirty.markLineRange(edit_line, edit_line);
    }

    /// Update buffer metadata
    pub fn updateMetadata(self: *Self, buf_len: usize, line_count: usize, max_line_len: usize) void {
        self.cached_buf_len = buf_len;
        self.cached_line_count = line_count;
        self.cached_max_line_len = max_line_len;
    }

    /// Check if line index needs rebuild
    pub fn needsLineIndexRebuild(self: *const Self, current_buf_len: usize) bool {
        return !self.line_index.isValidFor(current_buf_len);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "simpleHash produces consistent values" {
    const hash1 = simpleHash("hello");
    const hash2 = simpleHash("hello");
    const hash3 = simpleHash("world");

    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}

test "CursorCache basic operations" {
    var cache = CursorCache.init();

    try std.testing.expectEqual(false, cache.valid);
    try std.testing.expect(cache.get(0) == null);

    cache.update(100, 5, 10);
    try std.testing.expectEqual(true, cache.valid);

    const result = cache.get(100);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 5), result.?.line);
    try std.testing.expectEqual(@as(usize, 10), result.?.col);

    // Invalid for different position
    try std.testing.expect(cache.get(50) == null);

    cache.invalidate();
    try std.testing.expectEqual(false, cache.valid);
}

test "LineIndex build and query" {
    var index = LineIndex.init();

    index.build("line1\nline2\nline3");

    try std.testing.expectEqual(true, index.valid);
    try std.testing.expectEqual(@as(usize, 3), index.count);
    try std.testing.expectEqual(@as(?usize, 0), index.getLineOffset(0));
    try std.testing.expectEqual(@as(?usize, 6), index.getLineOffset(1));
    try std.testing.expectEqual(@as(?usize, 12), index.getLineOffset(2));
    try std.testing.expect(index.getLineOffset(3) == null);
}

test "DirtyTracking operations" {
    var dirty = DirtyTracking.init();

    try std.testing.expectEqual(DirtyType.full, dirty.dirty_type);

    dirty.clear();
    try std.testing.expectEqual(DirtyType.none, dirty.dirty_type);

    dirty.markCursorOnly();
    try std.testing.expectEqual(DirtyType.cursor_only, dirty.dirty_type);

    dirty.clear();
    dirty.markLineRange(5, 10);
    try std.testing.expectEqual(DirtyType.line_range, dirty.dirty_type);
    try std.testing.expectEqual(@as(usize, 5), dirty.line_start);
    try std.testing.expectEqual(@as(usize, 10), dirty.line_end);

    // Expand range
    dirty.markLineRange(3, 15);
    try std.testing.expectEqual(@as(usize, 3), dirty.line_start);
    try std.testing.expectEqual(@as(usize, 15), dirty.line_end);
}

test "CachedLineTokens validation" {
    var cached = CachedLineTokens.init();

    const line = "const x = 42;";
    try std.testing.expectEqual(false, cached.isValidFor(line));

    cached.line_hash = simpleHash(line);
    cached.count = 1;
    try std.testing.expectEqual(true, cached.isValidFor(line));
    try std.testing.expectEqual(false, cached.isValidFor("different line"));

    cached.invalidate();
    try std.testing.expectEqual(false, cached.isValidFor(line));
}

test "TokenCache line operations" {
    // Use smaller cache for testing to avoid stack overflow
    var cache_line = CachedLineTokens.init();

    try std.testing.expectEqual(@as(u16, 0), cache_line.count);

    cache_line.line_hash = 12345;
    cache_line.count = 5;

    cache_line.invalidate();
    try std.testing.expectEqual(@as(u16, 0), cache_line.count);
    try std.testing.expectEqual(@as(u32, 0), cache_line.line_hash);
}

test "BufferCache cursor and dirty tracking" {
    // Test only the smaller components to avoid stack overflow
    var cursor = CursorCache.init();
    var dirty = DirtyTracking.init();

    cursor.update(100, 5, 10);
    try std.testing.expectEqual(true, cursor.valid);

    dirty.clear();
    dirty.markLineRange(5, 10);
    try std.testing.expectEqual(DirtyType.line_range, dirty.dirty_type);

    cursor.invalidate();
    try std.testing.expectEqual(false, cursor.valid);
}
