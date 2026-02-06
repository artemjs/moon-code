const std = @import("std");
const GapBuffer = @import("buffer.zig").GapBuffer;

/// Tab information - represents a single editor tab
pub const Tab = struct {
    buffer: ?*GapBuffer = null,
    path: [512]u8 = undefined,
    path_len: usize = 0,
    name: [64]u8 = undefined,
    name_len: usize = 0,
    modified: bool = false,
    scroll_x: i32 = 0,
    scroll_y: i32 = 0,
    is_plugin: bool = false, // true = plugin details tab
    plugin_idx: usize = 0, // which plugin

    const Self = @This();

    /// Get the display name as a slice
    pub fn getName(self: *const Self) []const u8 {
        return self.name[0..self.name_len];
    }

    /// Get the file path as a slice
    pub fn getPath(self: *const Self) []const u8 {
        return self.path[0..self.path_len];
    }

    /// Check if tab has a file path (not "Untitled")
    pub fn hasPath(self: *const Self) bool {
        return self.path_len > 0;
    }

    /// Set the display name
    pub fn setName(self: *Self, name: []const u8) void {
        const len = @min(name.len, self.name.len);
        @memcpy(self.name[0..len], name[0..len]);
        self.name_len = len;
    }

    /// Set the file path
    pub fn setPath(self: *Self, path: []const u8) void {
        const len = @min(path.len, self.path.len);
        @memcpy(self.path[0..len], path[0..len]);
        self.path_len = len;
    }

    /// Extract filename from path and set as name
    pub fn setNameFromPath(self: *Self, path: []const u8) void {
        // Find last slash
        var last_slash: usize = 0;
        for (path, 0..) |c, i| {
            if (c == '/' or c == '\\') {
                last_slash = i + 1;
            }
        }
        const filename = path[last_slash..];
        self.setName(filename);
    }
};

