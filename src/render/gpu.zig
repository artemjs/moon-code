const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;
const stb = @cImport({
    @cInclude("stb_truetype.h");
});

// Platform-specific imports
const is_windows = builtin.os.tag == .windows;
const windows = if (is_windows) @import("windows.zig") else struct {};

pub const GpuRenderer = struct {
    const MAX_BATCH_CHARS = 4096;

    // Platform-specific context (only used on Linux)
    egl_display: if (is_windows) void else c.EGLDisplay = if (is_windows) {} else undefined,
    egl_context: if (is_windows) void else c.EGLContext = if (is_windows) {} else undefined,
    egl_surface: if (is_windows) void else c.EGLSurface = if (is_windows) {} else undefined,
    egl_window: if (is_windows) void else *c.wl_egl_window = if (is_windows) {} else undefined,
    // Windows-specific: store platform pointer for swap
    win_platform: if (is_windows) ?*windows.Windows else void = if (is_windows) null else {},
    width: u32,
    height: u32,

    // Shaders for rectangles
    rect_program: c.GLuint,
    rect_pos_loc: c.GLint,
    rect_color_loc: c.GLint,

    // Shaders for text
    text_texture: c.GLuint = 0,
    text_program: c.GLuint = 0,
    text_pos_loc: c.GLint = 0,
    text_uv_loc: c.GLint = 0,
    text_sampler_loc: c.GLint = 0,
    text_color_loc: c.GLint = 0,

    // Shaders for RGBA textures (icons)
    tex_program: c.GLuint = 0,
    tex_pos_loc: c.GLint = 0,
    tex_uv_loc: c.GLint = 0,
    tex_sampler_loc: c.GLint = 0,

    // Shaders for soft shadows (SDF)
    shadow_program: c.GLuint = 0,
    shadow_pos_loc: c.GLint = 0,
    shadow_rect_loc: c.GLint = 0,
    shadow_params_loc: c.GLint = 0, // radius, blur, intensity
    shadow_bg_loc: c.GLint = 0, // background color
    shadow_res_loc: c.GLint = 0, // resolution

    // Shaders for glow effect
    glow_program: c.GLuint = 0,
    glow_pos_loc: c.GLint = 0,
    glow_rect_loc: c.GLint = 0,
    glow_params_loc: c.GLint = 0,
    glow_color_loc: c.GLint = 0,
    glow_res_loc: c.GLint = 0,

    // Font atlas (code font)
    font_atlas_texture: c.GLuint = 0,
    atlas_width: u32 = 0,
    atlas_height: u32 = 0,
    glyph_uvs: [1280]GlyphUV = [_]GlyphUV{.{}} ** 1280, // ASCII + Cyrillic (0x0000-0x04FF)
    font_char_width: u32 = 0,
    font_char_height: u32 = 0,
    font_ascent: i32 = 0,

    // UI Font atlas (light font for menus, etc)
    ui_font_texture: c.GLuint = 0,
    ui_atlas_width: u32 = 0,
    ui_atlas_height: u32 = 0,
    ui_glyph_uvs: [1280]GlyphUV = [_]GlyphUV{.{}} ** 1280, // ASCII + Cyrillic
    ui_font_char_width: u32 = 0,
    ui_font_char_height: u32 = 0,
    ui_font_ascent: i32 = 0,

    // Zoom level (1.0 = 100%)
    zoom_level: f32 = 1.0,

    // Text zoom level (1.0 = 100%)
    text_zoom: f32 = 1.0,

    // Text batching for performance (using GL_TRIANGLES - 6 vertices per char)
    text_batch_vertices: [MAX_BATCH_CHARS * 24]f32 = undefined, // 6 vertices * 4 floats per char
    text_batch_count: usize = 0,
    text_batch_color: u32 = 0xFFFFFFFF,
    text_batch_texture: c.GLuint = 0,
    base_font_size: f32 = 20.0,
    font_data_ptr: ?[*]const u8 = null,
    font_data_len: usize = 0,

    const GlyphUV = struct {
        u0: f32 = 0,
        v0: f32 = 0,
        u1: f32 = 0,
        v1: f32 = 0,
        xoff: i32 = 0,
        yoff: i32 = 0,
        w: u32 = 0,
        h: u32 = 0,
        advance: u32 = 0, // Advance width for proportional fonts
    };

    const Self = @This();

    // Windows init: OpenGL context already created by platform
    pub fn initWindows(win_platform: *windows.Windows, width: u32, height: u32) !Self {
        // Compile shaders
        const rect_program = try compileProgram(
            \\attribute vec2 a_pos;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\}
        ,
            \\precision mediump float;
            \\uniform vec4 u_color;
            \\void main() {
            \\    gl_FragColor = u_color;
            \\}
        );

        const rect_pos_loc = c.glGetAttribLocation(rect_program, "a_pos");
        const rect_color_loc = c.glGetUniformLocation(rect_program, "u_color");

        // Enable blending
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

        return Self{
            .win_platform = win_platform,
            .width = width,
            .height = height,
            .rect_program = rect_program,
            .rect_pos_loc = rect_pos_loc,
            .rect_color_loc = rect_color_loc,
        };
    }

    // Linux/Wayland init with EGL
    pub fn init(wl_surface: *c.wl_surface, wl_display: *c.wl_display, width: u32, height: u32) !Self {
        if (is_windows) {
            @compileError("Use initWindows() on Windows platform");
        }

        // EGL initialization
        const egl_display = c.eglGetDisplay(@ptrCast(wl_display));
        if (egl_display == c.EGL_NO_DISPLAY) return error.EglNoDisplay;

        var major: c.EGLint = 0;
        var minor: c.EGLint = 0;
        if (c.eglInitialize(egl_display, &major, &minor) == c.EGL_FALSE) {
            return error.EglInitFailed;
        }

        // Configuration
        const config_attribs = [_]c.EGLint{
            c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
            c.EGL_RED_SIZE,        8,
            c.EGL_GREEN_SIZE,      8,
            c.EGL_BLUE_SIZE,       8,
            c.EGL_ALPHA_SIZE,      8,
            c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES2_BIT,
            c.EGL_NONE,
        };

        var config: c.EGLConfig = undefined;
        var num_configs: c.EGLint = 0;
        if (c.eglChooseConfig(egl_display, &config_attribs, &config, 1, &num_configs) == c.EGL_FALSE or num_configs == 0) {
            return error.EglConfigFailed;
        }

        // OpenGL ES 2.0 context
        const context_attribs = [_]c.EGLint{
            c.EGL_CONTEXT_CLIENT_VERSION, 2,
            c.EGL_NONE,
        };

        const egl_context = c.eglCreateContext(egl_display, config, c.EGL_NO_CONTEXT, &context_attribs);
        if (egl_context == c.EGL_NO_CONTEXT) return error.EglContextFailed;

        // Create EGL window
        const egl_window = c.wl_egl_window_create(wl_surface, @intCast(width), @intCast(height)) orelse {
            return error.EglWindowFailed;
        };

        // Create EGL surface
        const egl_surface = c.eglCreateWindowSurface(egl_display, config, @ptrCast(egl_window), null);
        if (egl_surface == c.EGL_NO_SURFACE) return error.EglSurfaceFailed;

        // Activate context
        if (c.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) == c.EGL_FALSE) {
            return error.EglMakeCurrentFailed;
        }

        // Compile shaders
        const rect_program = try compileProgram(
            \\attribute vec2 a_pos;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\}
        ,
            \\precision mediump float;
            \\uniform vec4 u_color;
            \\void main() {
            \\    gl_FragColor = u_color;
            \\}
        );

        const rect_pos_loc = c.glGetAttribLocation(rect_program, "a_pos");
        const rect_color_loc = c.glGetUniformLocation(rect_program, "u_color");

        // Enable blending
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

        return Self{
            .egl_display = egl_display,
            .egl_context = egl_context,
            .egl_surface = egl_surface,
            .egl_window = egl_window,
            .width = width,
            .height = height,
            .rect_program = rect_program,
            .rect_pos_loc = rect_pos_loc,
            .rect_color_loc = rect_color_loc,
        };
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteProgram(self.rect_program);
        if (!is_windows) {
            _ = c.eglMakeCurrent(self.egl_display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT);
            _ = c.eglDestroySurface(self.egl_display, self.egl_surface);
            _ = c.eglDestroyContext(self.egl_display, self.egl_context);
            c.wl_egl_window_destroy(self.egl_window);
            _ = c.eglTerminate(self.egl_display);
        }
        // Windows: WGL context cleanup handled by platform
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        if (!is_windows) {
            c.wl_egl_window_resize(self.egl_window, @intCast(width), @intCast(height), 0, 0);
        }
        c.glViewport(0, 0, @intCast(width), @intCast(height));
    }

    pub fn beginFrame(self: *Self) void {
        _ = self;
    }

    pub fn endFrame(self: *Self) void {
        // Flush any remaining batched text
        self.flushTextBatch();

        if (is_windows) {
            if (self.win_platform) |platform| {
                platform.swapBuffers();
            }
        } else {
            _ = c.eglSwapBuffers(self.egl_display, self.egl_surface);
        }
    }

    pub fn clear(self: *Self, color: u32) void {
        _ = self;
        const r = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const g = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const b = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const a = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;
        c.glClearColor(r, g, b, a);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
    }

    /// Enable scissor test (clip rendering to rectangle)
    pub fn setScissor(self: *Self, x: i32, y: i32, w: u32, h: u32) void {
        c.glEnable(c.GL_SCISSOR_TEST);
        // OpenGL scissor uses coordinates from bottom-left corner
        const gl_y = @as(i32, @intCast(self.height)) - y - @as(i32, @intCast(h));
        c.glScissor(x, gl_y, @intCast(w), @intCast(h));
    }

    /// Disable scissor test
    pub fn clearScissor(_: *Self) void {
        c.glDisable(c.GL_SCISSOR_TEST);
    }

    // Draw rectangle (pixel coordinates)
    pub fn fillRect(self: *Self, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        // Convert to NDC (-1..1)
        const fx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        const vertices = [_]f32{
            fx,      fy,
            fx + fw, fy,
            fx,      fy - fh,
            fx + fw, fy - fh,
        };

        const r = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const g = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const b = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const a = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.rect_program);
        c.glUniform4f(self.rect_color_loc, r, g, b, a);
        c.glVertexAttribPointer(@intCast(self.rect_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 0, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.rect_pos_loc));
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    // Rounded rectangle (using many triangles)
    pub fn fillRoundedRect(self: *Self, x: i32, y: i32, w: u32, h: u32, radius: u32, color: u32) void {
        if (radius == 0) {
            self.fillRect(x, y, w, h, color);
            return;
        }

        const r = @min(radius, @min(w / 2, h / 2));

        // Central rectangle
        self.fillRect(x + @as(i32, @intCast(r)), y, w - r * 2, h, color);
        // Left
        self.fillRect(x, y + @as(i32, @intCast(r)), r, h - r * 2, color);
        // Right
        self.fillRect(x + @as(i32, @intCast(w - r)), y + @as(i32, @intCast(r)), r, h - r * 2, color);

        // Corners (circles)
        self.fillCircle(x + @as(i32, @intCast(r)), y + @as(i32, @intCast(r)), r, color);
        self.fillCircle(x + @as(i32, @intCast(w - r)), y + @as(i32, @intCast(r)), r, color);
        self.fillCircle(x + @as(i32, @intCast(r)), y + @as(i32, @intCast(h - r)), r, color);
        self.fillCircle(x + @as(i32, @intCast(w - r)), y + @as(i32, @intCast(h - r)), r, color);
    }

    pub fn fillCircle(self: *Self, cx: i32, cy: i32, radius: u32, color: u32) void {
        const segments: u32 = 32;
        var vertices: [segments * 2 + 4]f32 = undefined;

        const fcx = @as(f32, @floatFromInt(cx)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fcy = 1.0 - @as(f32, @floatFromInt(cy)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const frx = @as(f32, @floatFromInt(radius)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fry = @as(f32, @floatFromInt(radius)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        // Center
        vertices[0] = fcx;
        vertices[1] = fcy;

        var i: u32 = 0;
        while (i <= segments) : (i += 1) {
            const angle = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
            vertices[(i + 1) * 2] = fcx + @cos(angle) * frx;
            vertices[(i + 1) * 2 + 1] = fcy + @sin(angle) * fry;
        }

        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.rect_program);
        c.glUniform4f(self.rect_color_loc, cr, cg, cb, ca);
        c.glVertexAttribPointer(@intCast(self.rect_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 0, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.rect_pos_loc));
        c.glDrawArrays(c.GL_TRIANGLE_FAN, 0, @intCast(segments + 2));
    }

    /// Initialize shader for soft shadows
    fn initShadowShader(self: *Self) !void {
        if (self.shadow_program != 0) return;

        const vert_src =
            \\attribute vec2 a_pos;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\}
        ;

        // Shader for multiply blend - outputs darkening coefficient
        const frag_src =
            \\precision mediump float;
            \\uniform vec4 u_rect;       // x, y, w, h in pixels
            \\uniform vec3 u_params;     // radius, blur, intensity
            \\uniform vec2 u_resolution;
            \\
            \\float roundedBoxSDF(vec2 p, vec2 b, float r) {
            \\    vec2 q = abs(p) - b + vec2(r);
            \\    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            \\}
            \\
            \\void main() {
            \\    vec2 fragCoord = gl_FragCoord.xy;
            \\    fragCoord.y = u_resolution.y - fragCoord.y;
            \\
            \\    vec2 center = u_rect.xy + u_rect.zw * 0.5;
            \\    vec2 halfSize = u_rect.zw * 0.5;
            \\    float radius = u_params.x;
            \\    float blur = u_params.y;
            \\    float intensity = u_params.z;
            \\
            \\    float dist = roundedBoxSDF(fragCoord - center, halfSize, radius);
            \\
            \\    // Gaussian-like blur
            \\    float shadow = 1.0 - smoothstep(-blur, blur, dist);
            \\    shadow = shadow * shadow * intensity;
            \\
            \\    // Multiplier for darkening (1.0 = no change, 0.0 = black)
            \\    float darken = 1.0 - shadow * 0.5;
            \\    gl_FragColor = vec4(darken, darken, darken, 1.0);
            \\}
        ;

        self.shadow_program = try compileProgram(vert_src, frag_src);
        self.shadow_pos_loc = c.glGetAttribLocation(self.shadow_program, "a_pos");
        self.shadow_rect_loc = c.glGetUniformLocation(self.shadow_program, "u_rect");
        self.shadow_params_loc = c.glGetUniformLocation(self.shadow_program, "u_params");
        self.shadow_bg_loc = c.glGetUniformLocation(self.shadow_program, "u_bg_color");
        self.shadow_res_loc = c.glGetUniformLocation(self.shadow_program, "u_resolution");
    }

    /// Soft shadow with gradient blur (SDF shader)
    pub fn drawSoftShadow(self: *Self, x: i32, y: i32, w: u32, h: u32, radius: u32, offset_x: i32, offset_y: i32, blur: u32, intensity: u8) void {
        self.drawSoftShadowWithBg(x, y, w, h, radius, offset_x, offset_y, blur, intensity, 0xFF1E1E2E);
    }

    /// Soft shadow with specified background color
    pub fn drawSoftShadowWithBg(self: *Self, x: i32, y: i32, w: u32, h: u32, radius: u32, offset_x: i32, offset_y: i32, blur: u32, intensity: u8, bg_color: u32) void {
        _ = bg_color;
        self.initShadowShader() catch return;

        const blur_f: f32 = @floatFromInt(blur);
        const intensity_f: f32 = @as(f32, @floatFromInt(intensity)) / 100.0;

        const shadow_x: f32 = @as(f32, @floatFromInt(x + offset_x));
        const shadow_y: f32 = @as(f32, @floatFromInt(y + offset_y));
        const w_f: f32 = @floatFromInt(w);
        const h_f: f32 = @floatFromInt(h);
        const radius_f: f32 = @floatFromInt(radius);

        const expand = blur_f * 2.0;
        const qx = shadow_x - expand;
        const qy = shadow_y - expand;
        const qw = w_f + expand * 2.0;
        const qh = h_f + expand * 2.0;

        const width_f: f32 = @floatFromInt(self.width);
        const height_f: f32 = @floatFromInt(self.height);

        const x0 = qx / width_f * 2.0 - 1.0;
        const y0 = 1.0 - qy / height_f * 2.0;
        const x1 = (qx + qw) / width_f * 2.0 - 1.0;
        const y1 = 1.0 - (qy + qh) / height_f * 2.0;

        // Multiply blend: dst = dst * src (darkens what's under the shadow)
        c.glBlendFunc(c.GL_DST_COLOR, c.GL_ZERO);

        c.glUseProgram(self.shadow_program);

        c.glUniform4f(self.shadow_rect_loc, shadow_x, shadow_y, w_f, h_f);
        c.glUniform3f(self.shadow_params_loc, radius_f, blur_f, intensity_f);
        c.glUniform2f(self.shadow_res_loc, width_f, height_f);

        const vertices = [_]f32{
            x0, y0,
            x1, y0,
            x1, y1,
            x0, y1,
        };

        c.glVertexAttribPointer(@intCast(self.shadow_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 0, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.shadow_pos_loc));
        c.glDrawArrays(c.GL_TRIANGLE_FAN, 0, 4);

        // Restore standard blend
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    }

    /// Soft shadow with default settings
    pub fn drawDropShadow(self: *Self, x: i32, y: i32, w: u32, h: u32, radius: u32) void {
        self.drawSoftShadow(x, y, w, h, radius, 3, 4, 16, 70);
    }

    fn initGlowShader(self: *Self) !void {
        if (self.glow_program != 0) return;

        const vert_src =
            \\attribute vec2 a_pos;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\}
        ;

        // Glow shader - SDF with color
        const frag_src =
            \\precision mediump float;
            \\uniform vec4 u_rect;       // x, y, w, h
            \\uniform vec3 u_params;     // radius, blur, intensity
            \\uniform vec2 u_resolution;
            \\uniform vec3 u_color;      // RGB glow color
            \\
            \\float roundedBoxSDF(vec2 p, vec2 b, float r) {
            \\    vec2 q = abs(p) - b + vec2(r);
            \\    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            \\}
            \\
            \\void main() {
            \\    vec2 fragCoord = gl_FragCoord.xy;
            \\    fragCoord.y = u_resolution.y - fragCoord.y;
            \\
            \\    vec2 center = u_rect.xy + u_rect.zw * 0.5;
            \\    vec2 halfSize = u_rect.zw * 0.5;
            \\    float radius = u_params.x;
            \\    float blur = u_params.y;
            \\    float intensity = u_params.z;
            \\
            \\    float dist = roundedBoxSDF(fragCoord - center, halfSize, radius);
            \\
            \\    // Soft glow from edge
            \\    float glow = 1.0 - smoothstep(0.0, blur, dist);
            \\    glow = glow * glow * intensity;
            \\
            \\    gl_FragColor = vec4(u_color, glow);
            \\}
        ;

        self.glow_program = try compileProgram(vert_src, frag_src);
        self.glow_pos_loc = c.glGetAttribLocation(self.glow_program, "a_pos");
        self.glow_rect_loc = c.glGetUniformLocation(self.glow_program, "u_rect");
        self.glow_params_loc = c.glGetUniformLocation(self.glow_program, "u_params");
        self.glow_color_loc = c.glGetUniformLocation(self.glow_program, "u_color");
        self.glow_res_loc = c.glGetUniformLocation(self.glow_program, "u_resolution");
    }

    /// Small glow effect for hover (additive blend with color)
    pub fn drawGlow(self: *Self, x: i32, y: i32, w: u32, h: u32, radius: u32, color: u32, intensity: u8) void {
        self.initGlowShader() catch return;

        const blur_f: f32 = 8.0;
        const intensity_f: f32 = @as(f32, @floatFromInt(intensity)) / 100.0;

        // Glow color
        const r: f32 = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;

        const glow_x: f32 = @floatFromInt(x);
        const glow_y: f32 = @floatFromInt(y);
        const w_f: f32 = @floatFromInt(w);
        const h_f: f32 = @floatFromInt(h);
        const radius_f: f32 = @floatFromInt(radius);

        const expand = blur_f * 1.5;
        const qx = glow_x - expand;
        const qy = glow_y - expand;
        const qw = w_f + expand * 2.0;
        const qh = h_f + expand * 2.0;

        const width_f: f32 = @floatFromInt(self.width);
        const height_f: f32 = @floatFromInt(self.height);

        const x0 = qx / width_f * 2.0 - 1.0;
        const y0 = 1.0 - qy / height_f * 2.0;
        const x1 = (qx + qw) / width_f * 2.0 - 1.0;
        const y1 = 1.0 - (qy + qh) / height_f * 2.0;

        // Additive blend for glow
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE);

        c.glUseProgram(self.glow_program);

        c.glUniform4f(self.glow_rect_loc, glow_x, glow_y, w_f, h_f);
        c.glUniform3f(self.glow_params_loc, radius_f, blur_f, intensity_f);
        c.glUniform3f(self.glow_color_loc, r, g, b);
        c.glUniform2f(self.glow_res_loc, width_f, height_f);

        const vertices = [_]f32{
            x0, y0,
            x1, y0,
            x1, y1,
            x0, y1,
        };

        c.glVertexAttribPointer(@intCast(self.glow_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 0, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.glow_pos_loc));
        c.glDrawArrays(c.GL_TRIANGLE_FAN, 0, 4);

        // Restore standard blend
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    }

    pub fn initTextRendering(self: *Self) !void {
        if (self.text_program != 0) return;

        self.text_program = try compileProgram(
            \\attribute vec2 a_pos;
            \\attribute vec2 a_uv;
            \\varying vec2 v_uv;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\    v_uv = a_uv;
            \\}
        ,
            \\precision mediump float;
            \\varying vec2 v_uv;
            \\uniform sampler2D u_texture;
            \\uniform vec4 u_color;
            \\void main() {
            \\    float alpha = texture2D(u_texture, v_uv).a;
            \\    gl_FragColor = vec4(u_color.rgb, u_color.a * alpha);
            \\}
        );

        self.text_pos_loc = c.glGetAttribLocation(self.text_program, "a_pos");
        self.text_uv_loc = c.glGetAttribLocation(self.text_program, "a_uv");
        self.text_sampler_loc = c.glGetUniformLocation(self.text_program, "u_texture");
        self.text_color_loc = c.glGetUniformLocation(self.text_program, "u_color");

        c.glGenTextures(1, &self.text_texture);

        // Shader for RGBA textures (SVG icons)
        self.tex_program = try compileProgram(
            \\attribute vec2 a_pos;
            \\attribute vec2 a_uv;
            \\varying vec2 v_uv;
            \\void main() {
            \\    gl_Position = vec4(a_pos, 0.0, 1.0);
            \\    v_uv = a_uv;
            \\}
        ,
            \\precision mediump float;
            \\varying vec2 v_uv;
            \\uniform sampler2D u_texture;
            \\void main() {
            \\    gl_FragColor = texture2D(u_texture, v_uv);
            \\}
        );

        self.tex_pos_loc = c.glGetAttribLocation(self.tex_program, "a_pos");
        self.tex_uv_loc = c.glGetAttribLocation(self.tex_program, "a_uv");
        self.tex_sampler_loc = c.glGetUniformLocation(self.tex_program, "u_texture");
    }

    pub fn uploadTextBitmap(self: *Self, data: []const u8, tex_width: u32, tex_height: u32) void {
        c.glBindTexture(c.GL_TEXTURE_2D, self.text_texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, @intCast(tex_width), @intCast(tex_height), 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, data.ptr);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    }

    pub fn drawTexturedQuad(self: *Self, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        const fx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        const vertices = [_]f32{
            fx,      fy,      0.0, 0.0,
            fx + fw, fy,      1.0, 0.0,
            fx,      fy - fh, 0.0, 1.0,
            fx + fw, fy - fh, 1.0, 1.0,
        };

        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.text_program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.text_texture);
        c.glUniform1i(self.text_sampler_loc, 0);
        c.glUniform4f(self.text_color_loc, cr, cg, cb, ca);

        c.glVertexAttribPointer(@intCast(self.text_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.text_pos_loc));
        c.glVertexAttribPointer(@intCast(self.text_uv_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, @ptrFromInt(@intFromPtr(&vertices) + 8));
        c.glEnableVertexAttribArray(@intCast(self.text_uv_loc));

        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    pub fn drawLine(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, thickness: f32, color: u32) void {
        // Line as stretched rectangle
        const fx0 = @as(f32, @floatFromInt(x0));
        const fy0 = @as(f32, @floatFromInt(y0));
        const fx1 = @as(f32, @floatFromInt(x1));
        const fy1 = @as(f32, @floatFromInt(y1));

        const dx = fx1 - fx0;
        const dy = fy1 - fy0;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 0.001) return;

        const nx = -dy / len * thickness / 2.0;
        const ny = dx / len * thickness / 2.0;

        // 4 vertices of line
        const toNdcX = struct {
            fn f(px: f32, w: u32) f32 {
                return px / @as(f32, @floatFromInt(w)) * 2.0 - 1.0;
            }
        }.f;
        const toNdcY = struct {
            fn f(py: f32, h: u32) f32 {
                return 1.0 - py / @as(f32, @floatFromInt(h)) * 2.0;
            }
        }.f;

        const vertices = [_]f32{
            toNdcX(fx0 + nx, self.width), toNdcY(fy0 + ny, self.height),
            toNdcX(fx0 - nx, self.width), toNdcY(fy0 - ny, self.height),
            toNdcX(fx1 + nx, self.width), toNdcY(fy1 + ny, self.height),
            toNdcX(fx1 - nx, self.width), toNdcY(fy1 - ny, self.height),
        };

        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.rect_program);
        c.glUniform4f(self.rect_color_loc, cr, cg, cb, ca);
        c.glVertexAttribPointer(@intCast(self.rect_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 0, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.rect_pos_loc));
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    pub fn initFontAtlas(self: *Self, font_data: []const u8, pixel_height: f32) !void {
        // Save data for possible regeneration
        self.font_data_ptr = font_data.ptr;
        self.font_data_len = font_data.len;
        self.base_font_size = pixel_height;

        // Initialize text shader if not done yet
        try self.initTextRendering();

        // Initialize stb_truetype
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        // Get font metrics
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        self.font_ascent = @intFromFloat(@as(f32, @floatFromInt(ascent)) * scale);
        self.font_char_height = @intFromFloat(pixel_height);

        // Get character width
        var advance: c_int = undefined;
        var lsb: c_int = undefined;
        stb.stbtt_GetCodepointHMetrics(&info, 'M', &advance, &lsb);
        self.font_char_width = @intFromFloat(@as(f32, @floatFromInt(advance)) * scale);

        // Create atlas 1024x1024 for ASCII + Cyrillic
        self.atlas_width = 1024;
        self.atlas_height = 1024;
        var atlas_data: [1024 * 1024]u8 = [_]u8{0} ** (1024 * 1024);

        // Render characters: ASCII 32-126 + Cyrillic 0x0400-0x04FF
        var atlas_x: u32 = 1;
        var atlas_y: u32 = 1;
        var row_height: u32 = 0;

        // Character ranges for rendering
        const ranges = [_][2]u32{
            .{ 32, 127 },      // ASCII
            .{ 0x0400, 0x0500 }, // Cyrillic
        };

        for (ranges) |range| {
            var cp: u32 = range[0];
            while (cp < range[1]) : (cp += 1) {
                if (cp >= self.glyph_uvs.len) continue;

                var gw: c_int = undefined;
                var gh: c_int = undefined;
                var xoff: c_int = undefined;
                var yoff: c_int = undefined;

                const bitmap = stb.stbtt_GetCodepointBitmap(&info, 0, scale, @intCast(cp), &gw, &gh, &xoff, &yoff);

                if (bitmap != null) {
                    defer stb.stbtt_FreeBitmap(bitmap, null);

                    const glyph_w: u32 = @intCast(gw);
                    const glyph_h: u32 = @intCast(gh);

                    // Move to new row if doesn't fit
                    if (atlas_x + glyph_w + 1 >= self.atlas_width) {
                        atlas_x = 1;
                        atlas_y += row_height + 1;
                        row_height = 0;
                    }

                    if (atlas_y + glyph_h + 1 >= self.atlas_height) break;

                    // Copy glyph to atlas
                    for (0..glyph_h) |row| {
                        for (0..glyph_w) |col| {
                            const src_idx = row * glyph_w + col;
                            const dst_idx = (atlas_y + row) * self.atlas_width + (atlas_x + col);
                            atlas_data[dst_idx] = bitmap[src_idx];
                        }
                    }

                    // Save UV coordinates
                    self.glyph_uvs[cp] = .{
                        .u0 = @as(f32, @floatFromInt(atlas_x)) / @as(f32, @floatFromInt(self.atlas_width)),
                        .v0 = @as(f32, @floatFromInt(atlas_y)) / @as(f32, @floatFromInt(self.atlas_height)),
                        .u1 = @as(f32, @floatFromInt(atlas_x + glyph_w)) / @as(f32, @floatFromInt(self.atlas_width)),
                        .v1 = @as(f32, @floatFromInt(atlas_y + glyph_h)) / @as(f32, @floatFromInt(self.atlas_height)),
                        .xoff = xoff,
                        .yoff = yoff,
                        .w = glyph_w,
                        .h = glyph_h,
                    };

                    atlas_x += glyph_w + 1;
                    if (glyph_h > row_height) row_height = glyph_h;
                }
            }
        }

        // Upload atlas to GPU
        c.glGenTextures(1, &self.font_atlas_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.font_atlas_texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, @intCast(self.atlas_width), @intCast(self.atlas_height), 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &atlas_data);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    }

    pub fn initUIFontAtlas(self: *Self, font_data: []const u8, pixel_height: f32) !void {
        // Initialize text shader if not done yet
        try self.initTextRendering();

        // Initialize stb_truetype
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        // Get font metrics
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        self.ui_font_ascent = @intFromFloat(@as(f32, @floatFromInt(ascent)) * scale);
        self.ui_font_char_height = @intFromFloat(pixel_height);

        // Get character width
        var advance: c_int = undefined;
        var lsb: c_int = undefined;
        stb.stbtt_GetCodepointHMetrics(&info, 'M', &advance, &lsb);
        self.ui_font_char_width = @intFromFloat(@as(f32, @floatFromInt(advance)) * scale);

        // Create atlas 1024x1024 for ASCII + Cyrillic
        self.ui_atlas_width = 1024;
        self.ui_atlas_height = 1024;
        var atlas_data: [1024 * 1024]u8 = [_]u8{0} ** (1024 * 1024);

        // Render characters: ASCII 32-126 + Cyrillic 0x0400-0x04FF
        var atlas_x: u32 = 1;
        var atlas_y: u32 = 1;
        var row_height: u32 = 0;

        // Character ranges for rendering
        const ranges = [_][2]u32{
            .{ 32, 127 },        // ASCII
            .{ 0x0400, 0x0500 }, // Cyrillic
        };

        for (ranges) |range| {
            var cp: u32 = range[0];
            while (cp < range[1]) : (cp += 1) {
                if (cp >= self.ui_glyph_uvs.len) continue;

                var gw: c_int = undefined;
                var gh: c_int = undefined;
                var xoff: c_int = undefined;
                var yoff: c_int = undefined;

                // Get advance width for proportional font
                var char_advance: c_int = undefined;
                var char_lsb: c_int = undefined;
                stb.stbtt_GetCodepointHMetrics(&info, @intCast(cp), &char_advance, &char_lsb);
                const glyph_advance: u32 = @intFromFloat(@as(f32, @floatFromInt(char_advance)) * scale);

                const bitmap = stb.stbtt_GetCodepointBitmap(&info, 0, scale, @intCast(cp), &gw, &gh, &xoff, &yoff);

                if (bitmap != null) {
                    defer stb.stbtt_FreeBitmap(bitmap, null);

                    const glyph_w: u32 = @intCast(gw);
                    const glyph_h: u32 = @intCast(gh);

                    // Check space in row
                    if (atlas_x + glyph_w + 1 >= self.ui_atlas_width) {
                        atlas_x = 1;
                        atlas_y += row_height + 1;
                        row_height = 0;
                    }

                    if (atlas_y + glyph_h + 1 >= self.ui_atlas_height) break;

                    // Copy glyph to atlas
                    for (0..glyph_h) |row| {
                        for (0..glyph_w) |col| {
                            const src_idx = row * glyph_w + col;
                            const dst_idx = (atlas_y + row) * self.ui_atlas_width + (atlas_x + col);
                            atlas_data[dst_idx] = bitmap[src_idx];
                        }
                    }

                    // Save UV coordinates and advance
                    self.ui_glyph_uvs[cp] = .{
                        .u0 = @as(f32, @floatFromInt(atlas_x)) / @as(f32, @floatFromInt(self.ui_atlas_width)),
                        .v0 = @as(f32, @floatFromInt(atlas_y)) / @as(f32, @floatFromInt(self.ui_atlas_height)),
                        .u1 = @as(f32, @floatFromInt(atlas_x + glyph_w)) / @as(f32, @floatFromInt(self.ui_atlas_width)),
                        .v1 = @as(f32, @floatFromInt(atlas_y + glyph_h)) / @as(f32, @floatFromInt(self.ui_atlas_height)),
                        .xoff = xoff,
                        .yoff = yoff,
                        .w = glyph_w,
                        .h = glyph_h,
                        .advance = glyph_advance,
                    };

                    atlas_x += glyph_w + 1;
                    if (glyph_h > row_height) row_height = glyph_h;
                }
            }
        }

        // Upload atlas to GPU
        c.glGenTextures(1, &self.ui_font_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.ui_font_texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, @intCast(self.ui_atlas_width), @intCast(self.ui_atlas_height), 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &atlas_data);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    }

    pub fn drawChar(self: *Self, codepoint: u32, x: i32, y: i32, color: u32) void {
        // Check that codepoint is in valid range
        if (codepoint < 32) return;
        if (codepoint >= self.glyph_uvs.len) return;
        // Skip unfilled characters between ASCII and Cyrillic
        if (codepoint >= 127 and codepoint < 0x0400) return;
        if (self.font_atlas_texture == 0) return;

        const glyph = self.glyph_uvs[codepoint];
        if (glyph.w == 0) return;

        // Position accounting for baseline and offset
        const gx = x + glyph.xoff;
        const gy = y + self.font_ascent + glyph.yoff;

        // Convert to NDC
        const fx = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(gy)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(glyph.w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(glyph.h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        const vertices = [_]f32{
            fx,      fy,      glyph.u0, glyph.v0,
            fx + fw, fy,      glyph.u1, glyph.v0,
            fx,      fy - fh, glyph.u0, glyph.v1,
            fx + fw, fy - fh, glyph.u1, glyph.v1,
        };

        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.text_program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.font_atlas_texture);
        c.glUniform1i(self.text_sampler_loc, 0);
        c.glUniform4f(self.text_color_loc, cr, cg, cb, ca);

        c.glVertexAttribPointer(@intCast(self.text_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.text_pos_loc));
        c.glVertexAttribPointer(@intCast(self.text_uv_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, @ptrFromInt(@intFromPtr(&vertices) + 8));
        c.glEnableVertexAttribArray(@intCast(self.text_uv_loc));

        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    pub fn drawText(self: *Self, text: []const u8, start_x: i32, start_y: i32, color: u32) void {
        // Flush batch if color or texture changed
        if (self.text_batch_count > 0 and (self.text_batch_color != color or self.text_batch_texture != self.font_atlas_texture)) {
            self.flushTextBatch();
        }
        self.text_batch_color = color;
        self.text_batch_texture = self.font_atlas_texture;

        var x = start_x;
        const baseline_offset: i32 = 2;
        const y = start_y + baseline_offset;
        var i: usize = 0;

        while (i < text.len) {
            const result = decodeUtf8(text[i..]);
            const codepoint = result.codepoint;
            i += result.len;

            if (codepoint == '\n' or codepoint == '\r') continue;

            // Add to batch instead of drawing immediately
            self.addCharToBatch(codepoint, x, y);
            x += @intCast(self.font_char_width);
        }
    }

    fn addCharToBatch(self: *Self, codepoint: u32, x: i32, y: i32) void {
        if (codepoint < 32 or codepoint >= self.glyph_uvs.len) return;
        if (codepoint >= 127 and codepoint < 0x0400) return;
        if (self.font_atlas_texture == 0) return;

        const glyph = self.glyph_uvs[codepoint];
        if (glyph.w == 0) return;

        // Flush if batch is full
        if (self.text_batch_count >= MAX_BATCH_CHARS) {
            self.flushTextBatch();
        }

        const gx = x + glyph.xoff;
        const gy = y + self.font_ascent + glyph.yoff;

        const fx = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(gy)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(glyph.w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(glyph.h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        // 6 vertices per quad (2 triangles), 4 floats per vertex (x, y, u, v)
        const base = self.text_batch_count * 24;

        // Triangle 1: top-left, top-right, bottom-left
        self.text_batch_vertices[base + 0] = fx;
        self.text_batch_vertices[base + 1] = fy;
        self.text_batch_vertices[base + 2] = glyph.u0;
        self.text_batch_vertices[base + 3] = glyph.v0;

        self.text_batch_vertices[base + 4] = fx + fw;
        self.text_batch_vertices[base + 5] = fy;
        self.text_batch_vertices[base + 6] = glyph.u1;
        self.text_batch_vertices[base + 7] = glyph.v0;

        self.text_batch_vertices[base + 8] = fx;
        self.text_batch_vertices[base + 9] = fy - fh;
        self.text_batch_vertices[base + 10] = glyph.u0;
        self.text_batch_vertices[base + 11] = glyph.v1;

        // Triangle 2: top-right, bottom-right, bottom-left
        self.text_batch_vertices[base + 12] = fx + fw;
        self.text_batch_vertices[base + 13] = fy;
        self.text_batch_vertices[base + 14] = glyph.u1;
        self.text_batch_vertices[base + 15] = glyph.v0;

        self.text_batch_vertices[base + 16] = fx + fw;
        self.text_batch_vertices[base + 17] = fy - fh;
        self.text_batch_vertices[base + 18] = glyph.u1;
        self.text_batch_vertices[base + 19] = glyph.v1;

        self.text_batch_vertices[base + 20] = fx;
        self.text_batch_vertices[base + 21] = fy - fh;
        self.text_batch_vertices[base + 22] = glyph.u0;
        self.text_batch_vertices[base + 23] = glyph.v1;

        self.text_batch_count += 1;
    }

    pub fn flushTextBatch(self: *Self) void {
        if (self.text_batch_count == 0) return;

        const color = self.text_batch_color;
        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.text_program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.text_batch_texture);
        c.glUniform1i(self.text_sampler_loc, 0);
        c.glUniform4f(self.text_color_loc, cr, cg, cb, ca);

        // Draw ALL characters in ONE call
        c.glVertexAttribPointer(@intCast(self.text_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, &self.text_batch_vertices);
        c.glEnableVertexAttribArray(@intCast(self.text_pos_loc));
        c.glVertexAttribPointer(@intCast(self.text_uv_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, @ptrFromInt(@intFromPtr(&self.text_batch_vertices) + 8));
        c.glEnableVertexAttribArray(@intCast(self.text_uv_loc));
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(self.text_batch_count * 6));

        self.text_batch_count = 0;
    }

    /// Decodes one UTF-8 character and returns codepoint and number of bytes
    fn decodeUtf8(bytes: []const u8) struct { codepoint: u32, len: usize } {
        if (bytes.len == 0) return .{ .codepoint = 0, .len = 0 };

        const first = bytes[0];

        // ASCII (0xxxxxxx)
        if (first & 0x80 == 0) {
            return .{ .codepoint = first, .len = 1 };
        }

        // 2-byte sequence (110xxxxx 10xxxxxx)
        if (first & 0xE0 == 0xC0 and bytes.len >= 2) {
            const b1 = bytes[1];
            if (b1 & 0xC0 == 0x80) {
                const cp = (@as(u32, first & 0x1F) << 6) | @as(u32, b1 & 0x3F);
                return .{ .codepoint = cp, .len = 2 };
            }
        }

        // 3-byte sequence (1110xxxx 10xxxxxx 10xxxxxx)
        if (first & 0xF0 == 0xE0 and bytes.len >= 3) {
            const b1 = bytes[1];
            const b2 = bytes[2];
            if (b1 & 0xC0 == 0x80 and b2 & 0xC0 == 0x80) {
                const cp = (@as(u32, first & 0x0F) << 12) | (@as(u32, b1 & 0x3F) << 6) | @as(u32, b2 & 0x3F);
                return .{ .codepoint = cp, .len = 3 };
            }
        }

        // 4-byte sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
        if (first & 0xF8 == 0xF0 and bytes.len >= 4) {
            const b1 = bytes[1];
            const b2 = bytes[2];
            const b3 = bytes[3];
            if (b1 & 0xC0 == 0x80 and b2 & 0xC0 == 0x80 and b3 & 0xC0 == 0x80) {
                const cp = (@as(u32, first & 0x07) << 18) | (@as(u32, b1 & 0x3F) << 12) | (@as(u32, b2 & 0x3F) << 6) | @as(u32, b3 & 0x3F);
                return .{ .codepoint = cp, .len = 4 };
            }
        }

        // Invalid UTF-8, skip one byte
        return .{ .codepoint = 0xFFFD, .len = 1 }; // Replacement character
    }

    pub fn drawUIChar(self: *Self, codepoint: u32, x: i32, y: i32, color: u32) void {
        // Check that codepoint is in valid range
        if (codepoint < 32) return;
        if (codepoint >= self.ui_glyph_uvs.len) return;
        // Skip unfilled characters between ASCII and Cyrillic
        if (codepoint >= 127 and codepoint < 0x0400) return;
        if (self.ui_font_texture == 0) return;

        const glyph = self.ui_glyph_uvs[codepoint];
        if (glyph.w == 0) return;

        // Position accounting for baseline and offset
        const gx = x + glyph.xoff;
        const gy = y + self.ui_font_ascent + glyph.yoff;

        // Convert to NDC
        const fx = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(gy)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(glyph.w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(glyph.h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        const vertices = [_]f32{
            fx,      fy,      glyph.u0, glyph.v0,
            fx + fw, fy,      glyph.u1, glyph.v0,
            fx,      fy - fh, glyph.u0, glyph.v1,
            fx + fw, fy - fh, glyph.u1, glyph.v1,
        };

        const cr = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
        const cg = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
        const cb = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
        const ca = @as(f32, @floatFromInt((color >> 24) & 0xFF)) / 255.0;

        c.glUseProgram(self.text_program);
        c.glBindTexture(c.GL_TEXTURE_2D, self.ui_font_texture);
        c.glUniform1i(self.text_sampler_loc, 0);
        c.glUniform4f(self.text_color_loc, cr, cg, cb, ca);

        c.glVertexAttribPointer(@intCast(self.text_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), &vertices);
        c.glEnableVertexAttribArray(@intCast(self.text_pos_loc));

        c.glVertexAttribPointer(@intCast(self.text_uv_loc), 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), @ptrFromInt(@intFromPtr(&vertices) + 2 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(@intCast(self.text_uv_loc));

        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    pub fn drawUIText(self: *Self, text: []const u8, start_x: i32, start_y: i32, color: u32) void {
        if (self.ui_font_texture == 0) {
            // Fallback to regular font if UI font not loaded
            self.drawText(text, start_x, start_y, color);
            return;
        }
        var x = start_x;
        var i: usize = 0;
        while (i < text.len) {
            const result = decodeUtf8(text[i..]);
            const codepoint = result.codepoint;
            i += result.len;

            if (codepoint == '\n' or codepoint == '\r') continue;
            self.drawUIChar(codepoint, x, start_y, color);
            // Use individual character width for proportional font
            if (codepoint >= 32 and codepoint < self.ui_glyph_uvs.len) {
                const advance = self.ui_glyph_uvs[codepoint].advance;
                x += @intCast(if (advance > 0) advance else self.ui_font_char_width);
            } else {
                x += @intCast(self.ui_font_char_width);
            }
        }
    }

    pub fn uiCharWidth(self: *const Self) u32 {
        if (self.ui_font_char_width == 0) return self.charWidth();
        return self.ui_font_char_width;
    }

    // Calculate actual text width for proportional UI font
    pub fn uiTextWidth(self: *const Self, text: []const u8) u32 {
        if (self.ui_font_texture == 0) {
            return @as(u32, @intCast(text.len)) * self.charWidth();
        }
        var width: u32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const result = decodeUtf8(text[i..]);
            const codepoint = result.codepoint;
            i += result.len;

            if (codepoint >= 32 and codepoint < self.ui_glyph_uvs.len) {
                const advance = self.ui_glyph_uvs[codepoint].advance;
                width += if (advance > 0) advance else self.ui_font_char_width;
            } else {
                width += self.ui_font_char_width;
            }
        }
        return width;
    }

    pub fn lineHeight(self: *const Self) u32 {
        if (self.font_char_height == 0) return 20;
        return self.font_char_height + 4; // Small line gap
    }

    pub fn uiLineHeight(self: *const Self) u32 {
        if (self.ui_font_char_height == 0) return 16;
        return self.ui_font_char_height;
    }

    pub fn charWidth(self: *const Self) u32 {
        if (self.font_char_width == 0) return 10;
        return self.font_char_width;
    }

    pub fn setZoom(self: *Self, zoom: f32) void {
        self.zoom_level = zoom;
    }

    pub fn getZoom(self: *const Self) f32 {
        return self.zoom_level;
    }

    /// Returns size scaled by zoom
    pub fn scaled(self: *const Self, size: u32) u32 {
        return @intFromFloat(@as(f32, @floatFromInt(size)) * self.zoom_level);
    }

    /// Returns i32 size scaled by zoom
    pub fn scaledI(self: *const Self, size: i32) i32 {
        return @intFromFloat(@as(f32, @floatFromInt(size)) * self.zoom_level);
    }

    /// Sets text scale and regenerates font atlas
    pub fn setTextZoom(self: *Self, zoom: f32) !void {
        if (self.font_data_ptr == null) return;

        self.text_zoom = zoom;
        const new_size = self.base_font_size * zoom;

        // Delete old texture
        if (self.font_atlas_texture != 0) {
            c.glDeleteTextures(1, &self.font_atlas_texture);
            self.font_atlas_texture = 0;
        }

        // Regenerate atlas with new size
        const font_data = self.font_data_ptr.?[0..self.font_data_len];
        try self.rebuildFontAtlas(font_data, new_size);
    }

    pub fn getTextZoom(self: *const Self) f32 {
        return self.text_zoom;
    }

    fn rebuildFontAtlas(self: *Self, font_data: []const u8, pixel_height: f32) !void {
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        self.font_ascent = @intFromFloat(@as(f32, @floatFromInt(ascent)) * scale);
        self.font_char_height = @intFromFloat(pixel_height);

        var advance: c_int = undefined;
        var lsb: c_int = undefined;
        stb.stbtt_GetCodepointHMetrics(&info, 'M', &advance, &lsb);
        self.font_char_width = @intFromFloat(@as(f32, @floatFromInt(advance)) * scale);

        // Atlas 1024x1024 for ASCII + Cyrillic
        self.atlas_width = 1024;
        self.atlas_height = 1024;

        const allocator = std.heap.page_allocator;
        const atlas_data = try allocator.alloc(u8, 1024 * 1024);
        defer allocator.free(atlas_data);
        @memset(atlas_data, 0);

        var atlas_x: u32 = 1;
        var atlas_y: u32 = 1;
        var row_height: u32 = 0;

        // Character ranges: ASCII + Cyrillic
        const ranges = [_][2]u32{
            .{ 32, 127 },        // ASCII
            .{ 0x0400, 0x0500 }, // Cyrillic
        };

        for (ranges) |range| {
            var cp: u32 = range[0];
            while (cp < range[1]) : (cp += 1) {
                if (cp >= self.glyph_uvs.len) continue;

                var gw: c_int = undefined;
                var gh: c_int = undefined;
                var xoff: c_int = undefined;
                var yoff: c_int = undefined;

                const bitmap = stb.stbtt_GetCodepointBitmap(&info, 0, scale, @intCast(cp), &gw, &gh, &xoff, &yoff);

                if (bitmap != null) {
                    defer stb.stbtt_FreeBitmap(bitmap, null);

                    const glyph_w: u32 = @intCast(gw);
                    const glyph_h: u32 = @intCast(gh);

                    if (atlas_x + glyph_w + 1 >= self.atlas_width) {
                        atlas_x = 1;
                        atlas_y += row_height + 1;
                        row_height = 0;
                    }

                    if (atlas_y + glyph_h + 1 >= self.atlas_height) break;

                    for (0..glyph_h) |row| {
                        for (0..glyph_w) |col| {
                            const src_idx = row * glyph_w + col;
                            const dst_idx = (atlas_y + row) * self.atlas_width + (atlas_x + col);
                            atlas_data[dst_idx] = bitmap[src_idx];
                        }
                    }

                    self.glyph_uvs[cp] = .{
                        .u0 = @as(f32, @floatFromInt(atlas_x)) / @as(f32, @floatFromInt(self.atlas_width)),
                        .v0 = @as(f32, @floatFromInt(atlas_y)) / @as(f32, @floatFromInt(self.atlas_height)),
                        .u1 = @as(f32, @floatFromInt(atlas_x + glyph_w)) / @as(f32, @floatFromInt(self.atlas_width)),
                        .v1 = @as(f32, @floatFromInt(atlas_y + glyph_h)) / @as(f32, @floatFromInt(self.atlas_height)),
                        .xoff = xoff,
                        .yoff = yoff,
                        .w = glyph_w,
                        .h = glyph_h,
                    };

                    atlas_x += glyph_w + 1;
                    if (glyph_h > row_height) row_height = glyph_h;
                }
            }
        }

        c.glGenTextures(1, &self.font_atlas_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.font_atlas_texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, @intCast(self.atlas_width), @intCast(self.atlas_height), 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, atlas_data.ptr);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    }

    /// Creates OpenGL texture from RGBA data
    pub fn createTextureFromRGBA(self: *Self, data: []const u8, width: u32, height: u32) u32 {
        _ = self;
        var texture: c.GLuint = 0;
        c.glGenTextures(1, &texture);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);

        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            data.ptr,
        );

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);

        return texture;
    }

    /// Deletes texture
    pub fn deleteTexture(self: *Self, texture: u32) void {
        _ = self;
        var tex = texture;
        c.glDeleteTextures(1, &tex);
    }

    /// Draws textured quad with specified texture
    pub fn drawTexture(self: *Self, texture: u32, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        _ = color; // Not used - color is taken from texture

        const fx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(self.width)) * 2.0 - 1.0;
        const fy = 1.0 - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(self.height)) * 2.0;
        const fw = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(self.width)) * 2.0;
        const fh = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(self.height)) * 2.0;

        const vertices = [_]f32{
            fx,      fy,      0.0, 0.0,
            fx + fw, fy,      1.0, 0.0,
            fx,      fy - fh, 0.0, 1.0,
            fx + fw, fy - fh, 1.0, 1.0,
        };

        c.glUseProgram(self.tex_program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        c.glUniform1i(self.tex_sampler_loc, 0);

        c.glVertexAttribPointer(@intCast(self.tex_pos_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, &vertices);
        c.glEnableVertexAttribArray(@intCast(self.tex_pos_loc));
        c.glVertexAttribPointer(@intCast(self.tex_uv_loc), 2, c.GL_FLOAT, c.GL_FALSE, 16, @ptrFromInt(@intFromPtr(&vertices) + 8));
        c.glEnableVertexAttribArray(@intCast(self.tex_uv_loc));

        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }
};

fn compileProgram(vert_src: [*:0]const u8, frag_src: [*:0]const u8) !c.GLuint {
    const vert = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vert, 1, &vert_src, null);
    c.glCompileShader(vert);

    var status: c.GLint = 0;
    c.glGetShaderiv(vert, c.GL_COMPILE_STATUS, &status);
    if (status == 0) return error.VertexShaderFailed;

    const frag = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(frag, 1, &frag_src, null);
    c.glCompileShader(frag);

    c.glGetShaderiv(frag, c.GL_COMPILE_STATUS, &status);
    if (status == 0) return error.FragmentShaderFailed;

    const program = c.glCreateProgram();
    c.glAttachShader(program, vert);
    c.glAttachShader(program, frag);
    c.glLinkProgram(program);

    c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);
    if (status == 0) return error.ProgramLinkFailed;

    c.glDeleteShader(vert);
    c.glDeleteShader(frag);

    return program;
}
