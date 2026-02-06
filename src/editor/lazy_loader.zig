const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;

/// Lazy file loader - loads first chunk immediately, then continues in background
pub const LazyLoader = struct {
    const Self = @This();

    const INITIAL_BYTES = 64 * 1024; // 64KB initial load
    const CHUNK_BYTES = 16 * 1024; // 16KB per chunk

    /// Loading state
    pub const State = enum {
        idle,
        partial,
        complete,
    };

    file: ?std.fs.File,
    path_buf: [512]u8,
    path_len: usize,
    state: State,
    bytes_loaded: usize,
    total_size: usize,

    pub fn init() Self {
        return Self{
            .file = null,
            .path_buf = undefined,
            .path_len = 0,
            .state = .idle,
            .bytes_loaded = 0,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
    }

    /// Start loading a file - loads first chunk
    pub fn startLoad(self: *Self, path: []const u8, buffer: *GapBuffer) bool {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }

        const file = std.fs.cwd().openFile(path, .{}) catch return false;

        const stat = file.stat() catch {
            file.close();
            return false;
        };
        self.total_size = stat.size;

        const len = @min(path.len, self.path_buf.len);
        @memcpy(self.path_buf[0..len], path[0..len]);
        self.path_len = len;

        buffer.clear();

        // Read initial chunk
        var read_buf: [INITIAL_BYTES]u8 = undefined;
        const bytes_read = file.read(&read_buf) catch {
            file.close();
            self.state = .complete;
            return false;
        };

        if (bytes_read > 0) {
            buffer.appendBulk(read_buf[0..bytes_read]) catch {
                file.close();
                self.state = .complete;
                return false;
            };
        }

        buffer.moveCursor(0);
        self.bytes_loaded = bytes_read;

        if (bytes_read >= self.total_size or bytes_read == 0) {
            file.close();
            self.file = null;
            self.state = .complete;
            return false;
        }

        self.file = file;
        self.state = .partial;
        return true;
    }

    /// Continue loading - returns true if more to load
    pub fn continueLoad(self: *Self, buffer: *GapBuffer) bool {
        if (self.state != .partial) return false;

        const file = self.file orelse {
            self.state = .complete;
            return false;
        };

        var read_buf: [CHUNK_BYTES]u8 = undefined;
        const bytes_read = file.read(&read_buf) catch {
            self.finishLoad();
            return false;
        };

        if (bytes_read == 0) {
            self.finishLoad();
            return false;
        }

        buffer.appendBulk(read_buf[0..bytes_read]) catch {
            self.finishLoad();
            return false;
        };

        self.bytes_loaded += bytes_read;

        if (self.bytes_loaded >= self.total_size) {
            self.finishLoad();
            return false;
        }

        return true;
    }

    fn finishLoad(self: *Self) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
        self.state = .complete;
    }

    pub fn isComplete(self: *const Self) bool {
        return self.state == .complete;
    }

    pub fn isPartial(self: *const Self) bool {
        return self.state == .partial;
    }

    pub fn getProgress(self: *const Self) f32 {
        if (self.total_size == 0) return 1.0;
        return @as(f32, @floatFromInt(self.bytes_loaded)) / @as(f32, @floatFromInt(self.total_size));
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "LazyLoader.init creates idle loader" {
    var loader = LazyLoader.init();
    defer loader.deinit();

    try std.testing.expectEqual(LazyLoader.State.idle, loader.state);
    try std.testing.expectEqual(@as(usize, 0), loader.bytes_loaded);
    try std.testing.expectEqual(@as(usize, 0), loader.total_size);
    try std.testing.expect(loader.file == null);
}

test "LazyLoader.isComplete returns correct state" {
    var loader = LazyLoader.init();

    try std.testing.expectEqual(false, loader.isComplete());

    loader.state = .complete;
    try std.testing.expectEqual(true, loader.isComplete());
}

test "LazyLoader.isPartial returns correct state" {
    var loader = LazyLoader.init();

    try std.testing.expectEqual(false, loader.isPartial());

    loader.state = .partial;
    try std.testing.expectEqual(true, loader.isPartial());
}

test "LazyLoader.getProgress returns 1.0 for zero total_size" {
    var loader = LazyLoader.init();
    loader.total_size = 0;
    loader.bytes_loaded = 0;

    try std.testing.expectEqual(@as(f32, 1.0), loader.getProgress());
}

test "LazyLoader.getProgress calculates correctly" {
    var loader = LazyLoader.init();
    loader.total_size = 100;
    loader.bytes_loaded = 50;

    try std.testing.expectEqual(@as(f32, 0.5), loader.getProgress());

    loader.bytes_loaded = 100;
    try std.testing.expectEqual(@as(f32, 1.0), loader.getProgress());
}

test "LazyLoader.deinit is safe to call multiple times" {
    var loader = LazyLoader.init();

    // Multiple deinit calls should not crash
    loader.deinit();
    loader.deinit();
    loader.deinit();

    try std.testing.expect(loader.file == null);
}

test "LazyLoader.continueLoad returns false when idle" {
    var loader = LazyLoader.init();
    var buffer = try GapBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    // Should return false when in idle state
    try std.testing.expectEqual(false, loader.continueLoad(&buffer));
}

test "LazyLoader.continueLoad returns false when complete" {
    var loader = LazyLoader.init();
    loader.state = .complete;
    var buffer = try GapBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    // Should return false when already complete
    try std.testing.expectEqual(false, loader.continueLoad(&buffer));
}

test "LazyLoader constants are correct" {
    // Verify constants match expected values
    try std.testing.expectEqual(@as(usize, 64 * 1024), LazyLoader.INITIAL_BYTES);
    try std.testing.expectEqual(@as(usize, 16 * 1024), LazyLoader.CHUNK_BYTES);
}
