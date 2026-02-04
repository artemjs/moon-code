const std = @import("std");
const GpuRenderer = @import("../render/gpu.zig").GpuRenderer;

// Colors (consistent with main.zig)
pub const Colors = struct {
    pub const bg: u32 = 0xFF1e1e1e;
    pub const surface: u32 = 0xFF242424;
    pub const surface_hover: u32 = 0xFF2a2a2a;
    pub const surface_active: u32 = 0xFF333333;
    pub const accent: u32 = 0xFFff9b71;
    pub const accent_dim: u32 = 0xFF4a3830;
    pub const text: u32 = 0xFFe0e0e0;
    pub const text_dim: u32 = 0xFF808080;
    pub const border: u32 = 0xFF3a3a3a;
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,

    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and px < self.x + @as(i32, @intCast(self.w)) and
            py >= self.y and py < self.y + @as(i32, @intCast(self.h));
    }
};

// === Button ===
pub const Button = struct {
    rect: Rect,
    label: []const u8,
    hovered: bool = false,
    active: bool = false,

    pub fn init(x: i32, y: i32, w: u32, h: u32, label: []const u8) Button {
        return .{
            .rect = .{ .x = x, .y = y, .w = w, .h = h },
            .label = label,
        };
    }

    pub fn update(self: *Button, mouse_x: i32, mouse_y: i32, pressed: bool) bool {
        self.hovered = self.rect.contains(mouse_x, mouse_y);
        const was_active = self.active;
        self.active = self.hovered and pressed;
        // Return true if clicked (was active, now released while hovered)
        return was_active and !pressed and self.hovered;
    }

    pub fn draw(self: *const Button, gpu: *GpuRenderer) void {
        const bg_color: u32 = if (self.active) Colors.surface_active else if (self.hovered) Colors.surface_hover else Colors.surface;
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, self.rect.h, 4, bg_color);

        // Center text
        const text_w: i32 = @as(i32, @intCast(self.label.len)) * @as(i32, @intCast(gpu.charWidth()));
        const text_x = self.rect.x + @divTrunc(@as(i32, @intCast(self.rect.w)) - text_w, 2);
        const text_y = self.rect.y + @divTrunc(@as(i32, @intCast(self.rect.h)) - @as(i32, @intCast(gpu.lineHeight())), 2);
        const text_color: u32 = if (self.hovered) Colors.accent else Colors.text;
        gpu.drawText(self.label, text_x, text_y, text_color);
    }
};

// === Menu Item ===
pub const MenuItem = struct {
    label: []const u8,
    shortcut: ?[]const u8 = null,
    action: ?*const fn () void = null,
};

