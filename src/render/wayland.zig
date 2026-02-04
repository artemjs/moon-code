const std = @import("std");
const c = @import("../c.zig").c;

pub const TITLEBAR_HEIGHT: u32 = 30;

pub const KeyEvent = struct {
    key: u32,
    char: ?u8,
    pressed: bool,
};

pub const MouseEvent = struct {
    x: i32,
    y: i32,
    button: u32,
    pressed: bool,
};

pub const CursorType = enum {
    default,
    text,
    pointer,
    resize_ns,
    resize_ew,
    resize_nwse,
    resize_nesw,
};

pub const Wayland = struct {
    display: *c.wl_display,
    registry: *c.wl_registry,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    xdg_wm_base: ?*c.xdg_wm_base = null,
    xdg_activation: ?*c.xdg_activation_v1 = null,
    seat: ?*c.wl_seat = null,
    keyboard: ?*c.wl_keyboard = null,
    pointer: ?*c.wl_pointer = null,
    surface: ?*c.wl_surface = null,
    xdg_surface: ?*c.xdg_surface = null,
    xdg_toplevel: ?*c.xdg_toplevel = null,
    configured: bool = false,
    running: bool = true,
    maximized: bool = false,
    fullscreen: bool = false,
    width: u32 = 1280,
    height: u32 = 800,

    // Clipboard support
    data_device_manager: ?*c.wl_data_device_manager = null,
    data_device: ?*c.wl_data_device = null,
    data_source: ?*c.wl_data_source = null,
    current_offer: ?*c.wl_data_offer = null,
    clipboard_data: [64 * 1024]u8 = undefined,
    clipboard_len: usize = 0,
    clipboard_serial: u32 = 0, // Serial for set_selection

    // Mouse
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_moved: bool = false,
    mouse_pressed: bool = false,
    last_button_serial: u32 = 0,
    pointer_enter_serial: u32 = 0,
    scroll_delta_x: i32 = 0,
    scroll_delta_y: i32 = 0,
    // Accumulators for touchpad (fixed-point)
    scroll_accum_x: i32 = 0,
    scroll_accum_y: i32 = 0,

    // Cursors
    cursor_theme: ?*c.wl_cursor_theme = null,
    cursor_surface: ?*c.wl_surface = null,
    cursor_default: ?*c.wl_cursor = null,
    cursor_text: ?*c.wl_cursor = null,
    cursor_pointer: ?*c.wl_cursor = null,
    cursor_resize_ns: ?*c.wl_cursor = null,
    cursor_resize_ew: ?*c.wl_cursor = null,
    cursor_resize_nwse: ?*c.wl_cursor = null,
    cursor_resize_nesw: ?*c.wl_cursor = null,
    current_cursor: CursorType = .default,

    // Modifiers
    shift_held: bool = false,
    ctrl_held: bool = false,

    // Events
    key_events: [32]KeyEvent = undefined,
    key_event_count: usize = 0,
    mouse_events: [32]MouseEvent = undefined,
    mouse_event_count: usize = 0,
    close_requested: bool = false,

    const Self = @This();

    pub fn init(self: *Self) !void {
        const display = c.wl_display_connect(null) orelse {
            return error.WaylandConnectionFailed;
        };

        const registry = c.wl_display_get_registry(display) orelse {
            return error.RegistryFailed;
        };

        self.display = display;
        self.registry = registry;

        _ = c.wl_registry_add_listener(registry, &registry_listener, self);
        _ = c.wl_display_roundtrip(display);

        if (self.compositor == null) return error.NoCompositor;
        if (self.shm == null) return error.NoShm;
        if (self.xdg_wm_base == null) return error.NoXdgWmBase;

        // Create data_device for clipboard
        if (self.data_device_manager != null and self.seat != null) {
            self.data_device = c.wl_data_device_manager_get_data_device(self.data_device_manager, self.seat);
            if (self.data_device != null) {
                _ = c.wl_data_device_add_listener(self.data_device, &data_device_listener, self);
            }
        }

        // Create surface
        self.surface = c.wl_compositor_create_surface(self.compositor);
        if (self.surface == null) return error.SurfaceCreationFailed;

        // Create xdg_surface
        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.xdg_wm_base, self.surface);
        if (self.xdg_surface == null) return error.XdgSurfaceFailed;

        _ = c.xdg_surface_add_listener(self.xdg_surface, &xdg_surface_listener, self);

        // Create toplevel (window)
        self.xdg_toplevel = c.xdg_surface_get_toplevel(self.xdg_surface);
        if (self.xdg_toplevel == null) return error.ToplevelFailed;

        _ = c.xdg_toplevel_add_listener(self.xdg_toplevel, &xdg_toplevel_listener, self);

        c.xdg_toplevel_set_title(self.xdg_toplevel, "Moon Code");
        c.xdg_toplevel_set_app_id(self.xdg_toplevel, "moon-code");

        c.wl_surface_commit(self.surface);
        _ = c.wl_display_roundtrip(display);

        // Initialize cursors
        self.cursor_theme = c.wl_cursor_theme_load(null, 24, self.shm);
        if (self.cursor_theme) |theme| {
            self.cursor_default = c.wl_cursor_theme_get_cursor(theme, "default");
            if (self.cursor_default == null) self.cursor_default = c.wl_cursor_theme_get_cursor(theme, "left_ptr");
            self.cursor_text = c.wl_cursor_theme_get_cursor(theme, "text");
            if (self.cursor_text == null) self.cursor_text = c.wl_cursor_theme_get_cursor(theme, "xterm");
            self.cursor_pointer = c.wl_cursor_theme_get_cursor(theme, "pointer");
            if (self.cursor_pointer == null) self.cursor_pointer = c.wl_cursor_theme_get_cursor(theme, "hand1");
            self.cursor_resize_ns = c.wl_cursor_theme_get_cursor(theme, "ns-resize");
            if (self.cursor_resize_ns == null) self.cursor_resize_ns = c.wl_cursor_theme_get_cursor(theme, "size_ver");
            self.cursor_resize_ew = c.wl_cursor_theme_get_cursor(theme, "ew-resize");
            if (self.cursor_resize_ew == null) self.cursor_resize_ew = c.wl_cursor_theme_get_cursor(theme, "size_hor");
            self.cursor_resize_nwse = c.wl_cursor_theme_get_cursor(theme, "nwse-resize");
            if (self.cursor_resize_nwse == null) self.cursor_resize_nwse = c.wl_cursor_theme_get_cursor(theme, "size_fdiag");
            self.cursor_resize_nesw = c.wl_cursor_theme_get_cursor(theme, "nesw-resize");
            if (self.cursor_resize_nesw == null) self.cursor_resize_nesw = c.wl_cursor_theme_get_cursor(theme, "size_bdiag");

            self.cursor_surface = c.wl_compositor_create_surface(self.compositor);
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.cursor_surface) |s| c.wl_surface_destroy(s);
        if (self.cursor_theme) |t| c.wl_cursor_theme_destroy(t);
        if (self.pointer) |p| c.wl_pointer_destroy(p);
        if (self.keyboard) |k| c.wl_keyboard_destroy(k);
        if (self.xdg_toplevel) |t| c.xdg_toplevel_destroy(t);
        if (self.xdg_surface) |s| c.xdg_surface_destroy(s);
        if (self.surface) |s| c.wl_surface_destroy(s);
        c.wl_display_disconnect(self.display);
    }

    pub fn setCursor(self: *Self, cursor_type: CursorType) void {
        if (self.current_cursor == cursor_type) return;
        self.current_cursor = cursor_type;

        const cursor = switch (cursor_type) {
            .default => self.cursor_default,
            .text => self.cursor_text,
            .pointer => self.cursor_pointer,
            .resize_ns => self.cursor_resize_ns,
            .resize_ew => self.cursor_resize_ew,
            .resize_nwse => self.cursor_resize_nwse,
            .resize_nesw => self.cursor_resize_nesw,
        } orelse self.cursor_default;

        if (cursor) |cur| {
            const image = cur.*.images[0];
            const buffer = c.wl_cursor_image_get_buffer(image);

            if (self.cursor_surface) |surface| {
                c.wl_pointer_set_cursor(self.pointer, self.pointer_enter_serial, surface, @intCast(image.*.hotspot_x), @intCast(image.*.hotspot_y));
                c.wl_surface_attach(surface, buffer, 0, 0);
                c.wl_surface_damage(surface, 0, 0, @intCast(image.*.width), @intCast(image.*.height));
                c.wl_surface_commit(surface);
            }
        }
    }

    pub fn dispatch(self: *Self) bool {
        // Do NOT clear events here - main will clear after processing
        if (c.wl_display_dispatch(self.display) == -1) {
            return false;
        }
        return self.running;
    }

    pub fn pollKeyEvents(self: *Self) []KeyEvent {
        return self.key_events[0..self.key_event_count];
    }

    pub fn pollMouseEvents(self: *Self) []MouseEvent {
        return self.mouse_events[0..self.mouse_event_count];
    }

    pub fn clearEvents(self: *Self) void {
        self.key_event_count = 0;
        self.mouse_event_count = 0;
    }

    pub fn startMove(self: *Self) void {
        if (self.seat) |seat| {
            c.xdg_toplevel_move(self.xdg_toplevel, seat, self.last_button_serial);
        }
    }

    pub fn minimize(self: *Self) void {
        c.xdg_toplevel_set_minimized(self.xdg_toplevel);
    }

    pub fn toggleMaximize(self: *Self) void {
        if (self.maximized) {
            c.xdg_toplevel_unset_maximized(self.xdg_toplevel);
        } else {
            c.xdg_toplevel_set_maximized(self.xdg_toplevel);
        }
        self.maximized = !self.maximized;
    }

    pub fn toggleFullscreen(self: *Self) void {
        if (self.fullscreen) {
            c.xdg_toplevel_unset_fullscreen(self.xdg_toplevel);
        } else {
            c.xdg_toplevel_set_fullscreen(self.xdg_toplevel, null);
        }
        self.fullscreen = !self.fullscreen;
    }

    pub fn startResize(self: *Self, edge: u32) void {
        if (self.seat) |seat| {
            c.xdg_toplevel_resize(self.xdg_toplevel, seat, self.last_button_serial, edge);
        }
    }

    /// Copies data to the system clipboard
    pub fn copyToClipboard(self: *Self, data: []const u8) void {
        if (self.data_device_manager == null or self.data_device == null) return;

        // Save data
        const len = @min(data.len, self.clipboard_data.len);
        @memcpy(self.clipboard_data[0..len], data[0..len]);
        self.clipboard_len = len;

        // Destroy old source
        if (self.data_source != null) {
            c.wl_data_source_destroy(self.data_source);
        }

        // Create new data source
        self.data_source = c.wl_data_device_manager_create_data_source(self.data_device_manager);
        if (self.data_source == null) return;

        _ = c.wl_data_source_add_listener(self.data_source, &data_source_listener, self);
        c.wl_data_source_offer(self.data_source, "text/plain;charset=utf-8");
        c.wl_data_source_offer(self.data_source, "text/plain");
        c.wl_data_source_offer(self.data_source, "UTF8_STRING");
        c.wl_data_source_offer(self.data_source, "STRING");

        // Set selection
        c.wl_data_device_set_selection(self.data_device, self.data_source, self.clipboard_serial);
    }

    /// Pastes data from the system clipboard
    pub fn pasteFromClipboard(self: *Self, buffer: []u8) ?[]u8 {
        if (self.current_offer == null) return null;

        // Create pipe to receive data
        const pipe_result = std.posix.pipe2(.{}) catch return null;
        const read_fd: i32 = @intCast(pipe_result[0]);
        const write_fd: i32 = @intCast(pipe_result[1]);

        // Request data
        c.wl_data_offer_receive(self.current_offer, "text/plain;charset=utf-8", write_fd);
        std.posix.close(@intCast(write_fd));

        // Need roundtrip so compositor processes the request
        _ = c.wl_display_roundtrip(self.display);

        // Read data
        var total_read: usize = 0;
        while (total_read < buffer.len) {
            const n = std.posix.read(@intCast(read_fd), buffer[total_read..]) catch break;
            if (n == 0) break;
            total_read += n;
        }
        std.posix.close(@intCast(read_fd));

        if (total_read > 0) {
            return buffer[0..total_read];
        }
        return null;
    }

    /// Updates serial for clipboard (called on input events)
    pub fn updateClipboardSerial(self: *Self, serial: u32) void {
        self.clipboard_serial = serial;
    }

    fn pushKeyEvent(self: *Self, event: KeyEvent) void {
        if (self.key_event_count < self.key_events.len) {
            self.key_events[self.key_event_count] = event;
            self.key_event_count += 1;
        }
    }

    fn pushMouseEvent(self: *Self, event: MouseEvent) void {
        if (self.mouse_event_count < self.mouse_events.len) {
            self.mouse_events[self.mouse_event_count] = event;
            self.mouse_event_count += 1;
        }
    }

    // Registry listener
    const registry_listener = c.wl_registry_listener{
        .global = registryGlobal,
        .global_remove = registryGlobalRemove,
    };

    fn registryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const iface = std.mem.span(interface);

        if (std.mem.eql(u8, iface, "wl_compositor")) {
            self.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, @min(version, 4)));
        } else if (std.mem.eql(u8, iface, "wl_shm")) {
            self.shm = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_shm_interface, 1));
        } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
            self.xdg_wm_base = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, 1));
            _ = c.xdg_wm_base_add_listener(self.xdg_wm_base, &xdg_wm_base_listener, self);
        } else if (std.mem.eql(u8, iface, "wl_seat")) {
            // Version 1 - minimal, without new features
            self.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, 1));
            _ = c.wl_seat_add_listener(self.seat, &seat_listener, self);
        } else if (std.mem.eql(u8, iface, "xdg_activation_v1")) {
            self.xdg_activation = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_activation_v1_interface, 1));
        } else if (std.mem.eql(u8, iface, "wl_data_device_manager")) {
            self.data_device_manager = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_data_device_manager_interface, @min(version, 3)));
        }
    }

    fn registryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}

    // Seat listener
    const seat_listener = c.wl_seat_listener{
        .capabilities = seatCapabilities,
        .name = seatName,
    };

    fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, caps: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));

        if ((caps & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0 and self.keyboard == null) {
            self.keyboard = c.wl_seat_get_keyboard(seat);
            _ = c.wl_keyboard_add_listener(self.keyboard, &keyboard_listener, self);
        }

        if ((caps & c.WL_SEAT_CAPABILITY_POINTER) != 0 and self.pointer == null) {
            self.pointer = c.wl_seat_get_pointer(seat);
            _ = c.wl_pointer_add_listener(self.pointer, &pointer_listener, self);
        }
    }

    fn seatName(_: ?*anyopaque, _: ?*c.wl_seat, _: [*c]const u8) callconv(.c) void {}

    // Data device listener (clipboard)
    const data_device_listener = c.wl_data_device_listener{
        .data_offer = dataDeviceOffer,
        .enter = dataDeviceEnter,
        .leave = dataDeviceLeave,
        .motion = dataDeviceMotion,
        .drop = dataDeviceDrop,
        .selection = dataDeviceSelection,
    };

    fn dataDeviceOffer(data: ?*anyopaque, _: ?*c.wl_data_device, offer: ?*c.wl_data_offer) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        // Save new offer
        if (offer != null) {
            _ = c.wl_data_offer_add_listener(offer, &data_offer_listener, self);
        }
    }

    fn dataDeviceEnter(_: ?*anyopaque, _: ?*c.wl_data_device, _: u32, _: ?*c.wl_surface, _: i32, _: i32, _: ?*c.wl_data_offer) callconv(.c) void {}
    fn dataDeviceLeave(_: ?*anyopaque, _: ?*c.wl_data_device) callconv(.c) void {}
    fn dataDeviceMotion(_: ?*anyopaque, _: ?*c.wl_data_device, _: u32, _: i32, _: i32) callconv(.c) void {}
    fn dataDeviceDrop(_: ?*anyopaque, _: ?*c.wl_data_device) callconv(.c) void {}

    fn dataDeviceSelection(data: ?*anyopaque, _: ?*c.wl_data_device, offer: ?*c.wl_data_offer) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        // Save current offer for selection (clipboard)
        if (self.current_offer != null) {
            c.wl_data_offer_destroy(self.current_offer);
        }
        self.current_offer = offer;
    }

    // Data offer listener
    const data_offer_listener = c.wl_data_offer_listener{
        .offer = dataOfferOffer,
        .source_actions = dataOfferSourceActions,
        .action = dataOfferAction,
    };

    fn dataOfferOffer(_: ?*anyopaque, _: ?*c.wl_data_offer, _: [*c]const u8) callconv(.c) void {
        // Reports available mime type
    }
    fn dataOfferSourceActions(_: ?*anyopaque, _: ?*c.wl_data_offer, _: u32) callconv(.c) void {}
    fn dataOfferAction(_: ?*anyopaque, _: ?*c.wl_data_offer, _: u32) callconv(.c) void {}

    // Data source listener (for copy)
    const data_source_listener = c.wl_data_source_listener{
        .target = dataSourceTarget,
        .send = dataSourceSend,
        .cancelled = dataSourceCancelled,
        .dnd_drop_performed = dataSourceDndDropPerformed,
        .dnd_finished = dataSourceDndFinished,
        .action = dataSourceAction,
    };

    fn dataSourceTarget(_: ?*anyopaque, _: ?*c.wl_data_source, _: [*c]const u8) callconv(.c) void {}
    fn dataSourceSend(data: ?*anyopaque, _: ?*c.wl_data_source, _: [*c]const u8, fd: i32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        // Write data to fd
        if (self.clipboard_len > 0) {
            _ = std.posix.write(@intCast(fd), self.clipboard_data[0..self.clipboard_len]) catch {};
        }
        std.posix.close(@intCast(fd));
    }
    fn dataSourceCancelled(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        if (self.data_source == source) {
            c.wl_data_source_destroy(source);
            self.data_source = null;
        }
    }
    fn dataSourceDndDropPerformed(_: ?*anyopaque, _: ?*c.wl_data_source) callconv(.c) void {}
    fn dataSourceDndFinished(_: ?*anyopaque, _: ?*c.wl_data_source) callconv(.c) void {}
    fn dataSourceAction(_: ?*anyopaque, _: ?*c.wl_data_source, _: u32) callconv(.c) void {}

    // Keyboard listener
    const keyboard_listener = c.wl_keyboard_listener{
        .keymap = keyboardKeymap,
        .enter = keyboardEnter,
        .leave = keyboardLeave,
        .key = keyboardKey,
        .modifiers = keyboardModifiers,
        .repeat_info = keyboardRepeatInfo,
    };

    fn keyboardKeymap(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: i32, _: u32) callconv(.c) void {}
    fn keyboardEnter(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface, _: ?*c.wl_array) callconv(.c) void {}
    fn keyboardLeave(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface) callconv(.c) void {}

    fn keyboardKey(data: ?*anyopaque, _: ?*c.wl_keyboard, serial: u32, _: u32, key: u32, state: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const pressed = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;
        const char: ?u8 = keyToChar(key, self.shift_held);

        // Save serial for clipboard operations
        self.clipboard_serial = serial;

        self.pushKeyEvent(.{
            .key = key,
            .char = char,
            .pressed = pressed,
        });
    }

    fn keyboardModifiers(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, mods_depressed: u32, _: u32, _: u32, _: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        // Shift = bit 0, Ctrl = bit 2 in standard layout
        self.shift_held = (mods_depressed & 1) != 0;
        self.ctrl_held = (mods_depressed & 4) != 0;
    }
    fn keyboardRepeatInfo(_: ?*anyopaque, _: ?*c.wl_keyboard, _: i32, _: i32) callconv(.c) void {}

    // Pointer listener - only basic handlers (version 1)
    const pointer_listener = c.wl_pointer_listener{
        .enter = pointerEnter,
        .leave = pointerLeave,
        .motion = pointerMotion,
        .button = pointerButton,
        .axis = pointerAxis,
    };

    fn pointerEnter(data: ?*anyopaque, _: ?*c.wl_pointer, serial: u32, _: ?*c.wl_surface, x: i32, y: i32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.mouse_x = @divTrunc(x, 256);
        self.mouse_y = @divTrunc(y, 256);
        self.pointer_enter_serial = serial;
        // Set default cursor on enter
        self.current_cursor = .default;
        self.setCursor(.default);
    }

    fn pointerLeave(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: ?*c.wl_surface) callconv(.c) void {}

    fn pointerMotion(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, x: i32, y: i32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.mouse_x = @divTrunc(x, 256);
        self.mouse_y = @divTrunc(y, 256);
        self.mouse_moved = true;
    }

    fn pointerButton(data: ?*anyopaque, _: ?*c.wl_pointer, serial: u32, _: u32, button: u32, state: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const pressed = state == c.WL_POINTER_BUTTON_STATE_PRESSED;

        self.last_button_serial = serial;

        // Track left mouse button state
        if (button == BTN_LEFT) {
            self.mouse_pressed = pressed;
        }

        self.pushMouseEvent(.{
            .x = self.mouse_x,
            .y = self.mouse_y,
            .button = button,
            .pressed = pressed,
        });
    }

    fn pointerAxis(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, axis: u32, value: i32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        // axis: 0 = vertical, 1 = horizontal
        // value: wl_fixed_t (24.8 fixed point)
        // For touchpad accumulate values to not lose small deltas
        const scale: i32 = 3; // sensitivity

        if (axis == 0) {
            // Vertical scroll
            self.scroll_accum_y += value;
            // Convert when enough accumulated (256 = 1 logical pixel)
            const pixels = @divTrunc(self.scroll_accum_y, 256);
            if (pixels != 0) {
                if (self.shift_held) {
                    self.scroll_delta_x += pixels * scale;
                } else {
                    self.scroll_delta_y += pixels * scale;
                }
                self.scroll_accum_y -= pixels * 256;
            }
        } else {
            // Horizontal scroll
            self.scroll_accum_x += value;
            const pixels = @divTrunc(self.scroll_accum_x, 256);
            if (pixels != 0) {
                self.scroll_delta_x += pixels * scale;
                self.scroll_accum_x -= pixels * 256;
            }
        }
    }

    // XDG WM Base listener
    const xdg_wm_base_listener = c.xdg_wm_base_listener{
        .ping = xdgWmBasePing,
    };

    fn xdgWmBasePing(_: ?*anyopaque, wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
        c.xdg_wm_base_pong(wm_base, serial);
    }

    // XDG Surface listener
    const xdg_surface_listener = c.xdg_surface_listener{
        .configure = xdgSurfaceConfigure,
    };

    fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        c.xdg_surface_ack_configure(xdg_surface, serial);
        if (!self.configured) {
            self.configured = true;
            // Request focus on first configuration
            self.requestFocus();
        }
    }

    pub fn requestFocus(self: *Self) void {
        if (self.xdg_activation == null or self.surface == null) return;

        const token = c.xdg_activation_v1_get_activation_token(self.xdg_activation);
        if (token == null) return;

        _ = c.xdg_activation_token_v1_add_listener(token, &activation_token_listener, self);
        c.xdg_activation_token_v1_set_surface(token, self.surface);
        c.xdg_activation_token_v1_commit(token);
    }

    const activation_token_listener = c.xdg_activation_token_v1_listener{
        .done = activationTokenDone,
    };

    fn activationTokenDone(data: ?*anyopaque, token: ?*c.xdg_activation_token_v1, token_str: [*c]const u8) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        if (self.xdg_activation != null and self.surface != null) {
            c.xdg_activation_v1_activate(self.xdg_activation, token_str, self.surface);
        }
        c.xdg_activation_token_v1_destroy(token);
    }

    // XDG Toplevel listener
    const xdg_toplevel_listener = c.xdg_toplevel_listener{
        .configure = xdgToplevelConfigure,
        .close = xdgToplevelClose,
    };

    fn xdgToplevelConfigure(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32, _: ?*c.wl_array) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        if (width > 0 and height > 0) {
            self.width = @intCast(width);
            self.height = @intCast(height);
        }
    }

    fn xdgToplevelClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.running = false;
    }
};

