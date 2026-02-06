const std = @import("std");
const logger = @import("logger.zig");

/// Application-wide error types
pub const MoonError = error{
    // File operations
    FileNotFound,
    FileReadError,
    FileWriteError,
    FileAccessDenied,
    PathTooLong,
    DirectoryNotFound,

    // Buffer operations
    BufferOverflow,
    InvalidPosition,
    AllocationFailed,

    // Plugin system
    PluginLoadError,
    PluginNotFound,
    PluginTimeout,
    TooManyPlugins,

    // WASM runtime
    WasmEngineError,
    WasmModuleError,
    WasmInstanceError,
    WasmTrapOccurred,

    // LSP
    LspConnectionError,
    LspTimeout,
    LspProtocolError,

    // General
    InvalidArgument,
    NotImplemented,
    Unknown,
};

/// Error context for better debugging
pub const ErrorContext = struct {
    err: anyerror,
    context: []const u8,
    file: []const u8 = "",
    line: u32 = 0,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.file.len > 0) {
            try writer.print("[{s}:{d}] [{s}] {}", .{ self.file, self.line, self.context, self.err });
        } else {
            try writer.print("[{s}] {}", .{ self.context, self.err });
        }
    }
};

/// Log an error with context
pub fn handle(err: anyerror, context: []const u8) void {
    logger.err("[{s}] Error: {}", .{ context, err });
}

/// Log an error with source location
pub fn handleWithLocation(
    err: anyerror,
    context: []const u8,
    src: std.builtin.SourceLocation,
) void {
    logger.err("[{s}:{d}] [{s}] Error: {}", .{
        src.file,
        src.line,
        context,
        err,
    });
}

/// Macro-like helper for getting source location
pub inline fn here() std.builtin.SourceLocation {
    return @src();
}

/// Retry configuration
pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    backoff_multiplier: f32 = 2.0,
};

/// Execute operation with retry and exponential backoff
pub fn withRetry(
    comptime T: type,
    operation: anytype,
    config: RetryConfig,
    context: []const u8,
) !T {
    var attempt: u32 = 0;
    var delay_ms: u64 = config.initial_delay_ms;

    while (attempt < config.max_attempts) : (attempt += 1) {
        if (operation()) |result| {
            if (attempt > 0) {
                logger.info("[{s}] Succeeded after {d} attempts", .{ context, attempt + 1 });
            }
            return result;
        } else |err| {
            logger.warn("[{s}] Attempt {d}/{d} failed: {}", .{
                context,
                attempt + 1,
                config.max_attempts,
                err,
            });

            if (attempt + 1 < config.max_attempts) {
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                delay_ms = @min(
                    @as(u64, @intFromFloat(@as(f32, @floatFromInt(delay_ms)) * config.backoff_multiplier)),
                    config.max_delay_ms,
                );
            } else {
                logger.err("[{s}] All {d} attempts failed", .{ context, config.max_attempts });
                return err;
            }
        }
    }

    return error.Unknown;
}

/// Result type for operations that can fail with context
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ErrorContext,

        const Self = @This();

        pub fn unwrap(self: Self) !T {
            return switch (self) {
                .ok => |v| v,
                .err => |e| e.err,
            };
        }

        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |v| v,
                .err => default,
            };
        }

        pub fn isOk(self: Self) bool {
            return self == .ok;
        }

        pub fn isErr(self: Self) bool {
            return self == .err;
        }
    };
}

/// Convert any error to MoonError
pub fn toMoonError(err: anyerror) MoonError {
    return switch (err) {
        error.FileNotFound => MoonError.FileNotFound,
        error.AccessDenied => MoonError.FileAccessDenied,
        error.OutOfMemory => MoonError.AllocationFailed,
        else => MoonError.Unknown,
    };
}

/// Get human-readable error message
pub fn getMessage(err: MoonError) []const u8 {
    return switch (err) {
        error.FileNotFound => "File not found",
        error.FileReadError => "Failed to read file",
        error.FileWriteError => "Failed to write file",
        error.FileAccessDenied => "Access denied",
        error.PathTooLong => "Path exceeds maximum length",
        error.DirectoryNotFound => "Directory not found",
        error.BufferOverflow => "Buffer overflow",
        error.InvalidPosition => "Invalid cursor position",
        error.AllocationFailed => "Memory allocation failed",
        error.PluginLoadError => "Failed to load plugin",
        error.PluginNotFound => "Plugin not found",
        error.PluginTimeout => "Plugin execution timed out",
        error.TooManyPlugins => "Maximum plugin limit reached",
        error.WasmEngineError => "WASM engine error",
        error.WasmModuleError => "WASM module error",
        error.WasmInstanceError => "WASM instance error",
        error.WasmTrapOccurred => "WASM trap occurred",
        error.LspConnectionError => "LSP connection failed",
        error.LspTimeout => "LSP request timed out",
        error.LspProtocolError => "LSP protocol error",
        error.InvalidArgument => "Invalid argument",
        error.NotImplemented => "Not implemented",
        error.Unknown => "Unknown error",
    };
}

// ============================================================================
// Tests
// ============================================================================

test "handle logs error" {
    // Just verify it doesn't crash
    handle(error.FileNotFound, "test");
}

test "getMessage returns correct strings" {
    try std.testing.expectEqualStrings("File not found", getMessage(MoonError.FileNotFound));
    try std.testing.expectEqualStrings("Memory allocation failed", getMessage(MoonError.AllocationFailed));
}

test "toMoonError converts standard errors" {
    try std.testing.expectEqual(MoonError.FileNotFound, toMoonError(error.FileNotFound));
    try std.testing.expectEqual(MoonError.FileAccessDenied, toMoonError(error.AccessDenied));
    try std.testing.expectEqual(MoonError.AllocationFailed, toMoonError(error.OutOfMemory));
}
