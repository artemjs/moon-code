const std = @import("std");
const builtin = @import("builtin");

/// Log levels in order of severity
pub const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Logger configuration
pub const LoggerConfig = struct {
    level: LogLevel = .info,
    file_path: ?[]const u8 = null,
    write_to_stderr: bool = true,
};

/// Main logger struct
pub const Logger = struct {
    file: ?std.fs.File = null,
    level: LogLevel = .info,
    write_to_stderr: bool = true,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    /// Initialize logger with configuration
    pub fn init(config: LoggerConfig) Self {
        var self = Self{
            .level = config.level,
            .write_to_stderr = config.write_to_stderr,
        };

        if (config.file_path) |path| {
            self.file = openLogFile(path);
        }

        return self;
    }

    /// Initialize with default log file in ~/.mncode/
    pub fn initDefault() Self {
        var path_buf: [512]u8 = undefined;
        const home = std.posix.getenv("HOME") orelse return Self{};

        const path_len = std.fmt.bufPrint(&path_buf, "{s}/.mncode/moon-code.log", .{home}) catch return Self{};
        const path = path_buf[0..path_len];

        // Ensure directory exists
        var dir_buf: [512]u8 = undefined;
        const dir_len = std.fmt.bufPrint(&dir_buf, "{s}/.mncode", .{home}) catch return Self{};
        std.fs.makeDirAbsolute(dir_buf[0..dir_len]) catch {};

        return Self.init(.{
            .level = .info,
            .file_path = path,
            .write_to_stderr = true,
        });
    }

    /// Deinitialize and close file handle
    pub fn deinit(self: *Self) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
    }

    /// Core logging function
    pub fn log(self: *Self, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Format timestamp
        const timestamp = std.time.timestamp();
        const secs = @mod(timestamp, 86400);
        const hours = @divTrunc(secs, 3600);
        const mins = @divTrunc(@mod(secs, 3600), 60);
        const seconds = @mod(secs, 60);

        // Build log line
        var buf: [4096]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buf, "[{d:0>2}:{d:0>2}:{d:0>2}] [{s}] ", .{
            hours,
            mins,
            seconds,
            level.toString(),
        }) catch return;
        const prefix_len = prefix.len;

        const msg = std.fmt.bufPrint(buf[prefix_len..], fmt, args) catch return;
        const total_len = prefix_len + msg.len;

        // Add newline if not present
        const line = if (total_len > 0 and buf[total_len - 1] != '\n') blk: {
            if (total_len < buf.len) {
                buf[total_len] = '\n';
                break :blk buf[0 .. total_len + 1];
            }
            break :blk buf[0..total_len];
        } else buf[0..total_len];

        // Write to file
        if (self.file) |f| {
            f.writeAll(line) catch {};
        }

        // Write to stderr
        if (self.write_to_stderr) {
            std.debug.print("{s}", .{line});
        }
    }

    fn openLogFile(path: []const u8) ?std.fs.File {
        return std.fs.createFileAbsolute(path, .{
            .truncate = false,
        }) catch |e| {
            std.debug.print("[Logger] Failed to open log file: {}\n", .{e});
            return null;
        };
    }
};

/// Global logger instance
pub var global: Logger = Logger{};

/// Initialize global logger
pub fn init(config: LoggerConfig) void {
    global = Logger.init(config);
}

/// Initialize global logger with defaults
pub fn initDefault() void {
    global = Logger.initDefault();
}

/// Deinitialize global logger
pub fn deinit() void {
    global.deinit();
}

/// Log debug message
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    global.log(.debug, fmt, args);
}

/// Log info message
pub fn info(comptime fmt: []const u8, args: anytype) void {
    global.log(.info, fmt, args);
}

/// Log warning message
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    global.log(.warn, fmt, args);
}

/// Log error message
pub fn err(comptime fmt: []const u8, args: anytype) void {
    global.log(.err, fmt, args);
}

// ============================================================================
// Tests
// ============================================================================

test "LogLevel ordering" {
    try std.testing.expect(@intFromEnum(LogLevel.debug) < @intFromEnum(LogLevel.info));
    try std.testing.expect(@intFromEnum(LogLevel.info) < @intFromEnum(LogLevel.warn));
    try std.testing.expect(@intFromEnum(LogLevel.warn) < @intFromEnum(LogLevel.err));
}

test "LogLevel toString" {
    try std.testing.expectEqualStrings("DEBUG", LogLevel.debug.toString());
    try std.testing.expectEqualStrings("INFO", LogLevel.info.toString());
    try std.testing.expectEqualStrings("WARN", LogLevel.warn.toString());
    try std.testing.expectEqualStrings("ERROR", LogLevel.err.toString());
}

test "Logger init with config" {
    var logger = Logger.init(.{
        .level = .warn,
        .write_to_stderr = false,
    });
    defer logger.deinit();

    try std.testing.expectEqual(LogLevel.warn, logger.level);
    try std.testing.expectEqual(false, logger.write_to_stderr);
}