// Simple conversion of Linux keycodes to ASCII
fn keyToChar(key: u32, shift: bool) ?u8 {
    if (shift) {
        // Shift+key - uppercase and special characters
        return switch (key) {
            // Numbers -> special chars
            2 => '!', 3 => '@', 4 => '#', 5 => '$', 6 => '%',
            7 => '^', 8 => '&', 9 => '*', 10 => '(', 11 => ')',
            // Letters -> uppercase
            16 => 'Q', 17 => 'W', 18 => 'E', 19 => 'R', 20 => 'T',
            21 => 'Y', 22 => 'U', 23 => 'I', 24 => 'O', 25 => 'P',
            30 => 'A', 31 => 'S', 32 => 'D', 33 => 'F', 34 => 'G',
            35 => 'H', 36 => 'J', 37 => 'K', 38 => 'L',
            44 => 'Z', 45 => 'X', 46 => 'C', 47 => 'V', 48 => 'B',
            49 => 'N', 50 => 'M',
            // Punctuation with shift
            12 => '_', 13 => '+', 26 => '{', 27 => '}',
            39 => ':', 40 => '"', 51 => '<', 52 => '>', 53 => '?',
            41 => '~', 43 => '|',
            57 => ' ', 28 => '\n',
            else => null,
        };
    } else {
        // Normal keys
        return switch (key) {
            2 => '1', 3 => '2', 4 => '3', 5 => '4', 6 => '5',
            7 => '6', 8 => '7', 9 => '8', 10 => '9', 11 => '0',
            16 => 'q', 17 => 'w', 18 => 'e', 19 => 'r', 20 => 't',
            21 => 'y', 22 => 'u', 23 => 'i', 24 => 'o', 25 => 'p',
            30 => 'a', 31 => 's', 32 => 'd', 33 => 'f', 34 => 'g',
            35 => 'h', 36 => 'j', 37 => 'k', 38 => 'l',
            44 => 'z', 45 => 'x', 46 => 'c', 47 => 'v', 48 => 'b',
            49 => 'n', 50 => 'm',
            57 => ' ', 28 => '\n',
            12 => '-', 13 => '=', 26 => '[', 27 => ']',
            39 => ';', 40 => '\'', 51 => ',', 52 => '.', 53 => '/',
            41 => '`', 43 => '\\',
            else => null,
        };
    }
}

