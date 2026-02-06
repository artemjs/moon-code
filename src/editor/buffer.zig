const std = @import("std");
const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
});

/// Piece Table - efficient data structure for text editing
/// Used in VS Code, Sublime Text and other editors
///
/// Advantages over Gap Buffer:
/// - Fast insertions/deletions O(log n) for search + O(1) for operation
/// - Efficient undo/redo (just piece manipulation)
/// - No data copying during editing
/// - Original file is not modified
pub const GapBuffer = struct {
    // Keep GapBuffer name for compatibility with the rest of the code

    allocator: std.mem.Allocator,

    // Original buffer (read-only, contents of loaded file)
    original: []const u8,
    original_is_mmap: bool, // true if original is memory-mapped

    // Add buffer (append-only, all added characters)
    add_buffer: std.ArrayList(u8),

    // Pieces table
    pieces: std.ArrayList(Piece),

    // Cursor position
    cursor_pos: usize,

    // Cache
    cached_len: usize,
    cached_line_count: usize,
    cached_max_line_len: usize,
    cache_valid: bool,

    // Cache for fast line access
    line_starts: std.ArrayList(usize), // Indices of each line start
    line_cache_valid: bool,

    // Materialized text cache for fast reading
    text_cache: []u8,
    text_cache_valid: bool,

    const Self = @This();

    const PieceSource = enum { original, add };

    const Piece = struct {
        source: PieceSource,
        start: usize, // Start in source buffer
        length: usize, // Piece length
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self = Self{
            .allocator = allocator,
            .original = &[_]u8{},
            .original_is_mmap = false,
            .add_buffer = .{},
            .pieces = .{},
            .cursor_pos = 0,
            .cached_len = 0,
            .cached_line_count = 1,
            .cached_max_line_len = 0,
            .cache_valid = true,
            .line_starts = .{},
            .line_cache_valid = true,
            .text_cache = &[_]u8{},
            .text_cache_valid = true,
        };
        try self.line_starts.append(allocator, 0); // First line starts at 0

        return self;
    }

    pub fn initWithText(allocator: std.mem.Allocator, text: []const u8) !Self {
        var self = try init(allocator);

        if (text.len > 0) {
            // Copy text to original
            const original_copy = try allocator.alloc(u8, text.len);
            @memcpy(original_copy, text);
            self.original = original_copy;

            // Create one piece for the entire text
            try self.pieces.append(allocator, .{
                .source = .original,
                .start = 0,
                .length = text.len,
            });

            // Count lines
            var line_count: usize = 1;
            var max_len: usize = 0;
            var current_len: usize = 0;

            self.line_starts.clearRetainingCapacity();
            try self.line_starts.append(allocator, 0);

            for (text, 0..) |ch, idx| {
                if (ch == '\n') {
                    line_count += 1;
                    if (current_len > max_len) max_len = current_len;
                    current_len = 0;
                    try self.line_starts.append(allocator, idx + 1);
                } else {
                    current_len += 1;
                }
            }
            if (current_len > max_len) max_len = current_len;

            self.cached_len = text.len;
            self.cached_line_count = line_count;
            self.cached_max_line_len = max_len;
            self.cache_valid = true;
            self.line_cache_valid = true;
            self.cursor_pos = text.len;

            // Text cache - just reference original
            self.text_cache = original_copy;
            self.text_cache_valid = true;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.original.len > 0) {
            if (self.original_is_mmap) {
                // Unmap memory-mapped region
                _ = c.munmap(@constCast(@ptrCast(self.original.ptr)), self.original.len);
            } else {
                self.allocator.free(@constCast(self.original));
            }
        }
        // Free text_cache only if it differs from original
        if (self.text_cache.len > 0 and self.text_cache.ptr != self.original.ptr) {
            self.allocator.free(self.text_cache);
        }
        self.add_buffer.deinit(self.allocator);
        self.pieces.deinit(self.allocator);
        self.line_starts.deinit(self.allocator);
    }

    /// Load file using memory mapping (instant for any file size)
    pub fn loadFileMmap(self: *Self, path: []const u8) bool {
        // Clear existing content
        self.clear();
        if (self.original.len > 0) {
            if (self.original_is_mmap) {
                _ = c.munmap(@constCast(@ptrCast(self.original.ptr)), self.original.len);
            } else {
                self.allocator.free(@constCast(self.original));
            }
            self.original = &[_]u8{};
            self.original_is_mmap = false;
        }

        // Null-terminate path for C functions
        var path_buf: [512]u8 = undefined;
        if (path.len >= path_buf.len) return false;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;

        // Open file
        const fd = c.open(&path_buf, c.O_RDONLY);
        if (fd < 0) return false;
        defer _ = c.close(fd);

        // Get file size
        var stat: c.struct_stat = undefined;
        if (c.fstat(fd, &stat) < 0) return false;
        const file_size: usize = @intCast(stat.st_size);
        if (file_size == 0) return true; // Empty file

        // Memory map the file
        const ptr = c.mmap(null, file_size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
        if (ptr == c.MAP_FAILED) return false;

        // Set as original buffer
        self.original = @as([*]const u8, @ptrCast(ptr))[0..file_size];
        self.original_is_mmap = true;

        // Create single piece for entire file
        self.pieces.append(self.allocator, .{
            .source = .original,
            .start = 0,
            .length = file_size,
        }) catch return false;

        // Build line index (scan for newlines)
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(self.allocator, 0) catch {};

        var line_count: usize = 1;
        for (self.original, 0..) |ch, i| {
            if (ch == '\n') {
                line_count += 1;
                self.line_starts.append(self.allocator, i + 1) catch {};
            }
        }

        self.cached_len = file_size;
        self.cached_line_count = line_count;
        self.cache_valid = true;
        self.line_cache_valid = true;
        self.cursor_pos = 0;

        // Text cache points to mmap'd region
        self.text_cache = @constCast(self.original);
        self.text_cache_valid = true;

        return true;
    }

    pub fn clear(self: *Self) void {
        self.pieces.clearRetainingCapacity();
        self.add_buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.cached_len = 0;
        self.cached_line_count = 1;
        self.cached_max_line_len = 0;
        self.cache_valid = true;
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(self.allocator, 0) catch {};
        self.line_cache_valid = true;
        self.invalidateTextCache();
    }

    fn invalidateTextCache(self: *Self) void {
        if (self.text_cache.len > 0 and self.text_cache.ptr != self.original.ptr) {
            self.allocator.free(self.text_cache);
            self.text_cache = &[_]u8{};
        }
        self.text_cache_valid = false;
    }

    fn ensureTextCache(self: *Self) void {
        if (self.text_cache_valid) return;

        const total_len = self.cached_len;
        if (total_len == 0) {
            self.text_cache = &[_]u8{};
            self.text_cache_valid = true;
            return;
        }

        // If only one piece from original - use it directly
        if (self.pieces.items.len == 1) {
            const piece = self.pieces.items[0];
            if (piece.source == .original and piece.start == 0 and piece.length == self.original.len) {
                self.text_cache = @constCast(self.original);
                self.text_cache_valid = true;
                return;
            }
        }

        // Otherwise create a new buffer
        const new_cache = self.allocator.alloc(u8, total_len) catch {
            return; // Failed to allocate memory
        };

        var pos: usize = 0;
        for (self.pieces.items) |piece| {
            const src = switch (piece.source) {
                .original => self.original[piece.start..][0..piece.length],
                .add => self.add_buffer.items[piece.start..][0..piece.length],
            };
            @memcpy(new_cache[pos..][0..piece.length], src);
            pos += piece.length;
        }

        self.text_cache = new_cache;
        self.text_cache_valid = true;
    }

    pub fn len(self: *const Self) usize {
        return self.cached_len;
    }

    pub fn cursor(self: *const Self) usize {
        return self.cursor_pos;
    }

    pub fn moveCursor(self: *Self, pos: usize) void {
        self.cursor_pos = @min(pos, self.len());
    }

    /// Insert character at cursor position
    pub fn insert(self: *Self, char: u8) !void {
        const add_start = self.add_buffer.items.len;
        try self.add_buffer.append(self.allocator, char);

        try self.insertPieceAt(self.cursor_pos, .{
            .source = .add,
            .start = add_start,
            .length = 1,
        });

        self.cursor_pos += 1;
        self.cached_len += 1;

        if (char == '\n') {
            self.cached_line_count += 1;
        }
        self.cache_valid = false;
        self.line_cache_valid = false;
        self.invalidateTextCache();
    }

    pub fn insertSlice(self: *Self, text: []const u8) !void {
        if (text.len == 0) return;

        const add_start = self.add_buffer.items.len;
        try self.add_buffer.appendSlice(self.allocator, text);

        try self.insertPieceAt(self.cursor_pos, .{
            .source = .add,
            .start = add_start,
            .length = text.len,
        });

        self.cursor_pos += text.len;
        self.cached_len += text.len;

        for (text) |ch| {
            if (ch == '\n') {
                self.cached_line_count += 1;
            }
        }
        self.cache_valid = false;
        self.line_cache_valid = false;
        self.invalidateTextCache();
    }

    /// Fast append for bulk loading - appends to end without piece splitting
    /// Also builds line_starts index incrementally
    pub fn appendBulk(self: *Self, text: []const u8) !void {
        if (text.len == 0) return;

        const base_offset = self.cached_len; // Current end position
        const add_start = self.add_buffer.items.len;
        try self.add_buffer.appendSlice(self.allocator, text);

        // Try to extend last piece if it's from add_buffer and contiguous
        if (self.pieces.items.len > 0) {
            const last = &self.pieces.items[self.pieces.items.len - 1];
            if (last.source == .add and last.start + last.length == add_start) {
                last.length += text.len;
            } else {
                try self.pieces.append(self.allocator, .{
                    .source = .add,
                    .start = add_start,
                    .length = text.len,
                });
            }
        } else {
            try self.pieces.append(self.allocator, .{
                .source = .add,
                .start = add_start,
                .length = text.len,
            });
        }

        // Count newlines and build line_starts incrementally
        var newlines: usize = 0;
        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                newlines += 1;
                // Add line start position (position after newline)
                self.line_starts.append(self.allocator, base_offset + i + 1) catch {};
            }
        }

        self.cached_len += text.len;
        self.cached_line_count += newlines;
        self.cache_valid = false;
        // DON'T invalidate text cache during bulk loading - it's expensive
        // self.invalidateTextCache();
        self.text_cache_valid = false;
    }

    pub fn deleteBack(self: *Self) void {
        if (self.cursor_pos == 0) return;

        const deleted_char = self.charAt(self.cursor_pos - 1);
        self.deleteAt(self.cursor_pos - 1, 1);
        self.cursor_pos -= 1;

        if (deleted_char == '\n') {
            if (self.cached_line_count > 1) self.cached_line_count -= 1;
        }
        self.cache_valid = false;
        self.line_cache_valid = false;
        self.invalidateTextCache();
    }

    pub fn deleteForward(self: *Self) void {
        if (self.cursor_pos >= self.len()) return;

        const deleted_char = self.charAt(self.cursor_pos);
        self.deleteAt(self.cursor_pos, 1);

        if (deleted_char == '\n') {
            if (self.cached_line_count > 1) self.cached_line_count -= 1;
        }
        self.cache_valid = false;
        self.line_cache_valid = false;
        self.invalidateTextCache();
    }

    pub fn charAt(self: *Self, index: usize) ?u8 {
        if (index >= self.cached_len) return null;

        // Use cache if available
        self.ensureTextCache();
        if (self.text_cache_valid and index < self.text_cache.len) {
            return self.text_cache[index];
        }

        // Fallback - iterate through pieces
        var pos: usize = 0;
        for (self.pieces.items) |piece| {
            if (index < pos + piece.length) {
                const offset = index - pos;
                return switch (piece.source) {
                    .original => self.original[piece.start + offset],
                    .add => self.add_buffer.items[piece.start + offset],
                };
            }
            pos += piece.length;
        }

        return null;
    }

    pub fn charAtConst(self: *const Self, index: usize) ?u8 {
        if (index >= self.cached_len) return null;

        // Use cache if available
        if (self.text_cache_valid and index < self.text_cache.len) {
            return self.text_cache[index];
        }

        // Fallback - iterate through pieces
        var pos: usize = 0;
        for (self.pieces.items) |piece| {
            if (index < pos + piece.length) {
                const offset = index - pos;
                return switch (piece.source) {
                    .original => self.original[piece.start + offset],
                    .add => self.add_buffer.items[piece.start + offset],
                };
            }
            pos += piece.length;
        }

        return null;
    }

    pub fn getText(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const total_len = self.len();
        if (total_len == 0) return try allocator.alloc(u8, 0);

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        for (self.pieces.items) |piece| {
            const src = switch (piece.source) {
                .original => self.original[piece.start..][0..piece.length],
                .add => self.add_buffer.items[piece.start..][0..piece.length],
            };
            @memcpy(result[pos..][0..piece.length], src);
            pos += piece.length;
        }

        return result;
    }

    /// Get pointer to cached text (read-only, fast)
    pub fn getTextCached(self: *Self) []const u8 {
        self.ensureTextCache();
        return self.text_cache;
    }

    pub fn getLine(self: *Self, line_num: usize) ?struct { start: usize, end: usize } {
        self.ensureTextCache();
        const text = self.text_cache;
        const total = text.len;

        var current_line: usize = 0;
        var line_start: usize = 0;

        var i: usize = 0;
        while (i <= total) : (i += 1) {
            const char = if (i < total) text[i] else null;

            if (char == '\n' or char == null) {
                if (current_line == line_num) {
                    return .{ .start = line_start, .end = i };
                }
                current_line += 1;
                line_start = i + 1;
            }
        }

        return null;
    }

    pub fn lineCount(self: *const Self) usize {
        return self.cached_line_count;
    }

    pub fn maxLineLength(self: *Self) usize {
        if (self.cache_valid) {
            return self.cached_max_line_len;
        }

        self.ensureTextCache();
        const text = self.text_cache;

        var max_len: usize = 0;
        var current_len: usize = 0;

        for (text) |ch| {
            if (ch == '\n') {
                if (current_len > max_len) max_len = current_len;
                current_len = 0;
            } else {
                current_len += 1;
            }
        }
        if (current_len > max_len) max_len = current_len;

        self.cached_max_line_len = max_len;
        self.cache_valid = true;
        return max_len;
    }

    pub fn maxLineLengthConst(self: *const Self) usize {
        if (self.cache_valid) {
            return self.cached_max_line_len;
        }

        // Without cache - slow path
        if (self.text_cache_valid) {
            var max_len: usize = 0;
            var current_len: usize = 0;
            for (self.text_cache) |ch| {
                if (ch == '\n') {
                    if (current_len > max_len) max_len = current_len;
                    current_len = 0;
                } else {
                    current_len += 1;
                }
            }
            if (current_len > max_len) max_len = current_len;
            return max_len;
        }

        return self.cached_max_line_len;
    }

    pub fn cursorPosition(self: *Self) struct { line: usize, col: usize } {
        self.ensureTextCache();
        const text = self.text_cache;

        var line: usize = 0;
        var col: usize = 0;

        var i: usize = 0;
        while (i < self.cursor_pos and i < text.len) : (i += 1) {
            if (text[i] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }

        return .{ .line = line, .col = col };
    }

    pub fn cursorPositionConst(self: *const Self) struct { line: usize, col: usize } {
        var line: usize = 0;
        var col: usize = 0;

        // Use cache if available
        if (self.text_cache_valid and self.text_cache.len > 0) {
            var i: usize = 0;
            while (i < self.cursor_pos and i < self.text_cache.len) : (i += 1) {
                if (self.text_cache[i] == '\n') {
                    line += 1;
                    col = 0;
                } else {
                    col += 1;
                }
            }
            return .{ .line = line, .col = col };
        }

        // Fallback - iterate through pieces
        var i: usize = 0;
        while (i < self.cursor_pos) : (i += 1) {
            if (self.charAtConst(i) == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }

        return .{ .line = line, .col = col };
    }

    pub fn getLineOffset(self: *Self, target_line: usize) ?usize {
        if (target_line == 0) return 0;

        self.ensureTextCache();
        const text = self.text_cache;

        var current_line: usize = 0;

        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                current_line += 1;
                if (current_line == target_line) {
                    return i + 1;
                }
            }
        }

        return null;
    }

    /// Fast O(1) line offset lookup using pre-built line_starts index
    /// Falls back to O(n) scan if line_starts is stale
    pub fn getLineOffsetFast(self: *const Self, target_line: usize) usize {
        if (target_line == 0) return 0;
        if (target_line < self.line_starts.items.len) {
            return self.line_starts.items[target_line];
        }
        // line_starts is stale (editing without reload) - scan text
        // This is O(n) but necessary for in-memory editing
        var current_line: usize = 0;
        var offset: usize = 0;
        const total = self.cached_len;

        while (offset < total and current_line < target_line) {
            // Get character at offset by scanning pieces
            var piece_offset: usize = 0;
            for (self.pieces.items) |piece| {
                if (offset < piece_offset + piece.length) {
                    const idx = piece.start + (offset - piece_offset);
                    const ch = switch (piece.source) {
                        .original => if (idx < self.original.len) self.original[idx] else 0,
                        .add => if (idx < self.add_buffer.items.len) self.add_buffer.items[idx] else 0,
                    };
                    if (ch == '\n') {
                        current_line += 1;
                        if (current_line == target_line) {
                            return offset + 1;
                        }
                    }
                    break;
                }
                piece_offset += piece.length;
            }
            offset += 1;
        }
        return offset;
    }

    /// Get total line count (O(1))
    pub fn getLineCount(self: *const Self) usize {
        return self.line_starts.items.len;
    }

    pub fn copyLine(self: *Self, start_offset: usize, dest: []u8) struct { line_len: usize, next_offset: usize } {
        self.ensureTextCache();
        const text = self.text_cache;
        const total = text.len;

        if (start_offset >= total) {
            return .{ .line_len = 0, .next_offset = total };
        }

        var line_len: usize = 0;
        var i: usize = start_offset;

        while (i < total and line_len < dest.len) {
            const ch = text[i];
            if (ch == '\n') {
                return .{ .line_len = line_len, .next_offset = i + 1 };
            }
            dest[line_len] = ch;
            line_len += 1;
            i += 1;
        }

        if (line_len >= dest.len) {
            while (i < total) {
                if (text[i] == '\n') {
                    i += 1;
                    break;
                }
                i += 1;
            }
        }

        return .{ .line_len = line_len, .next_offset = i };
    }

    pub fn copyLineConst(self: *const Self, start_offset: usize, dest: []u8) struct { line_len: usize, next_offset: usize } {
        // Use cache if available
        if (self.text_cache_valid) {
            const text = self.text_cache;
            const total = text.len;

            if (start_offset >= total) {
                return .{ .line_len = 0, .next_offset = total };
            }

            var line_len: usize = 0;
            var i: usize = start_offset;

            while (i < total and line_len < dest.len) {
                const ch = text[i];
                if (ch == '\n') {
                    return .{ .line_len = line_len, .next_offset = i + 1 };
                }
                dest[line_len] = ch;
                line_len += 1;
                i += 1;
            }

            if (line_len >= dest.len) {
                while (i < total) {
                    if (text[i] == '\n') {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
            }

            return .{ .line_len = line_len, .next_offset = i };
        }

        // Fallback - iterate through pieces
        const total = self.cached_len;

        if (start_offset >= total) {
            return .{ .line_len = 0, .next_offset = total };
        }

        var line_len: usize = 0;
        var i: usize = start_offset;

        while (i < total and line_len < dest.len) {
            const ch = self.charAtConst(i) orelse {
                i += 1;
                continue;
            };
            if (ch == '\n') {
                return .{ .line_len = line_len, .next_offset = i + 1 };
            }
            dest[line_len] = ch;
            line_len += 1;
            i += 1;
        }

        if (line_len >= dest.len) {
            while (i < total) {
                const ch = self.charAtConst(i) orelse break;
                i += 1;
                if (ch == '\n') break;
            }
        }

        return .{ .line_len = line_len, .next_offset = i };
    }

    // === Private helper methods ===

    fn insertPieceAt(self: *Self, pos: usize, new_piece: Piece) !void {
        if (self.pieces.items.len == 0) {
            try self.pieces.append(self.allocator, new_piece);
            return;
        }

        var current_pos: usize = 0;
        var piece_idx: usize = 0;

        // Find the piece that contains the insertion position
        while (piece_idx < self.pieces.items.len) {
            const piece = self.pieces.items[piece_idx];

            if (pos <= current_pos + piece.length) {
                const offset = pos - current_pos;

                if (offset == 0) {
                    // Insert before this piece
                    try self.pieces.insert(self.allocator, piece_idx, new_piece);
                } else if (offset == piece.length) {
                    // Insert after this piece
                    try self.pieces.insert(self.allocator, piece_idx + 1, new_piece);
                } else {
                    // Split piece into two and insert between them
                    const left = Piece{
                        .source = piece.source,
                        .start = piece.start,
                        .length = offset,
                    };
                    const right = Piece{
                        .source = piece.source,
                        .start = piece.start + offset,
                        .length = piece.length - offset,
                    };

                    // Replace current piece with left
                    self.pieces.items[piece_idx] = left;
                    // Insert new_piece and right
                    try self.pieces.insert(self.allocator, piece_idx + 1, new_piece);
                    try self.pieces.insert(self.allocator, piece_idx + 2, right);
                }
                return;
            }

            current_pos += piece.length;
            piece_idx += 1;
        }

        // If we reached the end, append to end
        try self.pieces.append(self.allocator, new_piece);
    }

    fn deleteAt(self: *Self, pos: usize, delete_len: usize) void {
        if (delete_len == 0) return;

        var remaining = delete_len;
        var current_pos: usize = 0;
        var piece_idx: usize = 0;

        while (piece_idx < self.pieces.items.len and remaining > 0) {
            const piece = &self.pieces.items[piece_idx];

            if (pos < current_pos + piece.length) {
                const offset = if (pos > current_pos) pos - current_pos else 0;
                const delete_in_piece = @min(remaining, piece.length - offset);

                if (offset == 0 and delete_in_piece == piece.length) {
                    // Delete entire piece
                    _ = self.pieces.orderedRemove(piece_idx);
                    self.cached_len -= delete_in_piece;
                    remaining -= delete_in_piece;
                    continue;
                } else if (offset == 0) {
                    // Delete start of piece
                    piece.start += delete_in_piece;
                    piece.length -= delete_in_piece;
                    self.cached_len -= delete_in_piece;
                    remaining -= delete_in_piece;
                } else if (offset + delete_in_piece == piece.length) {
                    // Delete end of piece
                    piece.length = offset;
                    self.cached_len -= delete_in_piece;
                    remaining -= delete_in_piece;
                } else {
                    // Delete middle - split into two pieces
                    const right = Piece{
                        .source = piece.source,
                        .start = piece.start + offset + delete_in_piece,
                        .length = piece.length - offset - delete_in_piece,
                    };
                    piece.length = offset;
                    self.pieces.insert(self.allocator, piece_idx + 1, right) catch {};
                    self.cached_len -= delete_in_piece;
                    remaining -= delete_in_piece;
                }
            }

            current_pos += self.pieces.items[piece_idx].length;
            piece_idx += 1;
        }
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "GapBuffer.init creates empty buffer" {
    var buf = try GapBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 0), buf.len());
    try std.testing.expectEqual(@as(usize, 1), buf.lineCount());
    try std.testing.expectEqual(@as(usize, 0), buf.cursor());
}

test "GapBuffer.initWithText creates buffer with content" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "hello");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 5), buf.len());
    try std.testing.expectEqual(@as(?u8, 'h'), buf.charAt(0));
    try std.testing.expectEqual(@as(?u8, 'o'), buf.charAt(4));
}

