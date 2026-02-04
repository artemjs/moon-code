// Interactive Shell Terminal for Moon-code
// Spawns system shell and provides interactive I/O

const std = @import("std");
const posix = std.posix;

pub const Shell = struct {
    child: ?std.process.Child = null,
    stdout_thread: ?std.Thread = null,

    // Output buffer (ring buffer style)
    output: [65536]u8 = undefined,
    output_len: usize = 0,
    output_mutex: std.Thread.Mutex = .{},

    // Input buffer
    input_buf: [1024]u8 = undefined,
    input_len: usize = 0,

    // Scroll state
    scroll_offset: usize = 0, // Lines from bottom (0 = show latest)
    total_lines: usize = 0, // Total line count in buffer

    // Command history
    history: [64][256]u8 = undefined,
    history_lens: [64]usize = [_]usize{0} ** 64,
    history_count: usize = 0,
    history_pos: usize = 0, // Current position when browsing

    running: bool = false,
    allocator: std.mem.Allocator = std.heap.page_allocator,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    /// Start interactive shell
    pub fn start(self: *Self) !void {
        if (self.running) return;

        // Get user's shell
        const shell_path = std.posix.getenv("SHELL") orelse "/bin/bash";

        const argv = [_][]const u8{ shell_path, "-i" };
        self.child = std.process.Child.init(&argv, self.allocator);

        var child_ptr = &self.child.?;
        child_ptr.stdin_behavior = .Pipe;
        child_ptr.stdout_behavior = .Pipe;
        child_ptr.stderr_behavior = .Pipe;

        child_ptr.spawn() catch |err| {
            self.child = null;
            return err;
        };

        self.running = true;
        self.output_len = 0;

        // Start reader thread
        self.stdout_thread = std.Thread.spawn(.{}, readOutput, .{self}) catch null;
    }

    fn readOutput(self: *Self) void {
        if (self.child == null) return;

        const child_ptr = &self.child.?;
        const stdout = child_ptr.stdout orelse return;

        var buf: [4096]u8 = undefined;
        while (self.running) {
            const n = stdout.read(&buf) catch break;
            if (n == 0) break;

            self.output_mutex.lock();
            defer self.output_mutex.unlock();

            // Append to output buffer
            const space = self.output.len - self.output_len;
            if (n <= space) {
                @memcpy(self.output[self.output_len..][0..n], buf[0..n]);
                self.output_len += n;
            } else {
                // Scroll buffer
                const keep = self.output.len / 2;
                std.mem.copyForwards(u8, self.output[0..keep], self.output[self.output_len - keep .. self.output_len]);
                self.output_len = keep;
                const copy_n = @min(n, self.output.len - self.output_len);
                @memcpy(self.output[self.output_len..][0..copy_n], buf[0..copy_n]);
                self.output_len += copy_n;
            }
        }
    }

    /// Send input to shell
    pub fn sendInput(self: *Self, data: []const u8) void {
        if (!self.running or self.child == null) return;

        if (self.child.?.stdin) |stdin| {
            _ = stdin.write(data) catch {};
        }
    }

    /// Send key (with newline for Enter)
    pub fn sendKey(self: *Self, char: u8) void {
        self.sendInput(&[_]u8{char});
    }

    /// Send line (adds newline) and save to history
    pub fn sendLine(self: *Self, line: []const u8) void {
        // Save to history if non-empty
        if (line.len > 0 and self.history_count < 64) {
            const copy_len = @min(line.len, 255);
            @memcpy(self.history[self.history_count][0..copy_len], line[0..copy_len]);
            self.history_lens[self.history_count] = copy_len;
            self.history_count += 1;
        }
        self.history_pos = self.history_count; // Reset history position

        self.sendInput(line);
        self.sendInput("\n");

        // Reset scroll to bottom on new command
        self.scroll_offset = 0;
    }

    /// Get previous command from history
    pub fn historyPrev(self: *Self) ?[]const u8 {
        if (self.history_count == 0) return null;
        if (self.history_pos > 0) {
            self.history_pos -= 1;
        }
        return self.history[self.history_pos][0..self.history_lens[self.history_pos]];
    }

    /// Get next command from history
    pub fn historyNext(self: *Self) ?[]const u8 {
        if (self.history_pos >= self.history_count) return null;
        self.history_pos += 1;
        if (self.history_pos >= self.history_count) return null;
        return self.history[self.history_pos][0..self.history_lens[self.history_pos]];
    }

    /// Scroll up (show older output)
    pub fn scrollUp(self: *Self, lines: usize) void {
        self.updateLineCount();
        self.scroll_offset = @min(self.scroll_offset + lines, if (self.total_lines > 10) self.total_lines - 10 else 0);
    }

    /// Scroll down (show newer output)
    pub fn scrollDown(self: *Self, lines: usize) void {
        if (self.scroll_offset > lines) {
            self.scroll_offset -= lines;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Scroll to bottom (show latest)
    pub fn scrollToBottom(self: *Self) void {
        self.scroll_offset = 0;
    }

    /// Update total line count
    fn updateLineCount(self: *Self) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        var count: usize = 0;
        for (self.output[0..self.output_len]) |ch| {
            if (ch == '\n') count += 1;
        }
        self.total_lines = count;
    }

    /// Get total line count
    pub fn getLineCount(self: *Self) usize {
        self.updateLineCount();
        return self.total_lines;
    }

    /// Get current output
    pub fn getOutput(self: *Self) []const u8 {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();
        return self.output[0..self.output_len];
    }

    /// Get output lines for display (with scroll support)
    pub fn getLines(self: *Self, lines: *[64][]const u8, max_lines: usize) usize {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        const out = self.output[0..self.output_len];
        var count: usize = 0;
        var line_start: usize = 0;

        // Find all line starts
        var line_starts: [512]usize = undefined;
        var line_count: usize = 0;

        for (out, 0..) |ch, i| {
            if (ch == '\n') {
                if (line_count < 512) {
                    line_starts[line_count] = line_start;
                    line_count += 1;
                }
                line_start = i + 1;
            }
        }
        if (line_start < out.len and line_count < 512) {
            line_starts[line_count] = line_start;
            line_count += 1;
        }

        self.total_lines = line_count;

        // Calculate which lines to show (with scroll offset from bottom)
        const end_line = if (line_count > self.scroll_offset) line_count - self.scroll_offset else 0;
        const start_line = if (end_line > max_lines) end_line - max_lines else 0;

        // Return lines in range
        var i = start_line;
        while (i < end_line and count < max_lines) : (i += 1) {
            if (i >= line_count) break;
            const ls = line_starts[i];

            // Find line end
            var le = ls;
            while (le < out.len and out[le] != '\n') : (le += 1) {}

            lines[count] = out[ls..le];
            count += 1;
        }

        return count;
    }

    /// Get scroll info for scrollbar
    pub fn getScrollInfo(self: *Self) struct { total: usize, visible: usize, offset: usize } {
        return .{
            .total = self.total_lines,
            .visible = 10, // Approximate visible lines
            .offset = self.scroll_offset,
        };
    }

    /// Check if running
    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    /// Stop shell
    pub fn stop(self: *Self) void {
        if (!self.running) return;

        self.running = false;

        if (self.child) |*child_ptr| {
            // Send exit
            if (child_ptr.stdin) |stdin| {
                _ = stdin.write("exit\n") catch {};
            }
            _ = child_ptr.wait() catch {};
        }

        if (self.stdout_thread) |thread| {
            thread.join();
        }

        self.child = null;
        self.stdout_thread = null;
    }

    pub fn deinit(self: *Self) void {
        self.stop();
    }
};

// Global shell instance
var g_shell: ?Shell = null;

pub fn getShell() *Shell {
    if (g_shell == null) {
        g_shell = Shell.init();
    }
    return &g_shell.?;
}

pub fn startShell() !void {
    try getShell().start();
}

pub fn stopShell() void {
    if (g_shell) |*sh| {
        sh.stop();
    }
}
