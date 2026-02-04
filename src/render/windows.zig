// Windows backend for Moon-code
// Implements same interface as wayland.zig using Win32 API + WGL/OpenGL

const std = @import("std");
const builtin = @import("builtin");

// Win32 imports
const win = struct {
    pub const HWND = *opaque {};
    pub const HDC = *opaque {};
    pub const HGLRC = *opaque {};
    pub const HINSTANCE = *opaque {};
    pub const HCURSOR = *opaque {};
    pub const HICON = *opaque {};
    pub const HBRUSH = *opaque {};
    pub const WPARAM = usize;
    pub const LPARAM = isize;
    pub const LRESULT = isize;
    pub const UINT = u32;
    pub const DWORD = u32;
    pub const BOOL = i32;
    pub const LONG = i32;
    pub const WORD = u16;
    pub const ATOM = u16;
    pub const BYTE = u8;

    pub const POINT = extern struct {
        x: LONG,
        y: LONG,
    };

    pub const RECT = extern struct {
        left: LONG,
        top: LONG,
        right: LONG,
        bottom: LONG,
    };

    pub const MSG = extern struct {
        hwnd: ?HWND,
        message: UINT,
        wParam: WPARAM,
        lParam: LPARAM,
        time: DWORD,
        pt: POINT,
    };

    pub const WNDCLASSEXW = extern struct {
        cbSize: UINT = @sizeOf(WNDCLASSEXW),
        style: UINT = 0,
        lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT,
        cbClsExtra: i32 = 0,
        cbWndExtra: i32 = 0,
        hInstance: ?HINSTANCE = null,
        hIcon: ?HICON = null,
        hCursor: ?HCURSOR = null,
        hbrBackground: ?HBRUSH = null,
        lpszMenuName: ?[*:0]const u16 = null,
        lpszClassName: [*:0]const u16,
        hIconSm: ?HICON = null,
    };

    pub const PIXELFORMATDESCRIPTOR = extern struct {
        nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
        nVersion: WORD = 1,
        dwFlags: DWORD = 0,
        iPixelType: BYTE = 0,
        cColorBits: BYTE = 0,
        cRedBits: BYTE = 0,
        cRedShift: BYTE = 0,
        cGreenBits: BYTE = 0,
        cGreenShift: BYTE = 0,
        cBlueBits: BYTE = 0,
        cBlueShift: BYTE = 0,
        cAlphaBits: BYTE = 0,
        cAlphaShift: BYTE = 0,
        cAccumBits: BYTE = 0,
        cAccumRedBits: BYTE = 0,
        cAccumGreenBits: BYTE = 0,
        cAccumBlueBits: BYTE = 0,
        cAccumAlphaBits: BYTE = 0,
        cDepthBits: BYTE = 0,
        cStencilBits: BYTE = 0,
        cAuxBuffers: BYTE = 0,
        iLayerType: BYTE = 0,
        bReserved: BYTE = 0,
        dwLayerMask: DWORD = 0,
        dwVisibleMask: DWORD = 0,
        dwDamageMask: DWORD = 0,
    };

    // Window styles
    pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
    pub const WS_VISIBLE: DWORD = 0x10000000;
    pub const WS_POPUP: DWORD = 0x80000000;
    pub const WS_MAXIMIZE: DWORD = 0x01000000;
    pub const WS_MINIMIZE: DWORD = 0x20000000;

    pub const WS_EX_APPWINDOW: DWORD = 0x00040000;

    // Window messages
    pub const WM_DESTROY: UINT = 0x0002;
    pub const WM_SIZE: UINT = 0x0005;
    pub const WM_CLOSE: UINT = 0x0010;
    pub const WM_QUIT: UINT = 0x0012;
    pub const WM_KEYDOWN: UINT = 0x0100;
    pub const WM_KEYUP: UINT = 0x0101;
    pub const WM_CHAR: UINT = 0x0102;
    pub const WM_MOUSEMOVE: UINT = 0x0200;
    pub const WM_LBUTTONDOWN: UINT = 0x0201;
    pub const WM_LBUTTONUP: UINT = 0x0202;
    pub const WM_RBUTTONDOWN: UINT = 0x0204;
    pub const WM_RBUTTONUP: UINT = 0x0205;
    pub const WM_MBUTTONDOWN: UINT = 0x0207;
    pub const WM_MBUTTONUP: UINT = 0x0208;
    pub const WM_MOUSEWHEEL: UINT = 0x020A;
    pub const WM_MOUSEHWHEEL: UINT = 0x020E;
    pub const WM_SETCURSOR: UINT = 0x0020;
    pub const WM_SYSCOMMAND: UINT = 0x0112;
    pub const WM_NCHITTEST: UINT = 0x0084;
    pub const WM_NCLBUTTONDOWN: UINT = 0x00A1;

    // System commands
    pub const SC_MOVE: WPARAM = 0xF010;
    pub const SC_SIZE: WPARAM = 0xF000;
    pub const SC_MINIMIZE: WPARAM = 0xF020;
    pub const SC_MAXIMIZE: WPARAM = 0xF030;
    pub const SC_RESTORE: WPARAM = 0xF120;

    // Show window commands
    pub const SW_SHOW: i32 = 5;
    pub const SW_HIDE: i32 = 0;
    pub const SW_MINIMIZE: i32 = 6;
    pub const SW_MAXIMIZE: i32 = 3;
    pub const SW_RESTORE: i32 = 9;

    // Cursor IDs
    pub const IDC_ARROW: usize = 32512;
    pub const IDC_IBEAM: usize = 32513;
    pub const IDC_HAND: usize = 32649;
    pub const IDC_SIZENS: usize = 32645;
    pub const IDC_SIZEWE: usize = 32644;
    pub const IDC_SIZENWSE: usize = 32642;
    pub const IDC_SIZENESW: usize = 32643;

    // Virtual key codes
    pub const VK_BACK: u32 = 0x08;
    pub const VK_TAB: u32 = 0x09;
    pub const VK_RETURN: u32 = 0x0D;
    pub const VK_SHIFT: u32 = 0x10;
    pub const VK_CONTROL: u32 = 0x11;
    pub const VK_ESCAPE: u32 = 0x1B;
    pub const VK_SPACE: u32 = 0x20;
    pub const VK_PRIOR: u32 = 0x21; // Page Up
    pub const VK_NEXT: u32 = 0x22; // Page Down
    pub const VK_END: u32 = 0x23;
    pub const VK_HOME: u32 = 0x24;
    pub const VK_LEFT: u32 = 0x25;
    pub const VK_UP: u32 = 0x26;
    pub const VK_RIGHT: u32 = 0x27;
    pub const VK_DOWN: u32 = 0x28;
    pub const VK_DELETE: u32 = 0x2E;
    pub const VK_F1: u32 = 0x70;
    pub const VK_F2: u32 = 0x71;
    pub const VK_F3: u32 = 0x72;
    pub const VK_F4: u32 = 0x73;
    pub const VK_F5: u32 = 0x74;
    pub const VK_F6: u32 = 0x75;
    pub const VK_F7: u32 = 0x76;
    pub const VK_F8: u32 = 0x77;
    pub const VK_F9: u32 = 0x78;
    pub const VK_F10: u32 = 0x79;
    pub const VK_F11: u32 = 0x7A;
    pub const VK_F12: u32 = 0x7B;
    pub const VK_OEM_MINUS: u32 = 0xBD;
    pub const VK_OEM_PLUS: u32 = 0xBB;

    // Pixel format flags
    pub const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
    pub const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;
    pub const PFD_DOUBLEBUFFER: DWORD = 0x00000001;
    pub const PFD_TYPE_RGBA: BYTE = 0;
    pub const PFD_MAIN_PLANE: BYTE = 0;

    // Clipboard formats
    pub const CF_UNICODETEXT: UINT = 13;

    // GWLP indices
    pub const GWLP_STYLE: i32 = -16;
    pub const GWLP_USERDATA: i32 = -21;

    // Hit test results
    pub const HTCLIENT: LRESULT = 1;
    pub const HTCAPTION: LRESULT = 2;
    pub const HTLEFT: LRESULT = 10;
    pub const HTRIGHT: LRESULT = 11;
    pub const HTTOP: LRESULT = 12;
    pub const HTTOPLEFT: LRESULT = 13;
    pub const HTTOPRIGHT: LRESULT = 14;
    pub const HTBOTTOM: LRESULT = 15;
    pub const HTBOTTOMLEFT: LRESULT = 16;
    pub const HTBOTTOMRIGHT: LRESULT = 17;

    pub const PM_REMOVE: UINT = 0x0001;

    pub const TRUE: BOOL = 1;
    pub const FALSE: BOOL = 0;

    pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

    // External functions
    pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) ATOM;
    pub extern "user32" fn CreateWindowExW(DWORD, [*:0]const u16, [*:0]const u16, DWORD, i32, i32, i32, i32, ?HWND, ?*anyopaque, ?HINSTANCE, ?*anyopaque) callconv(.winapi) ?HWND;
    pub extern "user32" fn DestroyWindow(HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) BOOL;
    pub extern "user32" fn UpdateWindow(HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn PeekMessageW(*MSG, ?HWND, UINT, UINT, UINT) callconv(.winapi) BOOL;
    pub extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) BOOL;
    pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) LRESULT;
    pub extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
    pub extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
    pub extern "user32" fn GetDC(HWND) callconv(.winapi) ?HDC;
    pub extern "user32" fn ReleaseDC(HWND, HDC) callconv(.winapi) i32;
    pub extern "user32" fn SetCursor(HCURSOR) callconv(.winapi) ?HCURSOR;
    pub extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.winapi) ?HCURSOR;
    pub extern "user32" fn GetClientRect(HWND, *RECT) callconv(.winapi) BOOL;
    pub extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.winapi) isize;
    pub extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.winapi) isize;
    pub extern "user32" fn SetWindowPos(HWND, ?HWND, i32, i32, i32, i32, UINT) callconv(.winapi) BOOL;
    pub extern "user32" fn SendMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
    pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
    pub extern "user32" fn OpenClipboard(?HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
    pub extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
    pub extern "user32" fn SetClipboardData(UINT, ?*anyopaque) callconv(.winapi) ?*anyopaque;
    pub extern "user32" fn GetClipboardData(UINT) callconv(.winapi) ?*anyopaque;
    pub extern "user32" fn IsClipboardFormatAvailable(UINT) callconv(.winapi) BOOL;
    pub extern "user32" fn SetForegroundWindow(HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
    pub extern "user32" fn GetWindowRect(HWND, *RECT) callconv(.winapi) BOOL;

    pub extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
    pub extern "kernel32" fn GlobalAlloc(UINT, usize) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn GlobalLock(?*anyopaque) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn GlobalUnlock(?*anyopaque) callconv(.winapi) BOOL;
    pub extern "kernel32" fn GlobalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;

    pub extern "gdi32" fn ChoosePixelFormat(HDC, *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
    pub extern "gdi32" fn SetPixelFormat(HDC, i32, *const PIXELFORMATDESCRIPTOR) callconv(.winapi) BOOL;
    pub extern "gdi32" fn SwapBuffers(HDC) callconv(.winapi) BOOL;

    pub extern "opengl32" fn wglCreateContext(HDC) callconv(.winapi) ?HGLRC;
    pub extern "opengl32" fn wglDeleteContext(HGLRC) callconv(.winapi) BOOL;
    pub extern "opengl32" fn wglMakeCurrent(HDC, ?HGLRC) callconv(.winapi) BOOL;
    pub extern "opengl32" fn wglGetProcAddress([*:0]const u8) callconv(.winapi) ?*anyopaque;

    // GMEM flags
    pub const GMEM_MOVEABLE: UINT = 0x0002;

    // SetWindowPos flags
    pub const SWP_NOMOVE: UINT = 0x0002;
    pub const SWP_NOSIZE: UINT = 0x0001;
    pub const SWP_NOZORDER: UINT = 0x0004;
    pub const SWP_FRAMECHANGED: UINT = 0x0020;

    // GetSystemMetrics indices
    pub const SM_CXSCREEN: i32 = 0;
    pub const SM_CYSCREEN: i32 = 1;
};

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

// Thread-local storage for window pointer
threadlocal var g_window_ptr: ?*Windows = null;

pub const Windows = struct {
    hwnd: ?win.HWND = null,
    hdc: ?win.HDC = null,
    hglrc: ?win.HGLRC = null,
    hinstance: ?win.HINSTANCE = null,

    configured: bool = false,
    running: bool = true,
    maximized: bool = false,
    fullscreen: bool = false,
    width: u32 = 1280,
    height: u32 = 800,

    // Saved window state for fullscreen toggle
    saved_style: win.DWORD = 0,
    saved_rect: win.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },

    // Clipboard
    clipboard_data: [64 * 1024]u8 = undefined,
    clipboard_len: usize = 0,

    // Mouse
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_moved: bool = false,
    mouse_pressed: bool = false,
    scroll_delta_x: i32 = 0,
    scroll_delta_y: i32 = 0,

    // Cursors
    cursor_default: ?win.HCURSOR = null,
    cursor_text: ?win.HCURSOR = null,
    cursor_pointer: ?win.HCURSOR = null,
    cursor_resize_ns: ?win.HCURSOR = null,
    cursor_resize_ew: ?win.HCURSOR = null,
    cursor_resize_nwse: ?win.HCURSOR = null,
    cursor_resize_nesw: ?win.HCURSOR = null,
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

    // Pending char for WM_CHAR
    pending_char: ?u8 = null,

    const Self = @This();

    pub fn init(self: *Self) !void {
        self.hinstance = win.GetModuleHandleW(null);

        // Register window class
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("MoonCodeWindow");

        const wc = win.WNDCLASSEXW{
            .lpfnWndProc = windowProc,
            .hInstance = self.hinstance,
            .lpszClassName = class_name,
            .hCursor = win.LoadCursorW(null, win.IDC_ARROW),
        };

        if (win.RegisterClassExW(&wc) == 0) {
            return error.WindowClassRegistrationFailed;
        }

        // Create window
        const window_name = std.unicode.utf8ToUtf16LeStringLiteral("Moon Code");

        self.hwnd = win.CreateWindowExW(
            win.WS_EX_APPWINDOW,
            class_name,
            window_name,
            win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
            win.CW_USEDEFAULT,
            win.CW_USEDEFAULT,
            @intCast(self.width),
            @intCast(self.height),
            null,
            null,
            self.hinstance,
            null,
        );

        if (self.hwnd == null) {
            return error.WindowCreationFailed;
        }

        // Store self pointer for window proc
        _ = win.SetWindowLongPtrW(self.hwnd.?, win.GWLP_USERDATA, @intCast(@intFromPtr(self)));

        // Get DC
        self.hdc = win.GetDC(self.hwnd.?);
        if (self.hdc == null) {
            return error.GetDCFailed;
        }

        // Setup OpenGL pixel format
        const pfd = win.PIXELFORMATDESCRIPTOR{
            .dwFlags = win.PFD_DRAW_TO_WINDOW | win.PFD_SUPPORT_OPENGL | win.PFD_DOUBLEBUFFER,
            .iPixelType = win.PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .iLayerType = win.PFD_MAIN_PLANE,
        };

        const pixel_format = win.ChoosePixelFormat(self.hdc.?, &pfd);
        if (pixel_format == 0) {
            return error.ChoosePixelFormatFailed;
        }

        if (win.SetPixelFormat(self.hdc.?, pixel_format, &pfd) == win.FALSE) {
            return error.SetPixelFormatFailed;
        }

        // Create OpenGL context
        self.hglrc = win.wglCreateContext(self.hdc.?);
        if (self.hglrc == null) {
            return error.WGLContextCreationFailed;
        }

        if (win.wglMakeCurrent(self.hdc.?, self.hglrc.?) == win.FALSE) {
            return error.WGLMakeCurrentFailed;
        }

        // Load cursors
        self.cursor_default = win.LoadCursorW(null, win.IDC_ARROW);
        self.cursor_text = win.LoadCursorW(null, win.IDC_IBEAM);
        self.cursor_pointer = win.LoadCursorW(null, win.IDC_HAND);
        self.cursor_resize_ns = win.LoadCursorW(null, win.IDC_SIZENS);
        self.cursor_resize_ew = win.LoadCursorW(null, win.IDC_SIZEWE);
        self.cursor_resize_nwse = win.LoadCursorW(null, win.IDC_SIZENWSE);
        self.cursor_resize_nesw = win.LoadCursorW(null, win.IDC_SIZENESW);

        // Update client rect
        var rect: win.RECT = undefined;
        if (win.GetClientRect(self.hwnd.?, &rect) == win.TRUE) {
            self.width = @intCast(rect.right - rect.left);
            self.height = @intCast(rect.bottom - rect.top);
        }

        _ = win.ShowWindow(self.hwnd.?, win.SW_SHOW);
        _ = win.UpdateWindow(self.hwnd.?);

        self.configured = true;
    }

    pub fn deinit(self: *Self) void {
        if (self.hglrc) |ctx| {
            _ = win.wglMakeCurrent(null, null);
            _ = win.wglDeleteContext(ctx);
        }
        if (self.hdc) |dc| {
            if (self.hwnd) |wnd| {
                _ = win.ReleaseDC(wnd, dc);
            }
        }
        if (self.hwnd) |wnd| {
            _ = win.DestroyWindow(wnd);
        }
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
        };

        if (cursor) |c| {
            _ = win.SetCursor(c);
        }
    }

    pub fn dispatch(self: *Self) bool {
        // Set thread-local pointer for window proc
        g_window_ptr = self;
        defer g_window_ptr = null;

        var msg: win.MSG = undefined;
        while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) == win.TRUE) {
            if (msg.message == win.WM_QUIT) {
                self.running = false;
                return false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageW(&msg);
        }

        return self.running and !self.close_requested;
    }

    pub fn swapBuffers(self: *Self) void {
        if (self.hdc) |dc| {
            _ = win.SwapBuffers(dc);
        }
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
        if (self.hwnd) |wnd| {
            _ = win.ReleaseCapture();
            _ = win.SendMessageW(wnd, win.WM_SYSCOMMAND, win.SC_MOVE | 0x0002, 0);
        }
    }

    pub fn minimize(self: *Self) void {
        if (self.hwnd) |wnd| {
            _ = win.ShowWindow(wnd, win.SW_MINIMIZE);
        }
    }

    pub fn toggleMaximize(self: *Self) void {
        if (self.hwnd) |wnd| {
            if (self.maximized) {
                _ = win.ShowWindow(wnd, win.SW_RESTORE);
                self.maximized = false;
            } else {
                _ = win.ShowWindow(wnd, win.SW_MAXIMIZE);
                self.maximized = true;
            }
        }
    }

    pub fn toggleFullscreen(self: *Self) void {
        if (self.hwnd == null) return;
        const wnd = self.hwnd.?;

        if (self.fullscreen) {
            // Restore windowed mode
            _ = win.SetWindowLongPtrW(wnd, win.GWLP_STYLE, @intCast(self.saved_style));
            _ = win.SetWindowPos(
                wnd,
                null,
                self.saved_rect.left,
                self.saved_rect.top,
                self.saved_rect.right - self.saved_rect.left,
                self.saved_rect.bottom - self.saved_rect.top,
                win.SWP_NOZORDER | win.SWP_FRAMECHANGED,
            );
            self.fullscreen = false;
        } else {
            // Save current state
            self.saved_style = @intCast(win.GetWindowLongPtrW(wnd, win.GWLP_STYLE));
            _ = win.GetWindowRect(wnd, &self.saved_rect);

            // Set fullscreen
            const screen_width = win.GetSystemMetrics(win.SM_CXSCREEN);
            const screen_height = win.GetSystemMetrics(win.SM_CYSCREEN);

            _ = win.SetWindowLongPtrW(wnd, win.GWLP_STYLE, @intCast(win.WS_POPUP | win.WS_VISIBLE));
            _ = win.SetWindowPos(wnd, null, 0, 0, screen_width, screen_height, win.SWP_NOZORDER | win.SWP_FRAMECHANGED);

            self.fullscreen = true;
        }
    }

    pub fn startResize(self: *Self, edge: u32) void {
        if (self.hwnd) |wnd| {
            _ = win.ReleaseCapture();
            // edge mapping: 1=left, 2=right, 4=top, 8=bottom
            const sc_edge: win.WPARAM = switch (edge) {
                1 => win.SC_SIZE | 1, // WMSZ_LEFT
                2 => win.SC_SIZE | 2, // WMSZ_RIGHT
                4 => win.SC_SIZE | 3, // WMSZ_TOP
                8 => win.SC_SIZE | 6, // WMSZ_BOTTOM
                5 => win.SC_SIZE | 4, // WMSZ_TOPLEFT
                6 => win.SC_SIZE | 5, // WMSZ_TOPRIGHT
                9 => win.SC_SIZE | 7, // WMSZ_BOTTOMLEFT
                10 => win.SC_SIZE | 8, // WMSZ_BOTTOMRIGHT
                else => win.SC_SIZE,
            };
            _ = win.SendMessageW(wnd, win.WM_SYSCOMMAND, sc_edge, 0);
        }
    }

    pub fn copyToClipboard(self: *Self, data: []const u8) void {
        if (self.hwnd == null) return;

        if (win.OpenClipboard(self.hwnd) == win.FALSE) return;
        defer _ = win.CloseClipboard();

        _ = win.EmptyClipboard();

        // Allocate global memory for UTF-16 string
        const utf16_len = (data.len + 1) * 2;
        const hmem = win.GlobalAlloc(win.GMEM_MOVEABLE, utf16_len);
        if (hmem == null) return;

        const ptr = win.GlobalLock(hmem);
        if (ptr == null) {
            _ = win.GlobalFree(hmem);
            return;
        }

        // Convert UTF-8 to UTF-16 (simple ASCII copy for now)
        const dest: [*]u16 = @ptrCast(@alignCast(ptr));
        for (data, 0..) |byte, i| {
            dest[i] = byte;
        }
        dest[data.len] = 0;

        _ = win.GlobalUnlock(hmem);
        _ = win.SetClipboardData(win.CF_UNICODETEXT, hmem);
    }

    pub fn pasteFromClipboard(self: *Self, buffer: []u8) ?[]u8 {
        if (self.hwnd == null) return null;

        if (win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) == win.FALSE) return null;
        if (win.OpenClipboard(self.hwnd) == win.FALSE) return null;
        defer _ = win.CloseClipboard();

        const hmem = win.GetClipboardData(win.CF_UNICODETEXT);
        if (hmem == null) return null;

        const ptr = win.GlobalLock(hmem);
        if (ptr == null) return null;
        defer _ = win.GlobalUnlock(hmem);

        // Convert UTF-16 to UTF-8 (simple ASCII copy for now)
        const src: [*]const u16 = @ptrCast(@alignCast(ptr));
        var len: usize = 0;
        while (src[len] != 0 and len < buffer.len) : (len += 1) {
            const ch = src[len];
            if (ch < 128) {
                buffer[len] = @intCast(ch);
            } else {
                buffer[len] = '?';
            }
        }

        return buffer[0..len];
    }

    pub fn updateClipboardSerial(_: *Self, _: u32) void {
        // Not needed on Windows
    }

    pub fn requestFocus(self: *Self) void {
        if (self.hwnd) |wnd| {
            _ = win.SetForegroundWindow(wnd);
        }
    }

    // Add key event helper
    fn addKeyEvent(self: *Self, key: u32, char: ?u8, pressed: bool) void {
        if (self.key_event_count < self.key_events.len) {
            self.key_events[self.key_event_count] = .{
                .key = key,
                .char = char,
                .pressed = pressed,
            };
            self.key_event_count += 1;
        }
    }

    // Add mouse event helper
    fn addMouseEvent(self: *Self, x: i32, y: i32, button: u32, pressed: bool) void {
        if (self.mouse_event_count < self.mouse_events.len) {
            self.mouse_events[self.mouse_event_count] = .{
                .x = x,
                .y = y,
                .button = button,
                .pressed = pressed,
            };
            self.mouse_event_count += 1;
        }
    }
};

