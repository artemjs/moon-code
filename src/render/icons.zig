const std = @import("std");
const gpu_mod = @import("gpu.zig");
const GpuRenderer = gpu_mod.GpuRenderer;

// nanosvg via C
const c = @cImport({
    @cInclude("nanosvg/nanosvg.h");
    @cInclude("nanosvg/nanosvgrast.h");
});

/// Icon types
pub const IconType = enum {
    files,
    search,
    git,
    file,
    folder_open,
    file_cpp,
    file_hpp,
    file_h,
    file_c,
    file_zig,
    file_meta,
    file_json,
    file_yaml,
    file_js,
    file_ts,
    file_py,
    file_rs,
    file_go,
    file_md,
    file_txt,
    file_xml,
    file_html,
    file_css,
    // UI icons
    close,
    plus,
    window_minimize,
    window_maximize,
    window_restore,
    window_close,
    plugin,
    play,
    terminal,
    error_icon,
    warning_icon,
};

/// Cached icon
const CachedIcon = struct {
    texture_id: u32,
    size: u32,
};

/// Texture cache for icons (by type and size)
const CACHE_SIZE = 128;
var texture_cache: [CACHE_SIZE]?CachedIcon = [_]?CachedIcon{null} ** CACHE_SIZE;
var cache_keys: [CACHE_SIZE]struct { icon: IconType, size: u32 } = undefined;
var cache_count: usize = 0;

/// Rasterizer (created once)
var rasterizer: ?*c.NSVGrasterizer = null;

/// Initialize icon system
pub fn init() void {
    if (rasterizer == null) {
        rasterizer = c.nsvgCreateRasterizer();
    }
}

/// Free resources
pub fn deinit(gpu: *GpuRenderer) void {
    // Delete all textures
    for (texture_cache) |entry| {
        if (entry) |cached| {
            gpu.deleteTexture(cached.texture_id);
        }
    }
    cache_count = 0;

    if (rasterizer) |r| {
        c.nsvgDeleteRasterizer(r);
        rasterizer = null;
    }
}

/// Get texture for icon (with caching)
fn getIconTexture(gpu: *GpuRenderer, icon: IconType, size: u32) ?u32 {
    // Check cache
    for (0..cache_count) |i| {
        if (cache_keys[i].icon == icon and cache_keys[i].size == size) {
            if (texture_cache[i]) |cached| {
                return cached.texture_id;
            }
        }
    }

    // Load and rasterize SVG
    const texture_id = loadAndRasterizeSvg(gpu, icon, size) orelse return null;

    // Add to cache
    if (cache_count < CACHE_SIZE) {
        cache_keys[cache_count] = .{ .icon = icon, .size = size };
        texture_cache[cache_count] = .{ .texture_id = texture_id, .size = size };
        cache_count += 1;
    }

    return texture_id;
}

/// Load SVG and create texture
fn loadAndRasterizeSvg(gpu: *GpuRenderer, icon: IconType, size: u32) ?u32 {
    const path = getIconPath(icon);

    // Create null-terminated string
    var path_buf: [256:0]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    // Load SVG
    const nsvg = c.nsvgParseFromFile(@ptrCast(&path_buf), "px", 96.0);
    if (nsvg == null) return null;
    defer c.nsvgDelete(nsvg);

    // Initialize rasterizer if needed
    if (rasterizer == null) {
        rasterizer = c.nsvgCreateRasterizer();
    }
    const rast = rasterizer orelse return null;

    // Allocate memory for bitmap
    var allocator = std.heap.page_allocator;
    const data = allocator.alloc(u8, size * size * 4) catch return null;
    defer allocator.free(data);

    // Calculate scale
    const svg_size = @max(nsvg.*.width, nsvg.*.height);
    const scale = @as(f32, @floatFromInt(size)) / svg_size;

    // Rasterize
    c.nsvgRasterize(
        rast,
        nsvg,
        0,
        0,
        scale,
        data.ptr,
        @intCast(size),
        @intCast(size),
        @intCast(size * 4),
    );

    // Create texture
    return gpu.createTextureFromRGBA(data, size, size);
}