test "GapBuffer.insert adds character at cursor" {
    var buf = try GapBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.insert('a');
    try std.testing.expectEqual(@as(usize, 1), buf.len());
    try std.testing.expectEqual(@as(?u8, 'a'), buf.charAt(0));

    try buf.insert('b');
    try std.testing.expectEqual(@as(usize, 2), buf.len());
    try std.testing.expectEqual(@as(?u8, 'b'), buf.charAt(1));
}

test "GapBuffer.insertSlice adds text at cursor" {
    var buf = try GapBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.insertSlice("hello");
    try std.testing.expectEqual(@as(usize, 5), buf.len());

    try buf.insertSlice(" world");
    try std.testing.expectEqual(@as(usize, 11), buf.len());
}

test "GapBuffer.deleteBack removes character before cursor" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "abc");
    defer buf.deinit();

    buf.moveCursor(3); // Move to end
    buf.deleteBack();

    try std.testing.expectEqual(@as(usize, 2), buf.len());
    try std.testing.expectEqual(@as(?u8, 'a'), buf.charAt(0));
    try std.testing.expectEqual(@as(?u8, 'b'), buf.charAt(1));
}

test "GapBuffer.deleteForward removes character after cursor" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "abc");
    defer buf.deinit();

    buf.moveCursor(0);
    buf.deleteForward();

    try std.testing.expectEqual(@as(usize, 2), buf.len());
    try std.testing.expectEqual(@as(?u8, 'b'), buf.charAt(0));
    try std.testing.expectEqual(@as(?u8, 'c'), buf.charAt(1));
}