// Special keys
pub const KEY_BACKSPACE: u32 = 14;
pub const KEY_TAB: u32 = 15;
pub const KEY_ENTER: u32 = 28;
pub const KEY_LEFT: u32 = 105;
pub const KEY_RIGHT: u32 = 106;
pub const KEY_UP: u32 = 103;
pub const KEY_DOWN: u32 = 108;
pub const KEY_HOME: u32 = 102;
pub const KEY_END: u32 = 107;
pub const KEY_DELETE: u32 = 111;
pub const KEY_ESC: u32 = 1;
pub const KEY_A: u32 = 30;
pub const KEY_S: u32 = 31;
pub const KEY_N: u32 = 49;
pub const KEY_W: u32 = 17;
pub const KEY_O: u32 = 24;
pub const KEY_Z: u32 = 44;
pub const KEY_Y: u32 = 21;
pub const KEY_C: u32 = 46;
pub const KEY_V: u32 = 47;
pub const KEY_X: u32 = 45;
pub const KEY_F: u32 = 33;
pub const KEY_G: u32 = 34;
pub const KEY_MINUS: u32 = 12;
pub const KEY_EQUAL: u32 = 13;  // + is Shift+= on US keyboards
pub const KEY_0: u32 = 11;      // For Ctrl+0 to reset zoom

