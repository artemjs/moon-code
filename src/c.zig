const builtin = @import("builtin");

pub const c = if (builtin.os.tag == .windows)
    @cImport({
        // Windows uses pure Zig for Win32 API, no C imports needed for windowing
        // Only import OpenGL and common headers
        @cInclude("GL/gl.h");
    })
else
    @cImport({
        @cInclude("wayland-client.h");
        @cInclude("wayland-egl.h");
        @cInclude("wayland-cursor.h");
        @cInclude("xdg-shell-client-protocol.h");
        @cInclude("xdg-activation-v1-client-protocol.h");
        @cInclude("EGL/egl.h");
        @cInclude("GLES2/gl2.h");
        @cInclude("sys/mman.h");
        @cInclude("unistd.h");
        @cInclude("fcntl.h");
    });