/// Paths to SVG files
fn getIconPath(icon: IconType) []const u8 {
    return switch (icon) {
        .files => "assets/icons/files.svg",
        .search => "assets/icons/search.svg",
        .git => "assets/icons/git-branch.svg",
        .file => "assets/icons/file-code.svg",
        .folder_open => "assets/icons/folder.svg",
        .file_cpp => "assets/icons/cpp.svg",
        .file_hpp => "assets/icons/h.svg",
        .file_h => "assets/icons/h.svg",
        .file_c => "assets/icons/c.svg",
        .file_zig => "assets/icons/zig.svg",
        .file_meta => "assets/icons/file-code.svg",
        .file_json => "assets/icons/json.svg",
        .file_yaml => "assets/icons/yaml.svg",
        .file_js => "assets/icons/js.svg",
        .file_ts => "assets/icons/ts.svg",
        .file_py => "assets/icons/py.svg",
        .file_rs => "assets/icons/rs.svg",
        .file_go => "assets/icons/go.svg",
        .file_md => "assets/icons/md.svg",
        .file_txt => "assets/icons/txt.svg",
        .file_xml => "assets/icons/xml.svg",
        .file_html => "assets/icons/html.svg",
        .file_css => "assets/icons/css.svg",
        .close => "assets/icons/close.svg",
        .plus => "assets/icons/plus.svg",
        .window_minimize => "assets/icons/window-minimize.svg",
        .window_maximize => "assets/icons/window-maximize.svg",
        .window_restore => "assets/icons/window-restore.svg",
        .window_close => "assets/icons/window-close.svg",
        .plugin => "assets/icons/plugin.svg",
        .play => "assets/icons/play.svg",
        .terminal => "assets/icons/terminal.svg",
        .error_icon => "assets/icons/error.svg",
        .warning_icon => "assets/icons/warning.svg",
    };
}

/// Draw icon
pub fn drawIcon(gpu: *GpuRenderer, icon: IconType, x: i32, y: i32, size: u32, color: u32) void {
    // Try to get SVG texture
    if (getIconTexture(gpu, icon, size)) |texture| {
        gpu.drawTexture(texture, x, y, size, size, color);
        return;
    }

    // Fallback to primitives
    const scale: f32 = @as(f32, @floatFromInt(size)) / 16.0;

    switch (icon) {
        .files => drawFilesIcon(gpu, x, y, scale, color),
        .search => drawSearchIcon(gpu, x, y, scale, color),
        .git => drawGitIcon(gpu, x, y, scale, color),
        .file, .file_txt => drawFileIcon(gpu, x, y, scale, color),
        .folder_open => drawFolderOpenIcon(gpu, x, y, scale, color),
        .file_cpp => drawFileWithLetter(gpu, x, y, scale, "C+", 0xFF569CD6),
        .file_hpp => drawFileWithLetter(gpu, x, y, scale, "H+", 0xFF9B6DFF),
        .file_h => drawFileWithLetter(gpu, x, y, scale, "H", 0xFF9B6DFF),
        .file_c => drawFileWithLetter(gpu, x, y, scale, "C", 0xFF569CD6),
        .file_zig => drawZigIcon(gpu, x, y, scale),
        .file_meta => drawFileWithLetter(gpu, x, y, scale, "M", 0xFFB0B0B0),
        .file_json => drawJsonIcon(gpu, x, y, scale),
        .file_yaml => drawFileWithLetter(gpu, x, y, scale, "Y", 0xFFCB4B16),
        .file_js => drawFileWithLetter(gpu, x, y, scale, "JS", 0xFFF7DF1E),
        .file_ts => drawFileWithLetter(gpu, x, y, scale, "TS", 0xFF3178C6),
        .file_py => drawPythonIcon(gpu, x, y, scale),
        .file_rs => drawFileWithLetter(gpu, x, y, scale, "Rs", 0xFFDEA584),
        .file_go => drawFileWithLetter(gpu, x, y, scale, "Go", 0xFF00ADD8),
        .file_md => drawFileWithLetter(gpu, x, y, scale, "MD", 0xFF519ABA),
        .file_xml => drawFileWithLetter(gpu, x, y, scale, "<>", 0xFFE37933),
        .file_html => drawFileWithLetter(gpu, x, y, scale, "<>", 0xFFE44D26),
        .file_css => drawFileWithLetter(gpu, x, y, scale, "#", 0xFF264DE4),
        .close => drawCloseIcon(gpu, x, y, scale, color),
        .plus => drawPlusIcon(gpu, x, y, scale, color),
        .window_minimize => drawWindowMinimizeIcon(gpu, x, y, scale, color),
        .window_maximize => drawWindowMaximizeIcon(gpu, x, y, scale, color),
        .window_restore => drawWindowRestoreIcon(gpu, x, y, scale, color),
        .window_close => drawCloseIcon(gpu, x, y, scale, color),
        .plugin => drawPluginIcon(gpu, x, y, scale, color),
        .play => drawPlayIcon(gpu, x, y, scale, color),
        .terminal => drawTerminalIcon(gpu, x, y, scale, color),
        .error_icon => drawErrorIcon(gpu, x, y, scale, color),
        .warning_icon => drawWarningIcon(gpu, x, y, scale, color),
    }
}