// Function keys
pub const KEY_F1: u32 = 59;
pub const KEY_F2: u32 = 60;
pub const KEY_F3: u32 = 61;
pub const KEY_F4: u32 = 62;
pub const KEY_F5: u32 = 63;
pub const KEY_F6: u32 = 64;
pub const KEY_F7: u32 = 65;
pub const KEY_F8: u32 = 66;
pub const KEY_F9: u32 = 67;
pub const KEY_F10: u32 = 68;
pub const KEY_F11: u32 = 87;
pub const KEY_F12: u32 = 88;
pub const KEY_PAGEUP: u32 = 104;
pub const KEY_PAGEDOWN: u32 = 109;
pub const KEY_SPACE: u32 = 57;

// Mouse buttons
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;
pub const BTN_MIDDLE: u32 = 0x112;

// Resize edges (xdg_toplevel_resize_edge)
pub const RESIZE_NONE: u32 = 0;
pub const RESIZE_TOP: u32 = 1;
pub const RESIZE_BOTTOM: u32 = 2;
pub const RESIZE_LEFT: u32 = 4;
pub const RESIZE_TOP_LEFT: u32 = 5;
pub const RESIZE_BOTTOM_LEFT: u32 = 6;
pub const RESIZE_RIGHT: u32 = 8;
pub const RESIZE_TOP_RIGHT: u32 = 9;
pub const RESIZE_BOTTOM_RIGHT: u32 = 10;