// === Dropdown Menu ===
pub const DropdownMenu = struct {
    trigger: Button,
    items: []const MenuItem,
    open: bool = false,
    hovered_item: ?usize = null,
    item_height: u32 = 28,

    pub fn init(x: i32, y: i32, label: []const u8, items: []const MenuItem) DropdownMenu {
        const w: u32 = @as(u32, @intCast(label.len)) * 9 + 24;
        return .{
            .trigger = Button.init(x, y, w, 26, label),
            .items = items,
        };
    }

    pub fn getMenuRect(self: *const DropdownMenu) Rect {
        var max_w: usize = 0;
        for (self.items) |item| {
            var item_len = item.label.len;
            if (item.shortcut) |sc| {
                item_len += sc.len + 4;
            }
            if (item_len > max_w) max_w = item_len;
        }
        const w: u32 = @max(120, @as(u32, @intCast(max_w)) * 9 + 32);
        const h: u32 = @as(u32, @intCast(self.items.len)) * self.item_height + 8;
        return .{
            .x = self.trigger.rect.x,
            .y = self.trigger.rect.y + @as(i32, @intCast(self.trigger.rect.h)) + 2,
            .w = w,
            .h = h,
        };
    }

    pub fn update(self: *DropdownMenu, mouse_x: i32, mouse_y: i32, clicked: bool) ?usize {
        // Update trigger button
        self.trigger.hovered = self.trigger.rect.contains(mouse_x, mouse_y);

        if (self.open) {
            const menu_rect = self.getMenuRect();
            const in_menu = menu_rect.contains(mouse_x, mouse_y);
            const in_trigger = self.trigger.rect.contains(mouse_x, mouse_y);

            if (in_menu) {
                // Calculate which item is hovered
                const rel_y = mouse_y - menu_rect.y - 4;
                if (rel_y >= 0) {
                    self.hovered_item = @intCast(@divTrunc(rel_y, @as(i32, @intCast(self.item_height))));
                    if (self.hovered_item.? >= self.items.len) {
                        self.hovered_item = null;
                    }
                }

                if (clicked and self.hovered_item != null) {
                    const selected = self.hovered_item;
                    self.open = false;
                    self.hovered_item = null;
                    return selected;
                }
            } else {
                self.hovered_item = null;
                if (clicked and !in_trigger) {
                    self.open = false;
                }
            }

            if (clicked and in_trigger) {
                self.open = false;
            }
        } else {
            if (clicked and self.trigger.hovered) {
                self.open = true;
            }
        }

        return null;
    }

    pub fn draw(self: *const DropdownMenu, gpu: *GpuRenderer) void {
        // Draw trigger - styled like window buttons
        const bg_color: u32 = if (self.open or self.trigger.hovered) 0xFF3a3a3a else 0xFF1a1a1a;
        gpu.fillRoundedRect(self.trigger.rect.x, self.trigger.rect.y, self.trigger.rect.w, self.trigger.rect.h, 6, bg_color);

        const text_x = self.trigger.rect.x + 10;
        const text_y = self.trigger.rect.y + @divTrunc(@as(i32, @intCast(self.trigger.rect.h)) - @as(i32, @intCast(gpu.lineHeight())), 2);
        const text_color: u32 = if (self.open or self.trigger.hovered) Colors.accent else Colors.text_dim;
        gpu.drawText(self.trigger.label, text_x, text_y, text_color);

        // Draw dropdown if open
        if (self.open) {
            const menu_rect = self.getMenuRect();

            // Menu background - dark like the main background
            gpu.fillRoundedRect(menu_rect.x, menu_rect.y, menu_rect.w, menu_rect.h, 8, 0xFF1e1e1e);
            // Subtle border
            gpu.fillRoundedRect(menu_rect.x, menu_rect.y, menu_rect.w, 1, 8, 0xFF3a3a3a);
            gpu.fillRoundedRect(menu_rect.x, menu_rect.y + @as(i32, @intCast(menu_rect.h)) - 1, menu_rect.w, 1, 8, 0xFF3a3a3a);
            gpu.fillRoundedRect(menu_rect.x, menu_rect.y, 1, menu_rect.h, 8, 0xFF3a3a3a);
            gpu.fillRoundedRect(menu_rect.x + @as(i32, @intCast(menu_rect.w)) - 1, menu_rect.y, 1, menu_rect.h, 8, 0xFF3a3a3a);

            // Items
            var item_y: i32 = menu_rect.y + 4;
            for (self.items, 0..) |item, idx| {
                const is_hovered = self.hovered_item == idx;

                if (is_hovered) {
                    gpu.fillRoundedRect(menu_rect.x + 4, item_y, menu_rect.w - 8, self.item_height, 4, Colors.accent_dim);
                }

                const item_text_y = item_y + @divTrunc(@as(i32, @intCast(self.item_height)) - @as(i32, @intCast(gpu.lineHeight())), 2);
                const item_color: u32 = if (is_hovered) Colors.accent else Colors.text;
                gpu.drawText(item.label, menu_rect.x + 12, item_text_y, item_color);

                // Shortcut
                if (item.shortcut) |sc| {
                    const sc_x = menu_rect.x + @as(i32, @intCast(menu_rect.w)) - @as(i32, @intCast(sc.len * 9)) - 12;
                    gpu.drawText(sc, sc_x, item_text_y, Colors.text_dim);
                }

                item_y += @intCast(self.item_height);
            }
        }
    }
};