/// Get icon type by file extension
pub fn getIconForExtension(filename: []const u8) IconType {
    var ext_start: usize = filename.len;
    var i: usize = filename.len;
    while (i > 0) {
        i -= 1;
        if (filename[i] == '.') {
            ext_start = i;
            break;
        }
    }

    if (ext_start >= filename.len) return .file;

    const ext = filename[ext_start..];

    if (eqlIgnoreCase(ext, ".cpp") or eqlIgnoreCase(ext, ".cc") or eqlIgnoreCase(ext, ".cxx")) return .file_cpp;
    if (eqlIgnoreCase(ext, ".hpp") or eqlIgnoreCase(ext, ".hxx")) return .file_hpp;
    if (eqlIgnoreCase(ext, ".h")) return .file_h;
    if (eqlIgnoreCase(ext, ".c")) return .file_c;
    if (eqlIgnoreCase(ext, ".zig")) return .file_zig;
    if (eqlIgnoreCase(ext, ".meta")) return .file_meta;
    if (eqlIgnoreCase(ext, ".json")) return .file_json;
    if (eqlIgnoreCase(ext, ".yaml") or eqlIgnoreCase(ext, ".yml")) return .file_yaml;
    if (eqlIgnoreCase(ext, ".js") or eqlIgnoreCase(ext, ".mjs")) return .file_js;
    if (eqlIgnoreCase(ext, ".ts") or eqlIgnoreCase(ext, ".tsx")) return .file_ts;
    if (eqlIgnoreCase(ext, ".py") or eqlIgnoreCase(ext, ".pyw")) return .file_py;
    if (eqlIgnoreCase(ext, ".rs")) return .file_rs;
    if (eqlIgnoreCase(ext, ".go")) return .file_go;
    if (eqlIgnoreCase(ext, ".md") or eqlIgnoreCase(ext, ".markdown")) return .file_md;
    if (eqlIgnoreCase(ext, ".txt")) return .file_txt;
    if (eqlIgnoreCase(ext, ".xml")) return .file_xml;
    if (eqlIgnoreCase(ext, ".html") or eqlIgnoreCase(ext, ".htm")) return .file_html;
    if (eqlIgnoreCase(ext, ".css")) return .file_css;

    return .file;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const la = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        const lb = if (cb >= 'A' and cb <= 'Z') cb + 32 else cb;
        if (la != lb) return false;
    }
    return true;
}

// === Fallback rendering with primitives ===

fn drawFilesIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    const bx = x + @as(i32, @intFromFloat(1.0 * scale));
    const by = y + @as(i32, @intFromFloat(5.0 * scale));
    const bw: u32 = @intFromFloat(14.0 * scale);
    const bh: u32 = @intFromFloat(9.0 * scale);
    gpu.fillRoundedRect(bx, by, bw, bh, @intFromFloat(2.0 * scale), color);

    const tx = x + @as(i32, @intFromFloat(1.0 * scale));
    const ty = y + @as(i32, @intFromFloat(2.0 * scale));
    const tw: u32 = @intFromFloat(6.0 * scale);
    const th: u32 = @intFromFloat(4.0 * scale);
    gpu.fillRoundedRect(tx, ty, tw, th, @intFromFloat(1.0 * scale), color);
}

