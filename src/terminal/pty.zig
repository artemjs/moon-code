// PTY Terminal module for Moon-code
// Provides pseudo-terminal support for running programs interactively

const std = @import("std");
const posix = std.posix;

pub const Terminal = struct {
    master_fd: ?posix.fd_t = null,
    child_pid: ?posix.pid_t = null,
    output_buffer: [65536]u8 = undefined,
    output_len: usize = 0,
    running: bool = false,
    exit_code: ?u32 = null,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    /// Start a command in PTY
    pub fn spawn(self: *Self, cmd: []const u8, args: []const []const u8, allocator: std.mem.Allocator) !void {
        _ = args;
        _ = allocator;

        // Use pipe-based approach for simplicity (real PTY needs forkpty from libc)
        // For now, run command and capture output non-interactively
        self.running = true;
        self.output_len = 0;
        self.exit_code = null;

        // Build shell command
        var shell_cmd: [2048]u8 = undefined;
        const shell_str = std.fmt.bufPrint(&shell_cmd, "{s} 2>&1", .{cmd}) catch return error.CommandTooLong;

        // Execute using Child.run (blocking for now)
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", shell_str },
        }) catch |err| {
            self.running = false;
            return err;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);

        // Copy output
        const output = if (result.stdout.len > 0) result.stdout else result.stderr;
        const copy_len = @min(output.len, self.output_buffer.len);
        @memcpy(self.output_buffer[0..copy_len], output[0..copy_len]);
        self.output_len = copy_len;

        self.exit_code = result.term.Exited;
        self.running = false;
    }

    /// Check if terminal is running
    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    /// Get output buffer
    pub fn getOutput(self: *const Self) []const u8 {
        return self.output_buffer[0..self.output_len];
    }

    /// Get exit code (null if still running)
    pub fn getExitCode(self: *const Self) ?u32 {
        return self.exit_code;
    }

    /// Kill running process
    pub fn kill(self: *Self) void {
        if (self.child_pid) |pid| {
            _ = posix.kill(pid, posix.SIG.TERM) catch {};
            self.child_pid = null;
        }
        self.running = false;
    }

    /// Clean up
    pub fn deinit(self: *Self) void {
        self.kill();
        if (self.master_fd) |fd| {
            posix.close(fd);
            self.master_fd = null;
        }
    }
};

/// Parse ANSI escape sequences and return color info
pub const AnsiParser = struct {
    pub const Color = struct {
        fg: u32 = 0xFFe8e8e8,
        bg: u32 = 0xFF1a1a1a,
        bold: bool = false,
    };

    /// Standard ANSI colors (normal)
    const ansi_colors = [_]u32{
        0xFF000000, // 0 black
        0xFFcd0000, // 1 red
        0xFF00cd00, // 2 green
        0xFFcdcd00, // 3 yellow
        0xFF0000ee, // 4 blue
        0xFFcd00cd, // 5 magenta
        0xFF00cdcd, // 6 cyan
        0xFFe5e5e5, // 7 white
    };

    /// Bright ANSI colors
    const ansi_bright = [_]u32{
        0xFF7f7f7f, // 8 bright black
        0xFFff0000, // 9 bright red
        0xFF00ff00, // 10 bright green
        0xFFffff00, // 11 bright yellow
        0xFF5c5cff, // 12 bright blue
        0xFFff00ff, // 13 bright magenta
        0xFF00ffff, // 14 bright cyan
        0xFFffffff, // 15 bright white
    };

    pub fn parseColor(code: u8, bright: bool) u32 {
        if (code < 8) {
            return if (bright) ansi_bright[code] else ansi_colors[code];
        }
        return 0xFFe8e8e8; // default
    }
};

/// Output line with color info
pub const OutputLine = struct {
    text: [256]u8 = undefined,
    len: usize = 0,
    line_type: u8 = 0, // 0=normal, 1=warning, 2=error
    fg_color: u32 = 0xFFe8e8e8,
};