// === Popup / Modal ===
pub const Popup = struct {
    rect: Rect,
    title: []const u8,
    visible: bool = false,
    close_hovered: bool = false,

    pub fn init(title: []const u8, w: u32, h: u32) Popup {
        return .{
            .rect = .{ .x = 0, .y = 0, .w = w, .h = h },
            .title = title,
        };
    }

    pub fn show(self: *Popup, screen_w: u32, screen_h: u32) void {
        self.rect.x = @divTrunc(@as(i32, @intCast(screen_w)) - @as(i32, @intCast(self.rect.w)), 2);
        self.rect.y = @divTrunc(@as(i32, @intCast(screen_h)) - @as(i32, @intCast(self.rect.h)), 2);
        self.visible = true;
    }

    pub fn hide(self: *Popup) void {
        self.visible = false;
    }

    pub fn update(self: *Popup, mouse_x: i32, mouse_y: i32, clicked: bool) bool {
        if (!self.visible) return false;

        // Close button area (top right)
        const close_x = self.rect.x + @as(i32, @intCast(self.rect.w)) - 32;
        const close_y = self.rect.y + 8;
        self.close_hovered = mouse_x >= close_x and mouse_x < close_x + 24 and
            mouse_y >= close_y and mouse_y < close_y + 24;

        if (clicked and self.close_hovered) {
            self.visible = false;
            return true;
        }

        return false;
    }

    pub fn draw(self: *const Popup, gpu: *GpuRenderer) void {
        if (!self.visible) return;

        // Semi-transparent overlay would be nice, but for now just darker bg
        // gpu.fillRect(0, 0, screen_w, screen_h, 0x80000000);

        // Popup background
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, self.rect.h, 8, Colors.surface);

        // Border
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, 2, 8, Colors.border);
        gpu.fillRoundedRect(self.rect.x, self.rect.y + @as(i32, @intCast(self.rect.h)) - 2, self.rect.w, 2, 8, Colors.border);
        gpu.fillRoundedRect(self.rect.x, self.rect.y, 2, self.rect.h, 8, Colors.border);
        gpu.fillRoundedRect(self.rect.x + @as(i32, @intCast(self.rect.w)) - 2, self.rect.y, 2, self.rect.h, 8, Colors.border);

        // Title bar
        const title_y = self.rect.y + 12;
        gpu.drawText(self.title, self.rect.x + 16, title_y, Colors.text);

        // Close button
        const close_x = self.rect.x + @as(i32, @intCast(self.rect.w)) - 32;
        const close_y = self.rect.y + 8;
        const close_color: u32 = if (self.close_hovered) 0xFFff6b6b else Colors.text_dim;
        gpu.drawText("X", close_x + 7, close_y + 4, close_color);

        // Separator
        gpu.fillRect(self.rect.x + 8, self.rect.y + 36, self.rect.w - 16, 1, Colors.border);
    }

    pub fn contentRect(self: *const Popup) Rect {
        return .{
            .x = self.rect.x + 16,
            .y = self.rect.y + 48,
            .w = self.rect.w - 32,
            .h = self.rect.h - 64,
        };
    }
};

// === Tab Bar ===
pub const TabBar = struct {
    tabs: []const []const u8,
    selected: usize = 0,
    rect: Rect,
    hovered_tab: ?usize = null,

    pub fn init(x: i32, y: i32, tabs: []const []const u8) TabBar {
        return .{
            .tabs = tabs,
            .rect = .{ .x = x, .y = y, .w = 0, .h = 28 },
        };
    }

    pub fn update(self: *TabBar, mouse_x: i32, mouse_y: i32, clicked: bool) void {
        self.hovered_tab = null;
        var tab_x = self.rect.x;

        for (self.tabs, 0..) |tab, idx| {
            const tab_w: u32 = @as(u32, @intCast(tab.len)) * 9 + 24;
            if (mouse_x >= tab_x and mouse_x < tab_x + @as(i32, @intCast(tab_w)) and
                mouse_y >= self.rect.y and mouse_y < self.rect.y + @as(i32, @intCast(self.rect.h)))
            {
                self.hovered_tab = idx;
                if (clicked) {
                    self.selected = idx;
                }
            }
            tab_x += @intCast(tab_w + 4);
        }
    }

    pub fn draw(self: *const TabBar, gpu: *GpuRenderer) void {
        var tab_x = self.rect.x;

        for (self.tabs, 0..) |tab, idx| {
            const tab_w: u32 = @as(u32, @intCast(tab.len)) * 9 + 24;
            const is_selected = self.selected == idx;
            const is_hovered = self.hovered_tab == idx;

            const bg_color: u32 = if (is_selected) Colors.accent_dim else if (is_hovered) Colors.surface_hover else Colors.surface;
            gpu.fillRoundedRect(tab_x, self.rect.y, tab_w, self.rect.h, 4, bg_color);

            const text_x = tab_x + 12;
            const text_y = self.rect.y + @divTrunc(@as(i32, @intCast(self.rect.h)) - @as(i32, @intCast(gpu.lineHeight())), 2);
            const text_color: u32 = if (is_selected) Colors.accent else if (is_hovered) Colors.text else Colors.text_dim;
            gpu.drawText(tab, text_x, text_y, text_color);

            tab_x += @intCast(tab_w + 4);
        }
    }
};