fn drawSearchIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    const cx = x + @as(i32, @intFromFloat(2.0 * scale));
    const cy = y + @as(i32, @intFromFloat(2.0 * scale));
    const cs: u32 = @intFromFloat(10.0 * scale);
    const cr: u32 = @intFromFloat(5.0 * scale);
    gpu.fillRoundedRect(cx, cy, cs, cs, cr, color);

    const ix = x + @as(i32, @intFromFloat(4.0 * scale));
    const iy = y + @as(i32, @intFromFloat(4.0 * scale));
    const is: u32 = @intFromFloat(6.0 * scale);
    const ir: u32 = @intFromFloat(3.0 * scale);
    gpu.fillRoundedRect(ix, iy, is, is, ir, 0xFF252220);

    const hx = x + @as(i32, @intFromFloat(10.0 * scale));
    const hy = y + @as(i32, @intFromFloat(10.0 * scale));
    gpu.fillRoundedRect(hx, hy, @intFromFloat(4.0 * scale), @intFromFloat(2.0 * scale), 1, color);
    gpu.fillRoundedRect(hx + 2, hy + 1, @intFromFloat(2.0 * scale), @intFromFloat(3.0 * scale), 1, color);
}

fn drawGitIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    const lx = x + @as(i32, @intFromFloat(7.0 * scale));
    const ly = y + @as(i32, @intFromFloat(1.0 * scale));
    gpu.fillRect(lx, ly, @intFromFloat(2.0 * scale), @intFromFloat(14.0 * scale), color);

    const ts: u32 = @intFromFloat(6.0 * scale);
    const tr: u32 = @intFromFloat(3.0 * scale);
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(5.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), ts, ts, tr, color);
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(5.0 * scale)), y + @as(i32, @intFromFloat(10.0 * scale)), ts, ts, tr, color);

    gpu.fillRect(x + @as(i32, @intFromFloat(1.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(7.0 * scale), @intFromFloat(2.0 * scale), color);
    gpu.fillRoundedRect(x, y + @as(i32, @intFromFloat(4.0 * scale)), @intFromFloat(5.0 * scale), @intFromFloat(5.0 * scale), @intFromFloat(2.0 * scale), color);
}

fn drawFileIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    const fx = x + @as(i32, @intFromFloat(2.0 * scale));
    const fy = y + @as(i32, @intFromFloat(1.0 * scale));
    const fw: u32 = @intFromFloat(10.0 * scale);
    const fh: u32 = @intFromFloat(14.0 * scale);
    gpu.fillRoundedRect(fx, fy, fw, fh, @intFromFloat(1.0 * scale), color);

    const ccx = x + @as(i32, @intFromFloat(8.0 * scale));
    const ccy = y + @as(i32, @intFromFloat(1.0 * scale));
    gpu.fillRect(ccx, ccy, @intFromFloat(4.0 * scale), @intFromFloat(4.0 * scale), 0xFF252220);
    gpu.fillRoundedRect(ccx, ccy, @intFromFloat(4.0 * scale), @intFromFloat(4.0 * scale), 0, color);
}

fn drawFolderOpenIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(1.0 * scale)), y + @as(i32, @intFromFloat(3.0 * scale)), @intFromFloat(14.0 * scale), @intFromFloat(10.0 * scale), @intFromFloat(2.0 * scale), color);
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(1.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(6.0 * scale), @intFromFloat(3.0 * scale), @intFromFloat(1.0 * scale), color);

    const lighter = (color & 0xFF000000) | @min(0x00FFFFFF, (color & 0x00FEFEFE) + 0x00202020);
    gpu.fillRoundedRect(x, y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(14.0 * scale), @intFromFloat(8.0 * scale), @intFromFloat(2.0 * scale), lighter);
}