// Window procedure
fn windowProc(hwnd: win.HWND, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.winapi) win.LRESULT {
    // Get self pointer
    const self_ptr = win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA);
    const self: ?*Windows = if (self_ptr != 0) @ptrFromInt(@as(usize, @intCast(self_ptr))) else g_window_ptr;

    if (self == null) {
        return win.DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    const w = self.?;

    switch (msg) {
        win.WM_CLOSE => {
            w.close_requested = true;
            return 0;
        },
        win.WM_DESTROY => {
            win.PostQuitMessage(0);
            return 0;
        },
        win.WM_SIZE => {
            const width: u32 = @intCast(lParam & 0xFFFF);
            const height: u32 = @intCast((lParam >> 16) & 0xFFFF);
            if (width > 0 and height > 0) {
                w.width = width;
                w.height = height;
            }
            return 0;
        },
        win.WM_KEYDOWN => {
            const vk: u32 = @intCast(wParam);
            const key = vkToKey(vk);

            // Track modifiers
            if (vk == win.VK_SHIFT) w.shift_held = true;
            if (vk == win.VK_CONTROL) w.ctrl_held = true;

            w.addKeyEvent(key, null, true);
            return 0;
        },
        win.WM_KEYUP => {
            const vk: u32 = @intCast(wParam);
            const key = vkToKey(vk);

            // Track modifiers
            if (vk == win.VK_SHIFT) w.shift_held = false;
            if (vk == win.VK_CONTROL) w.ctrl_held = false;

            w.addKeyEvent(key, null, false);
            return 0;
        },
        win.WM_CHAR => {
            // Character input
            const char: u8 = if (wParam < 256) @intCast(wParam) else 0;
            if (char >= 32 and char < 127) {
                // Add as a key event with char
                if (w.key_event_count > 0) {
                    // Update last key event with char
                    w.key_events[w.key_event_count - 1].char = char;
                }
            }
            return 0;
        },
        win.WM_MOUSEMOVE => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.mouse_x = x;
            w.mouse_y = y;
            w.mouse_moved = true;
            return 0;
        },
        win.WM_LBUTTONDOWN => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.mouse_pressed = true;
            w.addMouseEvent(x, y, 1, true);
            return 0;
        },
        win.WM_LBUTTONUP => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.mouse_pressed = false;
            w.addMouseEvent(x, y, 1, false);
            return 0;
        },
        win.WM_RBUTTONDOWN => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.addMouseEvent(x, y, 3, true);
            return 0;
        },
        win.WM_RBUTTONUP => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.addMouseEvent(x, y, 3, false);
            return 0;
        },
        win.WM_MBUTTONDOWN => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.addMouseEvent(x, y, 2, true);
            return 0;
        },
        win.WM_MBUTTONUP => {
            const x: i32 = @as(i16, @bitCast(@as(u16, @intCast(lParam & 0xFFFF))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @intCast((lParam >> 16) & 0xFFFF))));
            w.addMouseEvent(x, y, 2, false);
            return 0;
        },
        win.WM_MOUSEWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @intCast((wParam >> 16) & 0xFFFF)));
            w.scroll_delta_y = @divTrunc(delta, 120) * 3; // 3 lines per notch
            return 0;
        },
        win.WM_MOUSEHWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @intCast((wParam >> 16) & 0xFFFF)));
            w.scroll_delta_x = @divTrunc(delta, 120) * 3;
            return 0;
        },
        win.WM_SETCURSOR => {
            if ((lParam & 0xFFFF) == win.HTCLIENT) {
                const cursor = switch (w.current_cursor) {
                    .default => w.cursor_default,
                    .text => w.cursor_text,
                    .pointer => w.cursor_pointer,
                    .resize_ns => w.cursor_resize_ns,
                    .resize_ew => w.cursor_resize_ew,
                    .resize_nwse => w.cursor_resize_nwse,
                    .resize_nesw => w.cursor_resize_nesw,
                };
                if (cursor) |c| {
                    _ = win.SetCursor(c);
                    return 1;
                }
            }
            return win.DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        else => {},
    }

    return win.DefWindowProcW(hwnd, msg, wParam, lParam);
}

