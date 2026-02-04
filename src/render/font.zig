const std = @import("std");
const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const Font = struct {
    info: c.stbtt_fontinfo,
    data: []const u8,
    scale: f32,
    ascent: i32,
    descent: i32,
    line_gap: i32,
    char_width: u32,
    char_height: u32,

    const Self = @This();

    pub fn init(font_data: []const u8, pixel_height: f32) !Self {
        var info: c.stbtt_fontinfo = undefined;

        if (c.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = c.stbtt_ScaleForPixelHeight(&info, pixel_height);

        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        c.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        // Get the width of 'M' character for monospace font
        var advance: c_int = undefined;
        var lsb: c_int = undefined;
        c.stbtt_GetCodepointHMetrics(&info, 'M', &advance, &lsb);

        const char_width: u32 = @intFromFloat(@as(f32, @floatFromInt(advance)) * scale);
        const char_height: u32 = @intFromFloat(pixel_height);

        return Self{
            .info = info,
            .data = font_data,
            .scale = scale,
            .ascent = @intFromFloat(@as(f32, @floatFromInt(ascent)) * scale),
            .descent = @intFromFloat(@as(f32, @floatFromInt(descent)) * scale),
            .line_gap = @intFromFloat(@as(f32, @floatFromInt(line_gap)) * scale),
            .char_width = char_width,
            .char_height = char_height,
        };
    }

    pub fn lineHeight(self: *const Self) u32 {
        return @intCast(self.ascent - self.descent + self.line_gap);
    }

    pub fn renderChar(
        self: *const Self,
        codepoint: u21,
        buffer: []u8,
        buf_width: u32,
        buf_height: u32,
        x: i32,
        y: i32,
        color: u32,
    ) void {
        var width: c_int = undefined;
        var height: c_int = undefined;
        var xoff: c_int = undefined;
        var yoff: c_int = undefined;

        const bitmap = c.stbtt_GetCodepointBitmap(
            &self.info,
            0,
            self.scale,
            @intCast(codepoint),
            &width,
            &height,
            &xoff,
            &yoff,
        );

        if (bitmap == null) return;
        defer c.stbtt_FreeBitmap(bitmap, null);

        const baseline_y = y + self.ascent;
        const glyph_y = baseline_y + yoff;
        const glyph_x = x + xoff;

        const r: u32 = (color >> 16) & 0xFF;
        const g: u32 = (color >> 8) & 0xFF;
        const b: u32 = color & 0xFF;

        const pixels: [*]u32 = @ptrCast(@alignCast(buffer.ptr));

        var row: i32 = 0;
        while (row < height) : (row += 1) {
            var col: i32 = 0;
            while (col < width) : (col += 1) {
                const px = glyph_x + col;
                const py = glyph_y + row;

                if (px < 0 or py < 0) {
                    col += 1;
                    continue;
                }
                if (px >= @as(i32, @intCast(buf_width)) or py >= @as(i32, @intCast(buf_height))) {
                    col += 1;
                    continue;
                }

                const alpha = bitmap[@intCast(row * width + col)];
                if (alpha == 0) continue;

                const idx: usize = @intCast(py * @as(i32, @intCast(buf_width)) + px);
                const bg = pixels[idx];
                const bg_r = (bg >> 16) & 0xFF;
                const bg_g = (bg >> 8) & 0xFF;
                const bg_b = bg & 0xFF;

                // Alpha blending
                const a: u32 = alpha;
                const inv_a: u32 = 255 - a;
                const out_r = (r * a + bg_r * inv_a) / 255;
                const out_g = (g * a + bg_g * inv_a) / 255;
                const out_b = (b * a + bg_b * inv_a) / 255;

                pixels[idx] = 0xFF000000 | (out_r << 16) | (out_g << 8) | out_b;
            }
        }
    }

    pub fn renderText(
        self: *const Self,
        text: []const u8,
        buffer: []u8,
        buf_width: u32,
        buf_height: u32,
        start_x: i32,
        start_y: i32,
        color: u32,
    ) void {
        var x = start_x;
        const y = start_y;

        for (text) |char| {
            if (char == '\n') {
                continue; // Handled separately
            }

            self.renderChar(char, buffer, buf_width, buf_height, x, y, color);
            x += @intCast(self.char_width);
        }
    }
};