fn drawFileWithLetter(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, letter: []const u8, letter_color: u32) void {
    const base_color: u32 = 0xFF606060;
    const fx = x + @as(i32, @intFromFloat(2.0 * scale));
    const fy = y + @as(i32, @intFromFloat(1.0 * scale));
    gpu.fillRoundedRect(fx, fy, @intFromFloat(12.0 * scale), @intFromFloat(14.0 * scale), @intFromFloat(2.0 * scale), base_color);
    gpu.fillRect(x + @as(i32, @intFromFloat(9.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(5.0 * scale), @intFromFloat(4.0 * scale), 0xFF404040);
    gpu.drawUIText(letter, x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), letter_color);
}

fn drawZigIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32) void {
    const zig_orange: u32 = 0xFFF7A41D;
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(2.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(12.0 * scale), @intFromFloat(14.0 * scale), @intFromFloat(2.0 * scale), 0xFF2D2D2D);
    gpu.fillRect(x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(4.0 * scale)), @intFromFloat(8.0 * scale), @intFromFloat(2.0 * scale), zig_orange);
    gpu.fillRect(x + @as(i32, @intFromFloat(7.0 * scale)), y + @as(i32, @intFromFloat(5.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(4.0 * scale), zig_orange);
    gpu.fillRect(x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(9.0 * scale)), @intFromFloat(8.0 * scale), @intFromFloat(2.0 * scale), zig_orange);
}