test "GapBuffer.charAt returns correct character" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "hello");
    defer buf.deinit();

    try std.testing.expectEqual(@as(?u8, 'h'), buf.charAt(0));
    try std.testing.expectEqual(@as(?u8, 'e'), buf.charAt(1));
    try std.testing.expectEqual(@as(?u8, 'l'), buf.charAt(2));
    try std.testing.expectEqual(@as(?u8, 'l'), buf.charAt(3));
    try std.testing.expectEqual(@as(?u8, 'o'), buf.charAt(4));
    try std.testing.expectEqual(@as(?u8, null), buf.charAt(5)); // Out of bounds
}

test "GapBuffer.moveCursor changes cursor position" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "hello");
    defer buf.deinit();

    // After initWithText, cursor is at end of text
    try std.testing.expectEqual(@as(usize, 5), buf.cursor());

    buf.moveCursor(0);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor());

    buf.moveCursor(3);
    try std.testing.expectEqual(@as(usize, 3), buf.cursor());

    buf.moveCursor(100); // Beyond end should clamp
    try std.testing.expectEqual(@as(usize, 5), buf.cursor());
}

test "GapBuffer.lineCount counts lines correctly" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "line1\nline2\nline3");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 3), buf.lineCount());
}

test "GapBuffer.getLine returns correct line range" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "abc\ndef\nghi");
    defer buf.deinit();

    const line0 = buf.getLine(0);
    try std.testing.expect(line0 != null);
    try std.testing.expectEqual(@as(usize, 0), line0.?.start);
    try std.testing.expectEqual(@as(usize, 3), line0.?.end);

    const line1 = buf.getLine(1);
    try std.testing.expect(line1 != null);
    try std.testing.expectEqual(@as(usize, 4), line1.?.start);
    try std.testing.expectEqual(@as(usize, 7), line1.?.end);
}