// === Confirm Dialog ===
pub const ConfirmResult = enum {
    none, // No action yet
    confirmed, // User clicked confirm
    cancelled, // User clicked cancel or pressed Escape
};

pub const ConfirmDialog = struct {
    visible: bool = false,
    title: [128]u8 = [_]u8{0} ** 128,
    title_len: usize = 0,
    message: [256]u8 = [_]u8{0} ** 256,
    message_len: usize = 0,
    confirm_text: [32]u8 = [_]u8{0} ** 32,
    confirm_len: usize = 0,
    cancel_text: [32]u8 = [_]u8{0} ** 32,
    cancel_len: usize = 0,
    is_destructive: bool = false, // Red confirm button for dangerous actions

    // Button hover states
    confirm_hovered: bool = false,
    cancel_hovered: bool = false,

    // Calculated layout
    rect: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },

    pub fn init() ConfirmDialog {
        return .{};
    }

    /// Show the dialog with custom text
    pub fn show(
        self: *ConfirmDialog,
        title: []const u8,
        message: []const u8,
        confirm_btn: []const u8,
        cancel_btn: []const u8,
        destructive: bool,
        screen_w: u32,
        screen_h: u32,
    ) void {
        // Copy title
        const t_len = @min(title.len, self.title.len);
        @memcpy(self.title[0..t_len], title[0..t_len]);
        self.title_len = t_len;

        // Copy message
        const m_len = @min(message.len, self.message.len);
        @memcpy(self.message[0..m_len], message[0..m_len]);
        self.message_len = m_len;

        // Copy confirm text
        const c_len = @min(confirm_btn.len, self.confirm_text.len);
        @memcpy(self.confirm_text[0..c_len], confirm_btn[0..c_len]);
        self.confirm_len = c_len;

        // Copy cancel text
        const cn_len = @min(cancel_btn.len, self.cancel_text.len);
        @memcpy(self.cancel_text[0..cn_len], cancel_btn[0..cn_len]);
        self.cancel_len = cn_len;

        self.is_destructive = destructive;
        self.visible = true;
        self.confirm_hovered = false;
        self.cancel_hovered = false;

        // Calculate dialog size
        const dialog_w: u32 = 360;
        const dialog_h: u32 = 160;
        self.rect = .{
            .x = @divTrunc(@as(i32, @intCast(screen_w)) - @as(i32, @intCast(dialog_w)), 2),
            .y = @divTrunc(@as(i32, @intCast(screen_h)) - @as(i32, @intCast(dialog_h)), 2),
            .w = dialog_w,
            .h = dialog_h,
        };
    }

    /// Quick show for common cases
    pub fn showSimple(
        self: *ConfirmDialog,
        title: []const u8,
        message: []const u8,
        screen_w: u32,
        screen_h: u32,
    ) void {
        self.show(title, message, "Confirm", "Cancel", false, screen_w, screen_h);
    }

    /// Quick show for delete/destructive actions
    pub fn showDelete(
        self: *ConfirmDialog,
        message: []const u8,
        screen_w: u32,
        screen_h: u32,
    ) void {
        self.show("Confirm Delete", message, "Delete", "Cancel", true, screen_w, screen_h);
    }

    pub fn hide(self: *ConfirmDialog) void {
        self.visible = false;
    }

    /// Update hover states and check for clicks
    /// Returns the result of user interaction
    pub fn update(self: *ConfirmDialog, mouse_x: i32, mouse_y: i32, clicked: bool, escape_pressed: bool) ConfirmResult {
        if (!self.visible) return .none;

        // Check escape
        if (escape_pressed) {
            self.visible = false;
            return .cancelled;
        }

        // Button layout
        const btn_w: u32 = 90;
        const btn_h: u32 = 32;
        const btn_y: i32 = self.rect.y + @as(i32, @intCast(self.rect.h)) - 50;
        const btn_spacing: i32 = 12;

        // Cancel button (left)
        const cancel_x: i32 = self.rect.x + @as(i32, @intCast(self.rect.w)) - @as(i32, @intCast(btn_w * 2)) - btn_spacing - 20;
        self.cancel_hovered = mouse_x >= cancel_x and mouse_x < cancel_x + @as(i32, @intCast(btn_w)) and
            mouse_y >= btn_y and mouse_y < btn_y + @as(i32, @intCast(btn_h));

        // Confirm button (right)
        const confirm_x: i32 = cancel_x + @as(i32, @intCast(btn_w)) + btn_spacing;
        self.confirm_hovered = mouse_x >= confirm_x and mouse_x < confirm_x + @as(i32, @intCast(btn_w)) and
            mouse_y >= btn_y and mouse_y < btn_y + @as(i32, @intCast(btn_h));

        if (clicked) {
            if (self.cancel_hovered) {
                self.visible = false;
                return .cancelled;
            }
            if (self.confirm_hovered) {
                self.visible = false;
                return .confirmed;
            }
        }

        return .none;
    }

    /// Draw the dialog
    pub fn draw(self: *const ConfirmDialog, gpu: *GpuRenderer) void {
        if (!self.visible) return;

        // Dim overlay (semi-transparent background)
        // Note: proper alpha blending would need shader support
        // For now, just draw the dialog

        // Soft shadow
        gpu.drawSoftShadow(self.rect.x, self.rect.y, self.rect.w, self.rect.h, 12, 0, 8, 24, 100);

        // Dialog background
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, self.rect.h, 12, 0xFF2a2a2a);

        // Border
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, 2, 12, Colors.border);

        // Title
        const title_text = self.title[0..self.title_len];
        gpu.drawText(title_text, self.rect.x + 20, self.rect.y + 20, Colors.text);

        // Title underline
        gpu.fillRect(self.rect.x + 20, self.rect.y + 44, self.rect.w - 40, 1, Colors.border);

        // Message
        const message_text = self.message[0..self.message_len];
        gpu.drawText(message_text, self.rect.x + 20, self.rect.y + 60, Colors.text_dim);

        // Buttons
        const btn_w: u32 = 90;
        const btn_h: u32 = 32;
        const btn_y: i32 = self.rect.y + @as(i32, @intCast(self.rect.h)) - 50;
        const btn_spacing: i32 = 12;

        // Cancel button
        const cancel_x: i32 = self.rect.x + @as(i32, @intCast(self.rect.w)) - @as(i32, @intCast(btn_w * 2)) - btn_spacing - 20;
        const cancel_bg: u32 = if (self.cancel_hovered) 0xFF404040 else 0xFF353535;
        gpu.fillRoundedRect(cancel_x, btn_y, btn_w, btn_h, 6, cancel_bg);
        const cancel_text = self.cancel_text[0..self.cancel_len];
        const cancel_text_x = cancel_x + @divTrunc(@as(i32, @intCast(btn_w)) - @as(i32, @intCast(cancel_text.len * 8)), 2);
        gpu.drawText(cancel_text, cancel_text_x, btn_y + 8, Colors.text);

        // Confirm button
        const confirm_x: i32 = cancel_x + @as(i32, @intCast(btn_w)) + btn_spacing;
        const confirm_bg: u32 = if (self.is_destructive)
            (if (self.confirm_hovered) 0xFF8b3030 else 0xFF6b2020)
        else
            (if (self.confirm_hovered) 0xFF4a6040 else 0xFF3a5030);
        gpu.fillRoundedRect(confirm_x, btn_y, btn_w, btn_h, 6, confirm_bg);
        const confirm_text = self.confirm_text[0..self.confirm_len];
        const confirm_text_x = confirm_x + @divTrunc(@as(i32, @intCast(btn_w)) - @as(i32, @intCast(confirm_text.len * 8)), 2);
        const confirm_text_color: u32 = if (self.is_destructive) 0xFFff8080 else 0xFF90ff90;
        gpu.drawText(confirm_text, confirm_text_x, btn_y + 8, confirm_text_color);
    }

    /// Check if dialog is blocking input
    pub fn isBlocking(self: *const ConfirmDialog) bool {
        return self.visible;
    }
};

