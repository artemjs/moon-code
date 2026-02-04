const std = @import("std");

/// Constants for key repeat
pub const REPEAT_DELAY_MS: i64 = 400; // Delay before repeat starts
pub const REPEAT_RATE_MS: i64 = 30; // Repeat interval
pub const ACCEL_START_MS: i64 = 8000; // When acceleration starts
pub const ACCEL_INTERVAL_MS: i64 = 500; // Speed doubling interval

/// Key repeat state
pub const KeyRepeatState = struct {
    held_key: ?u32 = null,
    held_char: ?u8 = null,
    press_time_ms: i64 = 0,
    last_repeat_ms: i64 = 0,
    last_accel_ms: i64 = 0,
    skip_lines: u32 = 1,

    pub fn reset(self: *KeyRepeatState) void {
        self.held_key = null;
        self.held_char = null;
        self.skip_lines = 1;
    }

    pub fn startPress(self: *KeyRepeatState, key: u32, char: ?u8, now: i64) void {
        self.held_key = key;
        self.held_char = char;
        self.press_time_ms = now;
        self.last_repeat_ms = now;
        self.last_accel_ms = now;
        self.skip_lines = 1;
    }

    pub fn release(self: *KeyRepeatState, key: u32) void {
        if (self.held_key == key) {
            self.reset();
        }
    }

    /// Checks if key press should repeat
    /// Returns the number of "skip" units (for navigation acceleration)
    pub fn shouldRepeat(self: *KeyRepeatState, now: i64, is_navigation: bool) ?u32 {
        if (self.held_key == null) return null;

        const held_duration = now - self.press_time_ms;
        if (held_duration <= REPEAT_DELAY_MS) return null;

        // Acceleration for navigation
        if (is_navigation and held_duration > ACCEL_START_MS) {
            if (now - self.last_accel_ms > ACCEL_INTERVAL_MS) {
                self.skip_lines *= 2;
                self.last_accel_ms = now;
            }
        }

        // Check repeat interval
        if (now - self.last_repeat_ms > REPEAT_RATE_MS) {
            self.last_repeat_ms = now;
            return self.skip_lines;
        }

        return null;
    }
};

/// Simple text buffer for input fields (search, dialogs, etc.)
pub const TextFieldBuffer = struct {
    data: []u8,
    len: usize = 0,
    cursor: usize = 0,
    max_len: usize,

    pub fn init(buffer: []u8) TextFieldBuffer {
        return .{
            .data = buffer,
            .len = 0,
            .cursor = 0,
            .max_len = buffer.len,
        };
    }

    pub fn initWithData(buffer: []u8, initial: []const u8) TextFieldBuffer {
        const copy_len = @min(initial.len, buffer.len - 1);
        @memcpy(buffer[0..copy_len], initial[0..copy_len]);
        return .{
            .data = buffer,
            .len = copy_len,
            .cursor = copy_len,
            .max_len = buffer.len,
        };
    }

    pub fn clear(self: *TextFieldBuffer) void {
        self.len = 0;
        self.cursor = 0;
    }

    pub fn getText(self: *const TextFieldBuffer) []const u8 {
        return self.data[0..self.len];
    }

    /// Insert character at cursor position
    pub fn insert(self: *TextFieldBuffer, ch: u8) bool {
        if (self.len >= self.max_len - 1) return false;

        // Shift characters right
        var i: usize = self.len;
        while (i > self.cursor) : (i -= 1) {
            self.data[i] = self.data[i - 1];
        }
        self.data[self.cursor] = ch;
        self.len += 1;
        self.cursor += 1;
        return true;
    }

    /// Delete character before cursor (Backspace)
    pub fn deleteBack(self: *TextFieldBuffer) bool {
        if (self.cursor == 0) return false;

        // Shift characters left
        var i: usize = self.cursor - 1;
        while (i < self.len - 1) : (i += 1) {
            self.data[i] = self.data[i + 1];
        }
        self.len -= 1;
        self.cursor -= 1;
        return true;
    }

    /// Delete character after cursor (Delete)
    pub fn deleteForward(self: *TextFieldBuffer) bool {
        if (self.cursor >= self.len) return false;

        // Shift characters left
        var i: usize = self.cursor;
        while (i < self.len - 1) : (i += 1) {
            self.data[i] = self.data[i + 1];
        }
        self.len -= 1;
        return true;
    }

    /// Move cursor left
    pub fn moveCursorLeft(self: *TextFieldBuffer) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Move cursor right
    pub fn moveCursorRight(self: *TextFieldBuffer) void {
        if (self.cursor < self.len) {
            self.cursor += 1;
        }
    }

    /// Move cursor to start
    pub fn moveCursorHome(self: *TextFieldBuffer) void {
        self.cursor = 0;
    }

    /// Move cursor to end
    pub fn moveCursorEnd(self: *TextFieldBuffer) void {
        self.cursor = self.len;
    }
};

/// Check if key is a navigation key
pub fn isNavigationKey(key: u32) bool {
    const KEY_LEFT: u32 = 105;
    const KEY_RIGHT: u32 = 106;
    const KEY_UP: u32 = 103;
    const KEY_DOWN: u32 = 108;
    const KEY_HOME: u32 = 102;
    const KEY_END: u32 = 107;

    return key == KEY_LEFT or key == KEY_RIGHT or
        key == KEY_UP or key == KEY_DOWN or
        key == KEY_HOME or key == KEY_END;
}

/// Handle key press for text field
/// Returns true if field was modified
pub fn handleTextFieldKey(field: *TextFieldBuffer, key: u32, char: ?u8) bool {
    const KEY_BACKSPACE: u32 = 14;
    const KEY_DELETE: u32 = 111;
    const KEY_LEFT: u32 = 105;
    const KEY_RIGHT: u32 = 106;
    const KEY_HOME: u32 = 102;
    const KEY_END: u32 = 107;

    if (key == KEY_BACKSPACE) {
        return field.deleteBack();
    } else if (key == KEY_DELETE) {
        return field.deleteForward();
    } else if (key == KEY_LEFT) {
        field.moveCursorLeft();
        return false;
    } else if (key == KEY_RIGHT) {
        field.moveCursorRight();
        return false;
    } else if (key == KEY_HOME) {
        field.moveCursorHome();
        return false;
    } else if (key == KEY_END) {
        field.moveCursorEnd();
        return false;
    } else if (char) |ch| {
        return field.insert(ch);
    }
    return false;
}