fn drawJsonIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32) void {
    const json_yellow: u32 = 0xFFCBCB41;
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(2.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(12.0 * scale), @intFromFloat(14.0 * scale), @intFromFloat(2.0 * scale), 0xFF2D2D2D);
    gpu.fillRect(x + @as(i32, @intFromFloat(5.0 * scale)), y + @as(i32, @intFromFloat(4.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(3.0 * scale), json_yellow);
    gpu.fillRect(x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(2.0 * scale), json_yellow);
    gpu.fillRect(x + @as(i32, @intFromFloat(5.0 * scale)), y + @as(i32, @intFromFloat(8.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(3.0 * scale), json_yellow);
    gpu.fillRect(x + @as(i32, @intFromFloat(9.0 * scale)), y + @as(i32, @intFromFloat(4.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(3.0 * scale), json_yellow);
    gpu.fillRect(x + @as(i32, @intFromFloat(10.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(2.0 * scale), json_yellow);
    gpu.fillRect(x + @as(i32, @intFromFloat(9.0 * scale)), y + @as(i32, @intFromFloat(8.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(3.0 * scale), json_yellow);
}

fn drawPythonIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32) void {
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(2.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(12.0 * scale), @intFromFloat(14.0 * scale), @intFromFloat(2.0 * scale), 0xFF2D2D2D);
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(4.0 * scale)), @intFromFloat(5.0 * scale), @intFromFloat(4.0 * scale), @intFromFloat(1.0 * scale), 0xFF3776AB);
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(7.0 * scale)), y + @as(i32, @intFromFloat(7.0 * scale)), @intFromFloat(5.0 * scale), @intFromFloat(4.0 * scale), @intFromFloat(1.0 * scale), 0xFFFFD43B);
}

fn drawCloseIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // X cross
    const cx = x + @as(i32, @intFromFloat(4.0 * scale));
    const cy = y + @as(i32, @intFromFloat(4.0 * scale));
    const size: u32 = @intFromFloat(8.0 * scale);
    const thick: u32 = @intFromFloat(2.0 * scale);
    // Diagonal \
    gpu.fillRect(cx, cy, thick, size, color);
    gpu.fillRect(cx, cy, size, thick, color);
    // Diagonal /
    gpu.fillRect(cx + @as(i32, @intCast(size)) - @as(i32, @intCast(thick)), cy, thick, size, color);
    gpu.fillRect(cx, cy + @as(i32, @intCast(size)) - @as(i32, @intCast(thick)), size, thick, color);
}

fn drawPlusIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Plus +
    const cx = x + @as(i32, @intFromFloat(7.0 * scale));
    const cy = y + @as(i32, @intFromFloat(4.0 * scale));
    const len: u32 = @intFromFloat(8.0 * scale);
    const thick: u32 = @intFromFloat(2.0 * scale);
    // Vertical line
    gpu.fillRect(cx, cy, thick, len, color);
    // Horizontal line
    gpu.fillRect(x + @as(i32, @intFromFloat(4.0 * scale)), y + @as(i32, @intFromFloat(7.0 * scale)), len, thick, color);
}

fn drawWindowMinimizeIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Horizontal line -
    const lx = x + @as(i32, @intFromFloat(4.0 * scale));
    const ly = y + @as(i32, @intFromFloat(8.0 * scale));
    gpu.fillRect(lx, ly, @intFromFloat(8.0 * scale), @intFromFloat(1.0 * scale), color);
}

fn drawWindowMaximizeIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Square
    const bx = x + @as(i32, @intFromFloat(4.0 * scale));
    const by = y + @as(i32, @intFromFloat(4.0 * scale));
    const bs: u32 = @intFromFloat(8.0 * scale);
    const thick: u32 = @intFromFloat(1.0 * scale);
    // Top
    gpu.fillRect(bx, by, bs, thick, color);
    // Bottom
    gpu.fillRect(bx, by + @as(i32, @intCast(bs)) - @as(i32, @intCast(thick)), bs, thick, color);
    // Left
    gpu.fillRect(bx, by, thick, bs, color);
    // Right
    gpu.fillRect(bx + @as(i32, @intCast(bs)) - @as(i32, @intCast(thick)), by, thick, bs, color);
}

fn drawWindowRestoreIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Two squares (restore)
    const thick: u32 = @intFromFloat(1.0 * scale);
    // Back square (offset right-up)
    const bx = x + @as(i32, @intFromFloat(6.0 * scale));
    const by = y + @as(i32, @intFromFloat(3.0 * scale));
    const bs: u32 = @intFromFloat(7.0 * scale);
    gpu.fillRect(bx, by, bs, thick, color);
    gpu.fillRect(bx + @as(i32, @intCast(bs)) - @as(i32, @intCast(thick)), by, thick, bs, color);
    gpu.fillRect(bx, by, thick, @intFromFloat(2.0 * scale), color);
    // Front square
    const fx = x + @as(i32, @intFromFloat(3.0 * scale));
    const fy = y + @as(i32, @intFromFloat(6.0 * scale));
    const fs: u32 = @intFromFloat(7.0 * scale);
    gpu.fillRect(fx, fy, fs, thick, color);
    gpu.fillRect(fx, fy + @as(i32, @intCast(fs)) - @as(i32, @intCast(thick)), fs, thick, color);
    gpu.fillRect(fx, fy, thick, fs, color);
    gpu.fillRect(fx + @as(i32, @intCast(fs)) - @as(i32, @intCast(thick)), fy, thick, fs, color);
}

fn drawPluginIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Plugin icon - puzzle piece
    const bx = x + @as(i32, @intFromFloat(3.0 * scale));
    const by = y + @as(i32, @intFromFloat(3.0 * scale));
    const bs: u32 = @intFromFloat(10.0 * scale);
    gpu.fillRoundedRect(bx, by, bs, bs, @intFromFloat(2.0 * scale), color);
    // Protrusion on top
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(6.0 * scale)), y + @as(i32, @intFromFloat(1.0 * scale)), @intFromFloat(4.0 * scale), @intFromFloat(4.0 * scale), @intFromFloat(2.0 * scale), color);
    // Protrusion on right
    gpu.fillRoundedRect(x + @as(i32, @intFromFloat(11.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(4.0 * scale), @intFromFloat(4.0 * scale), @intFromFloat(2.0 * scale), color);
}

fn drawPlayIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Play triangle
    const px = x + @as(i32, @intFromFloat(4.0 * scale));
    const py = y + @as(i32, @intFromFloat(2.0 * scale));
    // Draw as a series of rectangles (triangle)
    var i: i32 = 0;
    while (i < @as(i32, @intFromFloat(12.0 * scale))) : (i += 1) {
        const row_y = py + i;
        const mid: i32 = @intFromFloat(6.0 * scale);
        const dist = @as(i32, @intCast(@abs(i - mid)));
        const width: u32 = @intCast(@max(1, @as(i32, @intFromFloat(10.0 * scale)) - dist * 2));
        gpu.fillRect(px, row_y, width, 1, color);
    }
}