// === Scrollbar ===
pub const Scrollbar = struct {
    rect: Rect,
    thumb_pos: f32 = 0, // 0.0 - 1.0
    thumb_size: f32 = 0.2, // 0.0 - 1.0
    is_vertical: bool = true,
    dragging: bool = false,
    hovered: bool = false,
    drag_offset: i32 = 0,

    pub fn init(x: i32, y: i32, length: u32, is_vertical: bool) Scrollbar {
        return .{
            .rect = if (is_vertical)
                .{ .x = x, .y = y, .w = 10, .h = length }
            else
                .{ .x = x, .y = y, .w = length, .h = 10 },
            .is_vertical = is_vertical,
        };
    }

    pub fn setContentRatio(self: *Scrollbar, visible: f32, total: f32) void {
        if (total <= 0) {
            self.thumb_size = 1.0;
            return;
        }
        self.thumb_size = @min(1.0, visible / total);
    }

    pub fn setPosition(self: *Scrollbar, pos: f32) void {
        self.thumb_pos = std.math.clamp(pos, 0.0, 1.0 - self.thumb_size);
    }

    fn getThumbRect(self: *const Scrollbar) Rect {
        if (self.is_vertical) {
            const track_h = @as(f32, @floatFromInt(self.rect.h));
            const thumb_h: u32 = @intFromFloat(@max(20.0, track_h * self.thumb_size));
            const thumb_y: i32 = self.rect.y + @as(i32, @intFromFloat(track_h * self.thumb_pos));
            return .{ .x = self.rect.x, .y = thumb_y, .w = self.rect.w, .h = thumb_h };
        } else {
            const track_w = @as(f32, @floatFromInt(self.rect.w));
            const thumb_w: u32 = @intFromFloat(@max(20.0, track_w * self.thumb_size));
            const thumb_x: i32 = self.rect.x + @as(i32, @intFromFloat(track_w * self.thumb_pos));
            return .{ .x = thumb_x, .y = self.rect.y, .w = thumb_w, .h = self.rect.h };
        }
    }

    pub fn update(self: *Scrollbar, mouse_x: i32, mouse_y: i32, mouse_down: bool) bool {
        const thumb = self.getThumbRect();
        self.hovered = thumb.contains(mouse_x, mouse_y) or self.rect.contains(mouse_x, mouse_y);

        if (self.dragging) {
            if (!mouse_down) {
                self.dragging = false;
            } else {
                // Update position based on drag
                if (self.is_vertical) {
                    const track_h = @as(f32, @floatFromInt(self.rect.h));
                    const mouse_rel = @as(f32, @floatFromInt(mouse_y - self.rect.y - self.drag_offset));
                    self.thumb_pos = std.math.clamp(mouse_rel / track_h, 0.0, 1.0 - self.thumb_size);
                } else {
                    const track_w = @as(f32, @floatFromInt(self.rect.w));
                    const mouse_rel = @as(f32, @floatFromInt(mouse_x - self.rect.x - self.drag_offset));
                    self.thumb_pos = std.math.clamp(mouse_rel / track_w, 0.0, 1.0 - self.thumb_size);
                }
                return true;
            }
        } else if (mouse_down and thumb.contains(mouse_x, mouse_y)) {
            self.dragging = true;
            if (self.is_vertical) {
                self.drag_offset = mouse_y - thumb.y;
            } else {
                self.drag_offset = mouse_x - thumb.x;
            }
        }

        return false;
    }

    pub fn draw(self: *const Scrollbar, gpu: *GpuRenderer) void {
        // Track
        gpu.fillRoundedRect(self.rect.x, self.rect.y, self.rect.w, self.rect.h, 4, 0xFF1a1a1a);

        // Thumb
        const thumb = self.getThumbRect();
        const thumb_color: u32 = if (self.dragging) Colors.accent else if (self.hovered) 0xFF555555 else 0xFF404040;
        gpu.fillRoundedRect(thumb.x, thumb.y, thumb.w, thumb.h, 4, thumb_color);
    }

    pub fn getScrollPosition(self: *const Scrollbar) f32 {
        return self.thumb_pos;
    }
};