// Convert Windows virtual key to Linux keycode (for compatibility with wayland.zig interface)
fn vkToKey(vk: u32) u32 {
    return switch (vk) {
        win.VK_BACK => KEY_BACKSPACE,
        win.VK_TAB => KEY_TAB,
        win.VK_RETURN => KEY_ENTER,
        win.VK_ESCAPE => KEY_ESC,
        win.VK_SPACE => KEY_SPACE,
        win.VK_PRIOR => KEY_PAGEUP,
        win.VK_NEXT => KEY_PAGEDOWN,
        win.VK_END => KEY_END,
        win.VK_HOME => KEY_HOME,
        win.VK_LEFT => KEY_LEFT,
        win.VK_UP => KEY_UP,
        win.VK_RIGHT => KEY_RIGHT,
        win.VK_DOWN => KEY_DOWN,
        win.VK_DELETE => KEY_DELETE,
        win.VK_F1 => KEY_F1,
        win.VK_F2 => KEY_F2,
        win.VK_F3 => KEY_F3,
        win.VK_F4 => KEY_F4,
        win.VK_F5 => KEY_F5,
        win.VK_F6 => KEY_F6,
        win.VK_F7 => KEY_F7,
        win.VK_F8 => KEY_F8,
        win.VK_F9 => KEY_F9,
        win.VK_F10 => KEY_F10,
        win.VK_F11 => KEY_F11,
        win.VK_F12 => KEY_F12,
        win.VK_OEM_MINUS => KEY_MINUS,
        win.VK_OEM_PLUS => KEY_EQUAL,
        0x30 => KEY_0, // '0'
        0x41 => KEY_A,
        0x43 => KEY_C,
        0x46 => KEY_F,
        0x47 => KEY_G,
        0x4E => KEY_N,
        0x4F => KEY_O,
        0x53 => KEY_S,
        0x56 => KEY_V,
        0x57 => KEY_W,
        0x58 => KEY_X,
        0x59 => KEY_Y,
        0x5A => KEY_Z,
        else => vk, // Pass through unknown keys
    };
}

// Key constants (same as wayland.zig - Linux keycodes)
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
pub const KEY_EQUAL: u32 = 13;
pub const KEY_0: u32 = 11;

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
