const std = @import("std");

/// UI State - encapsulates all UI-related state variables
/// Extracted from main.zig lines 1307-1322
pub const UIState = struct {
    const Self = @This();

    // Sidebar state
    sidebar_visible: bool = true,
    sidebar_width: i32 = 200,
    dragging_sidebar: bool = false,
    sidebar_active_tab: usize = 0, // 0 = Explorer, 1 = Search, 2 = Git
    sidebar_tab_hovered: i32 = -1,
    open_folder_btn_hovered: bool = false,
    sidebar_resize_hovered: bool = false,

    // Menu state
    menu_open: i32 = -1, // -1 = closed, 0 = File, 1 = Edit, 2 = View
    menu_hover: i32 = -1,
    menu_item_hover: i32 = -1,

    // Settings dialog state
    settings_visible: bool = false,
    settings_active_tab: u8 = 0, // 0 = About, 1 = Additional
    settings_tab_hovered: i8 = -1,
    settings_checkbox_hovered: bool = false,
    settings_close_hovered: bool = false,

    // Scroll state
    scroll_velocity_y: f32 = 0, // Inertia velocity

    // Zoom levels
    zoom_level: f32 = 1.0,
    text_zoom: f32 = 1.0,

    // Editor focus
    editor_focused: bool = true,

    // Scrollbar drag state
    dragging_vbar: bool = false,
    dragging_hbar: bool = false,
    drag_start_scroll: i32 = 0,
    drag_start_mouse: i32 = 0,

    // Bottom panel drag state
    dragging_bottom_panel: bool = false,
    dragging_tab_bar: bool = false,
    tab_bar_resize_hovered: bool = false,

    pub fn init() Self {
        return Self{};
    }

    /// Scale a UI dimension based on current zoom level
    pub fn scaleUI(self: *const Self, base: u32) u32 {
        return @max(1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(base)) * self.zoom_level)));
    }

    /// Scale a signed UI dimension
    pub fn scaleUISigned(self: *const Self, base: i32) i32 {
        return @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(base)) * self.zoom_level)));
    }

    /// Scale text based on text zoom level
    pub fn scaleText(self: *const Self, base: f32) f32 {
        return base * self.text_zoom;
    }

    /// Toggle sidebar visibility
    pub fn toggleSidebar(self: *Self) void {
        self.sidebar_visible = !self.sidebar_visible;
    }

    /// Toggle settings dialog
    pub fn toggleSettings(self: *Self) void {
        self.settings_visible = !self.settings_visible;
    }

    /// Close all menus
    pub fn closeMenus(self: *Self) void {
        self.menu_open = -1;
        self.menu_hover = -1;
        self.menu_item_hover = -1;
    }

    /// Check if any menu is open
    pub fn isMenuOpen(self: *const Self) bool {
        return self.menu_open >= 0;
    }

    /// Check if any drag operation is in progress
    pub fn isDragging(self: *const Self) bool {
        return self.dragging_sidebar or
            self.dragging_vbar or
            self.dragging_hbar or
            self.dragging_bottom_panel or
            self.dragging_tab_bar;
    }

    /// Reset all hover states
    pub fn resetHoverStates(self: *Self) void {
        self.sidebar_tab_hovered = -1;
        self.open_folder_btn_hovered = false;
        self.sidebar_resize_hovered = false;
        self.menu_hover = -1;
        self.menu_item_hover = -1;
        self.settings_tab_hovered = -1;
        self.settings_checkbox_hovered = false;
        self.settings_close_hovered = false;
        self.tab_bar_resize_hovered = false;
    }

    /// Apply scroll inertia (call each frame)
    pub fn applyScrollInertia(self: *Self, scroll_y: *i32, max_scroll: i32) void {
        if (@abs(self.scroll_velocity_y) > 0.5) {
            scroll_y.* += @as(i32, @intFromFloat(self.scroll_velocity_y));
            scroll_y.* = @max(0, @min(scroll_y.*, max_scroll));
            self.scroll_velocity_y *= 0.92; // Friction
        } else {
            self.scroll_velocity_y = 0;
        }
    }

    /// Add scroll velocity for inertia effect
    pub fn addScrollVelocity(self: *Self, delta: f32) void {
        self.scroll_velocity_y += delta;
        // Cap velocity
        const max_velocity: f32 = 50.0;
        if (self.scroll_velocity_y > max_velocity) self.scroll_velocity_y = max_velocity;
        if (self.scroll_velocity_y < -max_velocity) self.scroll_velocity_y = -max_velocity;
    }

    /// Zoom in
    pub fn zoomIn(self: *Self) void {
        self.zoom_level = @min(3.0, self.zoom_level + 0.1);
    }

    /// Zoom out
    pub fn zoomOut(self: *Self) void {
        self.zoom_level = @max(0.5, self.zoom_level - 0.1);
    }

    /// Reset zoom to default
    pub fn resetZoom(self: *Self) void {
        self.zoom_level = 1.0;
    }

    /// Text zoom in
    pub fn textZoomIn(self: *Self) void {
        self.text_zoom = @min(3.0, self.text_zoom + 0.1);
    }

    /// Text zoom out
    pub fn textZoomOut(self: *Self) void {
        self.text_zoom = @max(0.5, self.text_zoom - 0.1);
    }
};

