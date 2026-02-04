const std = @import("std");
const c = @cImport({
    @cInclude("nanosvg/nanosvg.h");
    @cInclude("nanosvg/nanosvgrast.h");
});

/// SVG image
pub const SvgImage = struct {
    nsvg: *c.NSVGimage,
    width: f32,
    height: f32,

    pub fn deinit(self: *SvgImage) void {
        c.nsvgDelete(self.nsvg);
    }
};

/// Rasterized SVG image (RGBA bitmap)
pub const RasterizedSvg = struct {
    data: []u8,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RasterizedSvg) void {
        self.allocator.free(self.data);
    }
};

/// Loads SVG from file
pub fn loadFromFile(path: []const u8) ?SvgImage {
    // Create null-terminated string for C
    var path_buf: [1024]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const nsvg = c.nsvgParseFromFile(&path_buf, "px", 96.0);
    if (nsvg == null) return null;

    return SvgImage{
        .nsvg = nsvg.?,
        .width = nsvg.?.width,
        .height = nsvg.?.height,
    };
}

/// Loads SVG from string
pub fn loadFromMemory(data: []const u8, allocator: std.mem.Allocator) ?SvgImage {
    // nsvgParse modifies the input string, so a copy is needed
    const copy = allocator.allocSentinel(u8, data.len, 0) catch return null;
    defer allocator.free(copy);
    @memcpy(copy, data);

    const nsvg = c.nsvgParse(copy.ptr, "px", 96.0);
    if (nsvg == null) return null;

    return SvgImage{
        .nsvg = nsvg.?,
        .width = nsvg.?.width,
        .height = nsvg.?.height,
    };
}

/// Rasterizes SVG to RGBA bitmap
pub fn rasterize(svg: *const SvgImage, width: u32, height: u32, allocator: std.mem.Allocator) ?RasterizedSvg {
    const rast = c.nsvgCreateRasterizer();
    if (rast == null) return null;
    defer c.nsvgDeleteRasterizer(rast);

    const data = allocator.alloc(u8, width * height * 4) catch return null;

    // Calculate scale
    const scale_x = @as(f32, @floatFromInt(width)) / svg.width;
    const scale_y = @as(f32, @floatFromInt(height)) / svg.height;
    const scale = @min(scale_x, scale_y);

    c.nsvgRasterize(
        rast,
        svg.nsvg,
        0,
        0,
        scale,
        data.ptr,
        @intCast(width),
        @intCast(height),
        @intCast(width * 4),
    );

    return RasterizedSvg{
        .data = data,
        .width = width,
        .height = height,
        .allocator = allocator,
    };
}

/// Rasterizes SVG with specified color (replaces colors)
pub fn rasterizeWithColor(svg: *const SvgImage, width: u32, height: u32, color: u32, allocator: std.mem.Allocator) ?RasterizedSvg {
    var result = rasterize(svg, width, height, allocator) orelse return null;

    // Replace color, preserving alpha
    const r: u8 = @truncate((color >> 16) & 0xFF);
    const g: u8 = @truncate((color >> 8) & 0xFF);
    const b: u8 = @truncate(color & 0xFF);

    var i: usize = 0;
    while (i < result.data.len) : (i += 4) {
        const alpha = result.data[i + 3];
        if (alpha > 0) {
            result.data[i + 0] = r;
            result.data[i + 1] = g;
            result.data[i + 2] = b;
            // alpha remains unchanged
        }
    }

    return result;
}
