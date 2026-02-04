const std = @import("std");
const c = @import("../c.zig").c;

pub const Buffer = struct {
    wl_buffer: *c.wl_buffer,
    data: []u8,
    width: u32,
    height: u32,
    stride: u32,
    fd: c_int,

    const Self = @This();

    pub fn create(shm: *c.wl_shm, width: u32, height: u32) !Self {
        const stride = width * 4; // ARGB8888
        const size: usize = @as(usize, stride) * @as(usize, height);

        // Create an anonymous file
        const fd = createShmFile(size) orelse return error.ShmFileCreationFailed;

        // mmap
        const data_ptr = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (data_ptr == c.MAP_FAILED) {
            _ = c.close(fd);
            return error.MmapFailed;
        }

        // Create wl_shm_pool
        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size)) orelse {
            _ = c.munmap(data_ptr, size);
            _ = c.close(fd);
            return error.PoolCreationFailed;
        };

        // Create buffer
        const wl_buffer = c.wl_shm_pool_create_buffer(
            pool,
            0,
            @intCast(width),
            @intCast(height),
            @intCast(stride),
            c.WL_SHM_FORMAT_ARGB8888,
        ) orelse {
            c.wl_shm_pool_destroy(pool);
            _ = c.munmap(data_ptr, size);
            _ = c.close(fd);
            return error.BufferCreationFailed;
        };

        c.wl_shm_pool_destroy(pool);

        const data: []u8 = @as([*]u8, @ptrCast(data_ptr))[0..size];

        return Self{
            .wl_buffer = wl_buffer,
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
            .fd = fd,
        };
    }

    pub fn destroy(self: *Self) void {
        c.wl_buffer_destroy(self.wl_buffer);
        _ = c.munmap(self.data.ptr, self.data.len);
        _ = c.close(self.fd);
    }

    pub fn setPixel(self: *Self, x: u32, y: u32, color: u32) void {
        if (x >= self.width or y >= self.height) return;
        const offset = y * self.stride + x * 4;
        const pixels: [*]u32 = @ptrCast(@alignCast(self.data.ptr));
        pixels[offset / 4] = color;
    }

    pub fn fill(self: *Self, color: u32) void {
        const pixels: [*]u32 = @ptrCast(@alignCast(self.data.ptr));
        const count = self.data.len / 4;
        for (0..count) |i| {
            pixels[i] = color;
        }
    }

    pub fn fillRect(self: *Self, x: u32, y: u32, w: u32, h: u32, color: u32) void {
        const pixels: [*]u32 = @ptrCast(@alignCast(self.data.ptr));
        const x_end = @min(x + w, self.width);
        const y_end = @min(y + h, self.height);

        var py = y;
        while (py < y_end) : (py += 1) {
            var px = x;
            while (px < x_end) : (px += 1) {
                const idx = py * (self.stride / 4) + px;
                pixels[idx] = color;
            }
        }
    }

    /// Rounded rectangle with antialiasing
    pub fn fillRoundedRect(self: *Self, x: u32, y: u32, w: u32, h: u32, radius: u32, color: u32) void {
        if (w == 0 or h == 0) return;
        const r: f32 = @floatFromInt(@min(radius, @min(w / 2, h / 2)));
        const base_r = (color >> 16) & 0xFF;
        const base_g = (color >> 8) & 0xFF;
        const base_b = color & 0xFF;

        var py: u32 = 0;
        while (py < h) : (py += 1) {
            var px: u32 = 0;
            while (px < w) : (px += 1) {
                var corner_dist: f32 = -1.0; // -1 = not in corner

                const fpx: f32 = @floatFromInt(px);
                const fpy: f32 = @floatFromInt(py);
                const fw: f32 = @floatFromInt(w);
                const fh: f32 = @floatFromInt(h);

                // Check corners
                if (fpx < r and fpy < r) {
                    // Top left
                    const dx = r - fpx - 0.5;
                    const dy = r - fpy - 0.5;
                    corner_dist = @sqrt(dx * dx + dy * dy) - r;
                } else if (fpx >= fw - r and fpy < r) {
                    // Top right
                    const dx = fpx - (fw - r) + 0.5;
                    const dy = r - fpy - 0.5;
                    corner_dist = @sqrt(dx * dx + dy * dy) - r;
                } else if (fpx < r and fpy >= fh - r) {
                    // Bottom left
                    const dx = r - fpx - 0.5;
                    const dy = fpy - (fh - r) + 0.5;
                    corner_dist = @sqrt(dx * dx + dy * dy) - r;
                } else if (fpx >= fw - r and fpy >= fh - r) {
                    // Bottom right
                    const dx = fpx - (fw - r) + 0.5;
                    const dy = fpy - (fh - r) + 0.5;
                    corner_dist = @sqrt(dx * dx + dy * dy) - r;
                }

                if (corner_dist < -0.5) {
                    // Not in corner - draw fully
                    self.setPixel(x + px, y + py, color);
                } else if (corner_dist < 0.5) {
                    // Corner edge - antialiasing
                    const alpha_f = 0.5 - corner_dist;
                    const alpha: u32 = @intFromFloat(@max(0, @min(255, alpha_f * 255)));
                    if (alpha > 0) {
                        const aa_color = (alpha << 24) | (base_r << 16) | (base_g << 8) | base_b;
                        self.blendPixel(x + px, y + py, aa_color);
                    }
                }
                // corner_dist >= 0.5 - outside bounds, don't draw
            }
        }
    }

    /// Filled circle with antialiasing
    pub fn fillCircleAA(self: *Self, cx: i32, cy: i32, radius: f32, color: u32) void {
        const r_int: i32 = @intFromFloat(radius + 1.5);
        const base_r = (color >> 16) & 0xFF;
        const base_g = (color >> 8) & 0xFF;
        const base_b = color & 0xFF;

        var dy: i32 = -r_int;
        while (dy <= r_int) : (dy += 1) {
            var dx: i32 = -r_int;
            while (dx <= r_int) : (dx += 1) {
                const px = cx + dx;
                const py = cy + dy;
                if (px < 0 or py < 0) continue;

                // Distance from center
                const dist = @sqrt(@as(f32, @floatFromInt(dx * dx + dy * dy)));
                if (dist <= radius - 0.5) {
                    // Fully inside
                    self.setPixel(@intCast(px), @intCast(py), color);
                } else if (dist < radius + 0.5) {
                    // Edge - antialiasing
                    const alpha_f = 1.0 - (dist - (radius - 0.5));
                    const alpha: u32 = @intFromFloat(@max(0, @min(255, alpha_f * 255)));
                    const aa_color = (alpha << 24) | (base_r << 16) | (base_g << 8) | base_b;
                    self.blendPixel(@intCast(px), @intCast(py), aa_color);
                }
            }
        }
    }

    /// Filled circle (without AA, for compatibility)
    pub fn fillCircle(self: *Self, cx: i32, cy: i32, radius: u32, color: u32) void {
        self.fillCircleAA(cx, cy, @floatFromInt(radius), color);
    }

    /// Line with antialiasing (Wu's algorithm)
    pub fn drawLineAA(self: *Self, x0: f32, y0: f32, x1: f32, y1: f32, thickness: f32, color: u32) void {
        const base_r = (color >> 16) & 0xFF;
        const base_g = (color >> 8) & 0xFF;
        const base_b = color & 0xFF;

        const dx = x1 - x0;
        const dy = y1 - y0;
        const length = @sqrt(dx * dx + dy * dy);
        if (length < 0.001) return;

        const half_t = thickness / 2.0;

        // Bounding box
        const min_x: i32 = @intFromFloat(@min(x0, x1) - half_t - 1);
        const max_x: i32 = @intFromFloat(@max(x0, x1) + half_t + 1);
        const min_y: i32 = @intFromFloat(@min(y0, y1) - half_t - 1);
        const max_y: i32 = @intFromFloat(@max(y0, y1) + half_t + 1);

        var py: i32 = min_y;
        while (py <= max_y) : (py += 1) {
            var px: i32 = min_x;
            while (px <= max_x) : (px += 1) {
                if (px < 0 or py < 0) continue;

                const fpx: f32 = @floatFromInt(px);
                const fpy: f32 = @floatFromInt(py);

                // Project point onto line
                const t = ((fpx - x0) * dx + (fpy - y0) * dy) / (length * length);
                const clamped_t = @max(0.0, @min(1.0, t));

                // Closest point on line
                const closest_x = x0 + clamped_t * dx;
                const closest_y = y0 + clamped_t * dy;

                // Distance to line
                const dist_x = fpx - closest_x;
                const dist_y = fpy - closest_y;
                const dist = @sqrt(dist_x * dist_x + dist_y * dist_y);

                if (dist < half_t + 0.5) {
                    const alpha_f = @max(0.0, @min(1.0, half_t + 0.5 - dist));
                    const alpha: u32 = @intFromFloat(alpha_f * 255);
                    if (alpha > 0) {
                        const aa_color = (alpha << 24) | (base_r << 16) | (base_g << 8) | base_b;
                        self.blendPixel(@intCast(px), @intCast(py), aa_color);
                    }
                }
            }
        }
    }

    /// Line (for compatibility)
    pub fn drawLine(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, thickness: u32, color: u32) void {
        self.drawLineAA(@floatFromInt(x0), @floatFromInt(y0), @floatFromInt(x1), @floatFromInt(y1), @floatFromInt(thickness), color);
    }

    /// Alpha blending pixel
    pub fn blendPixel(self: *Self, x: u32, y: u32, color: u32) void {
        if (x >= self.width or y >= self.height) return;

        const alpha = (color >> 24) & 0xFF;
        if (alpha == 0) return;
        if (alpha == 255) {
            self.setPixel(x, y, color);
            return;
        }

        const pixels: [*]u32 = @ptrCast(@alignCast(self.data.ptr));
        const idx = y * (self.stride / 4) + x;
        const bg = pixels[idx];

        const src_r = (color >> 16) & 0xFF;
        const src_g = (color >> 8) & 0xFF;
        const src_b = color & 0xFF;

        const dst_r = (bg >> 16) & 0xFF;
        const dst_g = (bg >> 8) & 0xFF;
        const dst_b = bg & 0xFF;

        const out_r = (src_r * alpha + dst_r * (255 - alpha)) / 255;
        const out_g = (src_g * alpha + dst_g * (255 - alpha)) / 255;
        const out_b = (src_b * alpha + dst_b * (255 - alpha)) / 255;

        pixels[idx] = 0xFF000000 | (out_r << 16) | (out_g << 8) | out_b;
    }
};

fn createShmFile(size: usize) ?c_int {
    // Use memfd_create
    const name = "moon-code-shm";
    const fd = @as(c_int, @intCast(std.posix.system.memfd_create(name, 0)));
    if (fd < 0) {
        return null;
    }

    // Use C ftruncate
    if (c.ftruncate(fd, @intCast(size)) == 0) {
        return fd;
    } else {
        _ = c.close(fd);
        return null;
    }
}