/// Tab Manager - manages multiple editor tabs
/// Extracted from main.zig lines 1345-1360
pub const TabManager = struct {
    const Self = @This();
    pub const MAX_TABS = 16;

    tabs: [MAX_TABS]Tab = [_]Tab{Tab{}} ** MAX_TABS,
    count: usize = 0,
    active: usize = 0,
    hovered: i32 = -1,
    close_hovered: i32 = -1,

    // Auto-save tracking
    last_auto_save: i64 = 0,
    auto_save_interval_ms: i64 = 30000, // 30 seconds

    pub fn init() Self {
        return Self{};
    }

    /// Get the currently active tab
    pub fn getActiveTab(self: *Self) ?*Tab {
        if (self.count == 0) return null;
        return &self.tabs[self.active];
    }

    /// Get the currently active tab (const)
    pub fn getActiveTabConst(self: *const Self) ?*const Tab {
        if (self.count == 0) return null;
        return &self.tabs[self.active];
    }

    /// Get tab by index
    pub fn getTab(self: *Self, idx: usize) ?*Tab {
        if (idx >= self.count) return null;
        return &self.tabs[idx];
    }

    /// Create a new empty tab
    pub fn newTab(self: *Self, buffer: *GapBuffer) bool {
        if (self.count >= MAX_TABS) return false;

        var tab = &self.tabs[self.count];
        tab.* = Tab{};
        tab.buffer = buffer;
        tab.setName("Untitled");
        tab.modified = false;

        self.count += 1;
        self.active = self.count - 1;
        return true;
    }

    /// Open a file in a new tab
    pub fn openFile(self: *Self, path: []const u8, buffer: *GapBuffer) bool {
        if (self.count >= MAX_TABS) return false;

        // Check if file is already open
        for (self.tabs[0..self.count], 0..) |*tab, i| {
            if (tab.path_len == path.len and
                std.mem.eql(u8, tab.getPath(), path))
            {
                self.active = i;
                return true; // Already open, just switch to it
            }
        }

        var tab = &self.tabs[self.count];
        tab.* = Tab{};
        tab.buffer = buffer;
        tab.setPath(path);
        tab.setNameFromPath(path);
        tab.modified = false;

        self.count += 1;
        self.active = self.count - 1;
        return true;
    }

    /// Close the specified tab
    pub fn closeTab(self: *Self, idx: usize) bool {
        if (idx >= self.count) return false;
        if (self.count == 0) return false;

        // Shift remaining tabs
        var i = idx;
        while (i + 1 < self.count) : (i += 1) {
            self.tabs[i] = self.tabs[i + 1];
        }

        self.count -= 1;

        // Adjust active tab
        if (self.count == 0) {
            self.active = 0;
        } else if (self.active >= self.count) {
            self.active = self.count - 1;
        } else if (self.active > idx) {
            self.active -= 1;
        }

        return true;
    }

    /// Close the currently active tab
    pub fn closeActiveTab(self: *Self) bool {
        return self.closeTab(self.active);
    }

    /// Switch to the specified tab
    pub fn switchTo(self: *Self, idx: usize) void {
        if (idx < self.count) {
            self.active = idx;
        }
    }

    /// Switch to the next tab
    pub fn nextTab(self: *Self) void {
        if (self.count > 0) {
            self.active = (self.active + 1) % self.count;
        }
    }

    /// Switch to the previous tab
    pub fn prevTab(self: *Self) void {
        if (self.count > 0) {
            if (self.active == 0) {
                self.active = self.count - 1;
            } else {
                self.active -= 1;
            }
        }
    }

    /// Mark the active tab as modified
    pub fn markModified(self: *Self) void {
        if (self.getActiveTab()) |tab| {
            tab.modified = true;
        }
    }

    /// Mark the active tab as saved
    pub fn markSaved(self: *Self) void {
        if (self.getActiveTab()) |tab| {
            tab.modified = false;
        }
    }

    /// Check if any tab has unsaved changes
    pub fn hasUnsavedChanges(self: *const Self) bool {
        for (self.tabs[0..self.count]) |tab| {
            if (tab.modified) return true;
        }
        return false;
    }

    /// Get number of tabs with unsaved changes
    pub fn countUnsaved(self: *const Self) usize {
        var count: usize = 0;
        for (self.tabs[0..self.count]) |tab| {
            if (tab.modified) count += 1;
        }
        return count;
    }

    /// Store scroll position for active tab
    pub fn saveScrollPosition(self: *Self, scroll_x: i32, scroll_y: i32) void {
        if (self.getActiveTab()) |tab| {
            tab.scroll_x = scroll_x;
            tab.scroll_y = scroll_y;
        }
    }

    /// Get scroll position for active tab
    pub fn getScrollPosition(self: *const Self) struct { x: i32, y: i32 } {
        if (self.getActiveTabConst()) |tab| {
            return .{ .x = tab.scroll_x, .y = tab.scroll_y };
        }
        return .{ .x = 0, .y = 0 };
    }

    /// Check if auto-save should be triggered
    pub fn shouldAutoSave(self: *Self, current_time: i64) bool {
        if (current_time - self.last_auto_save >= self.auto_save_interval_ms) {
            self.last_auto_save = current_time;
            return true;
        }
        return false;
    }

    /// Reset hover states
    pub fn resetHover(self: *Self) void {
        self.hovered = -1;
        self.close_hovered = -1;
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "Tab.setName and getName" {
    var tab = Tab{};
    tab.setName("test.zig");

    try std.testing.expectEqualStrings("test.zig", tab.getName());
}

test "Tab.setPath and getPath" {
    var tab = Tab{};
    tab.setPath("/home/user/project/main.zig");

    try std.testing.expectEqualStrings("/home/user/project/main.zig", tab.getPath());
}

test "Tab.setNameFromPath extracts filename" {
    var tab = Tab{};
    tab.setNameFromPath("/home/user/project/main.zig");

    try std.testing.expectEqualStrings("main.zig", tab.getName());
}

test "Tab.hasPath returns correct state" {
    var tab = Tab{};

    try std.testing.expectEqual(false, tab.hasPath());

    tab.setPath("/some/path.zig");
    try std.testing.expectEqual(true, tab.hasPath());
}

test "TabManager.init creates empty manager" {
    var manager = TabManager.init();

    try std.testing.expectEqual(@as(usize, 0), manager.count);
    try std.testing.expectEqual(@as(usize, 0), manager.active);
    try std.testing.expect(manager.getActiveTab() == null);
}

test "TabManager.newTab adds tab" {
    var manager = TabManager.init();
    var buffer: GapBuffer = undefined; // Mock buffer

    const result = manager.newTab(&buffer);

    try std.testing.expectEqual(true, result);
    try std.testing.expectEqual(@as(usize, 1), manager.count);
    try std.testing.expectEqual(@as(usize, 0), manager.active);
    try std.testing.expectEqualStrings("Untitled", manager.getActiveTab().?.getName());
}

test "TabManager.closeTab removes tab" {
    var manager = TabManager.init();
    var buffer1: GapBuffer = undefined;
    var buffer2: GapBuffer = undefined;

    _ = manager.newTab(&buffer1);
    _ = manager.newTab(&buffer2);

    try std.testing.expectEqual(@as(usize, 2), manager.count);

    _ = manager.closeTab(0);

    try std.testing.expectEqual(@as(usize, 1), manager.count);
}

test "TabManager.switchTo changes active tab" {
    var manager = TabManager.init();
    var buffer1: GapBuffer = undefined;
    var buffer2: GapBuffer = undefined;
    var buffer3: GapBuffer = undefined;

    _ = manager.newTab(&buffer1);
    _ = manager.newTab(&buffer2);
    _ = manager.newTab(&buffer3);

    try std.testing.expectEqual(@as(usize, 2), manager.active);

    manager.switchTo(0);
    try std.testing.expectEqual(@as(usize, 0), manager.active);

    manager.switchTo(1);
    try std.testing.expectEqual(@as(usize, 1), manager.active);
}

test "TabManager.nextTab and prevTab cycle" {
    var manager = TabManager.init();
    var buffer1: GapBuffer = undefined;
    var buffer2: GapBuffer = undefined;
    var buffer3: GapBuffer = undefined;

    _ = manager.newTab(&buffer1);
    _ = manager.newTab(&buffer2);
    _ = manager.newTab(&buffer3);

    manager.switchTo(0);
    manager.nextTab();
    try std.testing.expectEqual(@as(usize, 1), manager.active);

    manager.nextTab();
    manager.nextTab(); // Wraps around
    try std.testing.expectEqual(@as(usize, 0), manager.active);

    manager.prevTab(); // Wraps to end
    try std.testing.expectEqual(@as(usize, 2), manager.active);
}

test "TabManager.markModified and markSaved" {
    var manager = TabManager.init();
    var buffer: GapBuffer = undefined;

    _ = manager.newTab(&buffer);

    try std.testing.expectEqual(false, manager.getActiveTab().?.modified);

    manager.markModified();
    try std.testing.expectEqual(true, manager.getActiveTab().?.modified);

    manager.markSaved();
    try std.testing.expectEqual(false, manager.getActiveTab().?.modified);
}

test "TabManager.hasUnsavedChanges" {
    var manager = TabManager.init();
    var buffer1: GapBuffer = undefined;
    var buffer2: GapBuffer = undefined;

    _ = manager.newTab(&buffer1);
    _ = manager.newTab(&buffer2);

    try std.testing.expectEqual(false, manager.hasUnsavedChanges());

    manager.markModified();
    try std.testing.expectEqual(true, manager.hasUnsavedChanges());
    try std.testing.expectEqual(@as(usize, 1), manager.countUnsaved());
}

test "TabManager respects MAX_TABS limit" {
    var manager = TabManager.init();
    var buffers: [TabManager.MAX_TABS + 1]GapBuffer = undefined;

    // Add MAX_TABS tabs
    for (0..TabManager.MAX_TABS) |i| {
        const result = manager.newTab(&buffers[i]);
        try std.testing.expectEqual(true, result);
    }

    // Try to add one more - should fail
    const result = manager.newTab(&buffers[TabManager.MAX_TABS]);
    try std.testing.expectEqual(false, result);
    try std.testing.expectEqual(TabManager.MAX_TABS, manager.count);
}