fn drawTerminalIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Terminal window
    const bx = x + @as(i32, @intFromFloat(1.0 * scale));
    const by = y + @as(i32, @intFromFloat(2.0 * scale));
    const bw: u32 = @intFromFloat(14.0 * scale);
    const bh: u32 = @intFromFloat(12.0 * scale);
    const inner_h: u32 = bh - @as(u32, @intFromFloat(4.0 * scale));
    gpu.fillRoundedRect(bx, by, bw, bh, @as(u32, @intFromFloat(2.0 * scale)), color);
    // Inner area
    gpu.fillRoundedRect(bx + 1, by + @as(i32, @intFromFloat(3.0 * scale)), bw - 2, inner_h, @as(u32, @intFromFloat(1.0 * scale)), 0xFF1a1a1a);
    // Prompt >_
    gpu.fillRect(x + @as(i32, @intFromFloat(3.0 * scale)), y + @as(i32, @intFromFloat(8.0 * scale)), @as(u32, @intFromFloat(3.0 * scale)), @as(u32, @intFromFloat(1.0 * scale)), color);
    gpu.fillRect(x + @as(i32, @intFromFloat(3.0 * scale)), y + @as(i32, @intFromFloat(7.0 * scale)), @as(u32, @intFromFloat(1.0 * scale)), @as(u32, @intFromFloat(3.0 * scale)), color);
    // Cursor
    gpu.fillRect(x + @as(i32, @intFromFloat(8.0 * scale)), y + @as(i32, @intFromFloat(8.0 * scale)), @as(u32, @intFromFloat(3.0 * scale)), @as(u32, @intFromFloat(2.0 * scale)), color);
}

fn drawErrorIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Circle with X
    _ = color;
    const cx = x + @as(i32, @intFromFloat(2.0 * scale));
    const cy = y + @as(i32, @intFromFloat(2.0 * scale));
    const cs: u32 = @intFromFloat(12.0 * scale);
    gpu.fillRoundedRect(cx, cy, cs, cs, @intFromFloat(6.0 * scale), 0xFFe74c3c); // Red
    // X in center
    gpu.fillRect(x + @as(i32, @intFromFloat(5.0 * scale)), y + @as(i32, @intFromFloat(7.0 * scale)), @intFromFloat(6.0 * scale), @intFromFloat(2.0 * scale), 0xFFffffff);
    gpu.fillRect(x + @as(i32, @intFromFloat(7.0 * scale)), y + @as(i32, @intFromFloat(5.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(6.0 * scale), 0xFFffffff);
}

fn drawWarningIcon(gpu: *GpuRenderer, x: i32, y: i32, scale: f32, color: u32) void {
    // Triangle with !
    _ = color;
    const px = x + @as(i32, @intFromFloat(8.0 * scale));
    const py = y + @as(i32, @intFromFloat(2.0 * scale));
    // Triangle (yellow)
    var i: i32 = 0;
    while (i < @as(i32, @intFromFloat(12.0 * scale))) : (i += 1) {
        const row_y = py + i;
        const width: u32 = @intCast(@max(1, i + 1));
        const row_x = px - @divTrunc(i, 2);
        gpu.fillRect(row_x, row_y, width, 1, 0xFFf39c12); // Yellow
    }
    // ! in center
    gpu.fillRect(x + @as(i32, @intFromFloat(7.0 * scale)), y + @as(i32, @intFromFloat(6.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(4.0 * scale), 0xFF1a1a1a);
    gpu.fillRect(x + @as(i32, @intFromFloat(7.0 * scale)), y + @as(i32, @intFromFloat(11.0 * scale)), @intFromFloat(2.0 * scale), @intFromFloat(2.0 * scale), 0xFF1a1a1a);
}