test "GapBuffer.clear resets buffer" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "hello world");
    defer buf.deinit();

    buf.clear();

    try std.testing.expectEqual(@as(usize, 0), buf.len());
    try std.testing.expectEqual(@as(usize, 1), buf.lineCount());
}

test "GapBuffer insert in middle of text" {
    var buf = try GapBuffer.initWithText(std.testing.allocator, "hllo");
    defer buf.deinit();

    buf.moveCursor(1);
    try buf.insert('e');

    try std.testing.expectEqual(@as(usize, 5), buf.len());
    try std.testing.expectEqual(@as(?u8, 'h'), buf.charAt(0));
    try std.testing.expectEqual(@as(?u8, 'e'), buf.charAt(1));
    try std.testing.expectEqual(@as(?u8, 'l'), buf.charAt(2));
}

test "GapBuffer multiple operations" {
    var buf = try GapBuffer.init(std.testing.allocator);
    defer buf.deinit();

    // Insert "hello"
    try buf.insertSlice("hello");
    try std.testing.expectEqual(@as(usize, 5), buf.len());

    // Move to position 5 and add " world"
    try buf.insertSlice(" world");
    try std.testing.expectEqual(@as(usize, 11), buf.len());

    // Delete last character
    buf.deleteBack();
    try std.testing.expectEqual(@as(usize, 10), buf.len());
}

test "GapBuffer empty buffer operations" {
    var buf = try GapBuffer.init(std.testing.allocator);
    defer buf.deinit();

    // Operations on empty buffer should not crash
    buf.deleteBack();
    buf.deleteForward();
    try std.testing.expectEqual(@as(?u8, null), buf.charAt(0));
    try std.testing.expectEqual(@as(usize, 0), buf.len());
}