/// Search state for find/replace functionality
pub const SearchState = struct {
    const Self = @This();
    const MAX_MATCHES = 4096;

    visible: bool = false,
    query: [256]u8 = [_]u8{0} ** 256,
    query_len: usize = 0,
    matches: [MAX_MATCHES]usize = undefined, // Match positions
    match_count: usize = 0,
    current_match: usize = 0,

    pub fn init() Self {
        return Self{};
    }

    /// Toggle search visibility
    pub fn toggle(self: *Self) void {
        self.visible = !self.visible;
    }

    /// Clear search results
    pub fn clear(self: *Self) void {
        self.match_count = 0;
        self.current_match = 0;
    }

    /// Go to next match
    pub fn nextMatch(self: *Self) void {
        if (self.match_count > 0) {
            self.current_match = (self.current_match + 1) % self.match_count;
        }
    }

    /// Go to previous match
    pub fn prevMatch(self: *Self) void {
        if (self.match_count > 0) {
            if (self.current_match == 0) {
                self.current_match = self.match_count - 1;
            } else {
                self.current_match -= 1;
            }
        }
    }

    /// Get current match position
    pub fn getCurrentMatchPos(self: *const Self) ?usize {
        if (self.match_count == 0) return null;
        return self.matches[self.current_match];
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "UIState.init creates default state" {
    const state = UIState.init();

    try std.testing.expectEqual(true, state.sidebar_visible);
    try std.testing.expectEqual(@as(i32, 200), state.sidebar_width);
    try std.testing.expectEqual(@as(i32, -1), state.menu_open);
    try std.testing.expectEqual(false, state.settings_visible);
    try std.testing.expectEqual(@as(f32, 1.0), state.zoom_level);
}

test "UIState.scaleUI scales correctly" {
    var state = UIState.init();
    state.zoom_level = 2.0;

    try std.testing.expectEqual(@as(u32, 200), state.scaleUI(100));
    try std.testing.expectEqual(@as(u32, 20), state.scaleUI(10));
}

test "UIState.toggleSidebar works" {
    var state = UIState.init();

    try std.testing.expectEqual(true, state.sidebar_visible);
    state.toggleSidebar();
    try std.testing.expectEqual(false, state.sidebar_visible);
    state.toggleSidebar();
    try std.testing.expectEqual(true, state.sidebar_visible);
}

test "UIState.isDragging detects any drag" {
    var state = UIState.init();

    try std.testing.expectEqual(false, state.isDragging());

    state.dragging_sidebar = true;
    try std.testing.expectEqual(true, state.isDragging());

    state.dragging_sidebar = false;
    state.dragging_vbar = true;
    try std.testing.expectEqual(true, state.isDragging());
}

test "UIState zoom operations" {
    var state = UIState.init();

    state.zoomIn();
    try std.testing.expect(state.zoom_level > 1.0);

    state.resetZoom();
    try std.testing.expectEqual(@as(f32, 1.0), state.zoom_level);

    state.zoomOut();
    try std.testing.expect(state.zoom_level < 1.0);
}

test "SearchState.init creates default state" {
    const search = SearchState.init();

    try std.testing.expectEqual(false, search.visible);
    try std.testing.expectEqual(@as(usize, 0), search.match_count);
    try std.testing.expectEqual(@as(usize, 0), search.current_match);
}

test "SearchState navigation" {
    var search = SearchState.init();
    search.match_count = 5;

    search.nextMatch();
    try std.testing.expectEqual(@as(usize, 1), search.current_match);

    search.nextMatch();
    search.nextMatch();
    search.nextMatch();
    search.nextMatch(); // Wraps around
    try std.testing.expectEqual(@as(usize, 0), search.current_match);

    search.prevMatch(); // Wraps to end
    try std.testing.expectEqual(@as(usize, 4), search.current_match);
}

test "SearchState.clear resets state" {
    var search = SearchState.init();
    search.match_count = 10;
    search.current_match = 5;

    search.clear();

    try std.testing.expectEqual(@as(usize, 0), search.match_count);
    try std.testing.expectEqual(@as(usize, 0), search.current_match);
}
