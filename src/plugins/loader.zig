const std = @import("std");
const wasm = @import("wasm_runtime.zig");

/// Plugin metadata loaded from WASM export
pub const PluginInfo = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    version: [32]u8 = [_]u8{0} ** 32,
    version_len: usize = 0,
    author: [64]u8 = [_]u8{0} ** 64,
    author_len: usize = 0,
    description: [512]u8 = [_]u8{0} ** 512,
    description_len: usize = 0,
    extensions: [64]u8 = [_]u8{0} ** 64, // comma-separated extensions: ".py,.pyw"
    extensions_len: usize = 0,
    icon_svg: [2048]u8 = [_]u8{0} ** 2048, // SVG icon data
    icon_svg_len: usize = 0,
    has_syntax: bool = false,
    has_lsp: bool = false,
    has_run: bool = false,
    has_on_char: bool = false, // Auto-insert (e.g., auto-close tags)
    has_on_enter: bool = false, // Smart Enter

    // LSP server config (from plugin)
    lsp_command: [128]u8 = [_]u8{0} ** 128,
    lsp_command_len: usize = 0,
    lsp_args: [256]u8 = [_]u8{0} ** 256,
    lsp_args_len: usize = 0,
    language_id: [32]u8 = [_]u8{0} ** 32, // e.g., "python", "javascript"
    language_id_len: usize = 0,

    pub fn getLspCommand(self: *const PluginInfo) []const u8 {
        return self.lsp_command[0..self.lsp_command_len];
    }

    pub fn getLspArgs(self: *const PluginInfo) []const u8 {
        return self.lsp_args[0..self.lsp_args_len];
    }

    pub fn getLanguageId(self: *const PluginInfo) []const u8 {
        return self.language_id[0..self.language_id_len];
    }

    pub fn getName(self: *const PluginInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getVersion(self: *const PluginInfo) []const u8 {
        return self.version[0..self.version_len];
    }

    pub fn getAuthor(self: *const PluginInfo) []const u8 {
        return self.author[0..self.author_len];
    }

    pub fn getDescription(self: *const PluginInfo) []const u8 {
        return self.description[0..self.description_len];
    }

    pub fn getExtensions(self: *const PluginInfo) []const u8 {
        return self.extensions[0..self.extensions_len];
    }

    pub fn getIconSvg(self: *const PluginInfo) []const u8 {
        return self.icon_svg[0..self.icon_svg_len];
    }
};

/// Token type for syntax highlighting
pub const TokenType = enum(u8) {
    normal = 0,
    keyword = 1,
    type_name = 2,
    builtin = 3,
    string = 4,
    number = 5,
    comment = 6,
    function = 7,
    operator = 8,
    punctuation = 9,
    field = 10,
    error_tok = 11,
    warning_tok = 12,
};

/// Token returned by syntax highlighter (packed for WASM compatibility)
pub const WasmToken = extern struct {
    start: u32,
    len: u16,
    kind: u8,
    _pad: u8 = 0,
};

/// Plugin state
pub const PluginState = enum {
    unloaded,
    loading,
    active,
    error_state,
};

/// Loaded plugin instance
pub const Plugin = struct {
    info: PluginInfo = .{},
    state: PluginState = .unloaded,
    path: [512]u8 = [_]u8{0} ** 512,
    path_len: usize = 0,

    // WASM runtime
    store: ?wasm.Store = null,
    module: ?wasm.Module = null,
    instance: ?wasm.Instance = null,

    // Cached function exports
    fn_tokenize: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_name: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_version: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_author: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_description: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_icon: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_icon_len: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_extensions: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_run_command: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_run_command_len: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_on_char: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_on_enter: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_lsp_command: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_lsp_command_len: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_lsp_args: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_lsp_args_len: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_language_id: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,
    fn_get_language_id_len: ?@import("wasm_runtime.zig").c.wasmtime_func_t = null,

    pub fn getPath(self: *const Plugin) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn deinit(self: *Plugin) void {
        // WASM resources cleanup handled by store
        if (self.store) |*store| {
            store.deinit();
        }
        if (self.module) |*module| {
            module.deinit();
        }
        self.store = null;
        self.module = null;
        self.instance = null;
        self.state = .unloaded;
    }
};

/// Plugin loader manages all plugins
pub const PluginLoader = struct {
    plugins: [MAX_PLUGINS]Plugin = [_]Plugin{.{}} ** MAX_PLUGINS,
    plugin_count: usize = 0,
    allocator: std.mem.Allocator,

    const MAX_PLUGINS = 32;
    const Self = @This();

    // WASM memory layout for plugin communication
    const WASM_INPUT_OFFSET: u32 = 0x10000; // 64KB offset for input buffer
    const WASM_OUTPUT_OFFSET: u32 = 0x20000; // 128KB offset for output buffer
    const WASM_MAX_INPUT: u32 = 0x10000; // 64KB max input
    const WASM_MAX_OUTPUT: u32 = 0x10000; // 64KB max output

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (0..self.plugin_count) |i| {
            self.plugins[i].deinit();
        }
        self.plugin_count = 0;
    }

    /// Load plugin from WASM file
    pub fn loadPlugin(self: *Self, path: []const u8) !usize {
        if (self.plugin_count >= MAX_PLUGINS) {
            return error.TooManyPlugins;
        }

        const idx = self.plugin_count;
        var plugin = &self.plugins[idx];

        plugin.state = .loading;

        // Store path
        const copy_len = @min(path.len, plugin.path.len);
        @memcpy(plugin.path[0..copy_len], path[0..copy_len]);
        plugin.path_len = copy_len;

        // Get WASM engine
        const engine = wasm.getEngine() catch {
            plugin.state = .error_state;
            return error.WasmEngineError;
        };

        // Load and compile module
        plugin.module = wasm.Module.fromFile(engine, path) catch {
            plugin.state = .error_state;
            return error.ModuleLoadError;
        };

        // Create store
        plugin.store = wasm.Store.init(engine) catch {
            plugin.module.?.deinit();
            plugin.module = null;
            plugin.state = .error_state;
            return error.StoreCreationError;
        };

        // Create instance
        plugin.instance = wasm.Instance.init(&plugin.store.?, &plugin.module.?) catch {
            plugin.store.?.deinit();
            plugin.module.?.deinit();
            plugin.store = null;
            plugin.module = null;
            plugin.state = .error_state;
            return error.InstanceCreationError;
        };

        // Cache exported functions
        plugin.fn_tokenize = plugin.instance.?.getFunc("tokenize") catch null;
        plugin.fn_get_name = plugin.instance.?.getFunc("get_name") catch null;
        plugin.fn_get_version = plugin.instance.?.getFunc("get_version") catch null;
        plugin.fn_get_author = plugin.instance.?.getFunc("get_author") catch null;
        plugin.fn_get_description = plugin.instance.?.getFunc("get_description") catch null;
        plugin.fn_get_icon = plugin.instance.?.getFunc("get_icon") catch null;
        plugin.fn_get_icon_len = plugin.instance.?.getFunc("get_icon_len") catch null;
        plugin.fn_get_extensions = plugin.instance.?.getFunc("get_extensions") catch null;
        plugin.fn_get_run_command = plugin.instance.?.getFunc("get_run_command") catch null;
        plugin.fn_get_run_command_len = plugin.instance.?.getFunc("get_run_command_len") catch null;
        plugin.fn_on_char = plugin.instance.?.getFunc("on_char") catch null;
        plugin.fn_on_enter = plugin.instance.?.getFunc("on_enter") catch null;
        plugin.fn_get_lsp_command = plugin.instance.?.getFunc("get_lsp_command") catch null;
        plugin.fn_get_lsp_command_len = plugin.instance.?.getFunc("get_lsp_command_len") catch null;
        plugin.fn_get_lsp_args = plugin.instance.?.getFunc("get_lsp_args") catch null;
        plugin.fn_get_lsp_args_len = plugin.instance.?.getFunc("get_lsp_args_len") catch null;
        plugin.fn_get_language_id = plugin.instance.?.getFunc("get_language_id") catch null;
        plugin.fn_get_language_id_len = plugin.instance.?.getFunc("get_language_id_len") catch null;

        // Load plugin info
        self.loadPluginInfo(plugin);

        plugin.state = .active;
        self.plugin_count += 1;

        return idx;
    }

    fn loadPluginInfo(self: *Self, plugin: *Plugin) void {
        _ = self;

        var memory = plugin.instance.?.getMemory() catch return;

        // Get plugin name from WASM
        if (plugin.fn_get_name != null and plugin.instance != null) {
            const name_ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_name.?) catch 0;
            if (name_ptr > 0) {
                const name_data = plugin.instance.?.readMemory(&memory, @intCast(name_ptr), 64) catch return;
                var name_len: usize = 0;
                while (name_len < 64 and name_data[name_len] != 0) : (name_len += 1) {}
                @memcpy(plugin.info.name[0..name_len], name_data[0..name_len]);
                plugin.info.name_len = name_len;
            }
        }

        // Get version
        if (plugin.fn_get_version != null and plugin.instance != null) {
            const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_version.?) catch 0;
            if (ptr > 0) {
                const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), 32) catch return;
                var len: usize = 0;
                while (len < 32 and data[len] != 0) : (len += 1) {}
                @memcpy(plugin.info.version[0..len], data[0..len]);
                plugin.info.version_len = len;
            }
        }

        // Get author
        if (plugin.fn_get_author != null and plugin.instance != null) {
            const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_author.?) catch 0;
            if (ptr > 0) {
                const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), 64) catch return;
                var len: usize = 0;
                while (len < 64 and data[len] != 0) : (len += 1) {}
                @memcpy(plugin.info.author[0..len], data[0..len]);
                plugin.info.author_len = len;
            }
        }

        // Get description
        if (plugin.fn_get_description != null and plugin.instance != null) {
            const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_description.?) catch 0;
            if (ptr > 0) {
                const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), 512) catch return;
                var len: usize = 0;
                while (len < 512 and data[len] != 0) : (len += 1) {}
                @memcpy(plugin.info.description[0..len], data[0..len]);
                plugin.info.description_len = len;
            }
        }

        // Get SVG icon
        if (plugin.fn_get_icon != null and plugin.fn_get_icon_len != null and plugin.instance != null) {
            const icon_len = plugin.instance.?.callFuncI32(&plugin.fn_get_icon_len.?) catch 0;
            if (icon_len > 0 and icon_len < 2048) {
                const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_icon.?) catch 0;
                if (ptr > 0) {
                    const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), @intCast(icon_len)) catch return;
                    const len: usize = @intCast(icon_len);
                    @memcpy(plugin.info.icon_svg[0..len], data[0..len]);
                    plugin.info.icon_svg_len = len;
                }
            }
        }

        // Get extensions
        if (plugin.fn_get_extensions != null and plugin.instance != null) {
            const ext_ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_extensions.?) catch 0;
            if (ext_ptr > 0) {
                const ext_data = plugin.instance.?.readMemory(&memory, @intCast(ext_ptr), 64) catch return;
                var ext_len: usize = 0;
                while (ext_len < 64 and ext_data[ext_len] != 0) : (ext_len += 1) {}
                @memcpy(plugin.info.extensions[0..ext_len], ext_data[0..ext_len]);
                plugin.info.extensions_len = ext_len;
            }
        }

        // Get LSP command (if plugin supports LSP)
        if (plugin.fn_get_lsp_command != null and plugin.fn_get_lsp_command_len != null and plugin.instance != null) {
            const cmd_len = plugin.instance.?.callFuncI32(&plugin.fn_get_lsp_command_len.?) catch 0;
            if (cmd_len > 0 and cmd_len < 128) {
                const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_lsp_command.?) catch 0;
                if (ptr > 0) {
                    const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), @intCast(cmd_len)) catch return;
                    const len: usize = @intCast(cmd_len);
                    @memcpy(plugin.info.lsp_command[0..len], data[0..len]);
                    plugin.info.lsp_command_len = len;
                }
            }
        }

        // Get LSP args
        if (plugin.fn_get_lsp_args != null and plugin.fn_get_lsp_args_len != null and plugin.instance != null) {
            const args_len = plugin.instance.?.callFuncI32(&plugin.fn_get_lsp_args_len.?) catch 0;
            if (args_len > 0 and args_len < 256) {
                const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_lsp_args.?) catch 0;
                if (ptr > 0) {
                    const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), @intCast(args_len)) catch return;
                    const len: usize = @intCast(args_len);
                    @memcpy(plugin.info.lsp_args[0..len], data[0..len]);
                    plugin.info.lsp_args_len = len;
                }
            }
        }

        // Get language ID
        if (plugin.fn_get_language_id != null and plugin.fn_get_language_id_len != null and plugin.instance != null) {
            const id_len = plugin.instance.?.callFuncI32(&plugin.fn_get_language_id_len.?) catch 0;
            if (id_len > 0 and id_len < 32) {
                const ptr = plugin.instance.?.callFuncI32(&plugin.fn_get_language_id.?) catch 0;
                if (ptr > 0) {
                    const data = plugin.instance.?.readMemory(&memory, @intCast(ptr), @intCast(id_len)) catch return;
                    const len: usize = @intCast(id_len);
                    @memcpy(plugin.info.language_id[0..len], data[0..len]);
                    plugin.info.language_id_len = len;
                }
            }
        }

        // Check capabilities
        plugin.info.has_syntax = plugin.fn_tokenize != null;
        plugin.info.has_lsp = plugin.info.lsp_command_len > 0;
        plugin.info.has_on_char = plugin.fn_on_char != null;
        plugin.info.has_on_enter = plugin.fn_on_enter != null;
    }

    /// Find plugin for file extension
    pub fn findPluginForFile(self: *const Self, filename: []const u8) ?usize {
        const ext_start = std.mem.lastIndexOfScalar(u8, filename, '.') orelse return null;
        const ext = filename[ext_start..];

        for (0..self.plugin_count) |i| {
            const plugin = &self.plugins[i];
            if (plugin.state != .active) continue;

            const exts = plugin.info.getExtensions();
            var iter = std.mem.splitScalar(u8, exts, ',');
            while (iter.next()) |supported_ext| {
                if (std.mem.eql(u8, ext, supported_ext)) {
                    return i;
                }
            }
        }

        return null;
    }

    /// Tokenize source code using WASM plugin
    pub fn tokenize(self: *Self, plugin_idx: usize, source: []const u8, tokens: []WasmToken) usize {
        if (plugin_idx >= self.plugin_count) return 0;

        var plugin = &self.plugins[plugin_idx];
        if (plugin.state != .active) return 0;
        if (plugin.fn_tokenize == null or plugin.instance == null) return 0;

        var instance = &plugin.instance.?;

        // Get WASM memory
        var memory = instance.getMemory() catch return 0;

        // Write source to WASM memory
        const src_len: u32 = @intCast(@min(source.len, WASM_MAX_INPUT));
        instance.writeMemory(&memory, WASM_INPUT_OFFSET, source[0..src_len]) catch return 0;

        // Call tokenize function
        const max_tokens: u32 = @intCast(@min(tokens.len, WASM_MAX_OUTPUT / @sizeOf(WasmToken)));
        const count = instance.callTokenize(
            &plugin.fn_tokenize.?,
            WASM_INPUT_OFFSET,
            src_len,
            WASM_OUTPUT_OFFSET,
            max_tokens,
        ) catch return 0;

        if (count == 0) return 0;

        // Read tokens from WASM memory
        const token_bytes = @as(usize, count) * @sizeOf(WasmToken);
        const output_data = instance.readMemory(&memory, WASM_OUTPUT_OFFSET, token_bytes) catch return 0;

        // Copy tokens
        const token_count = @min(count, tokens.len);
        const src_tokens: [*]const WasmToken = @ptrCast(@alignCast(output_data.ptr));
        @memcpy(tokens[0..token_count], src_tokens[0..token_count]);

        return token_count;
    }

    /// Result of on_char call
    pub const OnCharResult = struct {
        insert_text: []const u8,
        delete_after: u16, // chars to delete after cursor before inserting
    };

    /// Call on_char to get auto-insert text (e.g., auto-close tag)
    /// Returns text to insert and how many chars to delete after cursor first
    pub fn onChar(self: *Self, plugin_idx: usize, source: []const u8, cursor: u32, char: u8, buf: []u8) ?OnCharResult {
        if (plugin_idx >= self.plugin_count) return null;

        var plugin = &self.plugins[plugin_idx];
        if (plugin.state != .active) return null;
        if (plugin.fn_on_char == null or plugin.instance == null) return null;

        var instance = &plugin.instance.?;

        // Get WASM memory
        var memory = instance.getMemory() catch return null;

        // Write source to WASM memory
        const src_len: u32 = @intCast(@min(source.len, WASM_MAX_INPUT));
        instance.writeMemory(&memory, WASM_INPUT_OFFSET, source[0..src_len]) catch return null;

        // Call on_char function
        // Returns: (delete_after << 16) | insert_len
        const result = instance.callOnChar(
            &plugin.fn_on_char.?,
            WASM_INPUT_OFFSET,
            src_len,
            cursor,
            char,
            WASM_OUTPUT_OFFSET,
        ) catch return null;

        const insert_len: u16 = @intCast(result & 0xFFFF);
        const delete_after: u16 = @intCast((result >> 16) & 0xFFFF);

        if (insert_len == 0 and delete_after == 0) return null;
        if (insert_len > buf.len) return null;

        // Read insert text from WASM memory
        if (insert_len > 0) {
            const output_data = instance.readMemory(&memory, WASM_OUTPUT_OFFSET, insert_len) catch return null;
            @memcpy(buf[0..insert_len], output_data);
        }

        return OnCharResult{
            .insert_text = buf[0..insert_len],
            .delete_after = delete_after,
        };
    }

    /// Call on_enter to get smart Enter text (e.g., indentation)
    /// Returns the text to insert instead of plain newline, or null for default behavior
    pub fn onEnter(self: *Self, plugin_idx: usize, source: []const u8, cursor: u32, buf: []u8) ?[]const u8 {
        if (plugin_idx >= self.plugin_count) return null;

        var plugin = &self.plugins[plugin_idx];
        if (plugin.state != .active) return null;
        if (plugin.fn_on_enter == null or plugin.instance == null) return null;

        var instance = &plugin.instance.?;

        // Get WASM memory
        var memory = instance.getMemory() catch return null;

        // Write source to WASM memory
        const src_len: u32 = @intCast(@min(source.len, WASM_MAX_INPUT));
        instance.writeMemory(&memory, WASM_INPUT_OFFSET, source[0..src_len]) catch return null;

        // Call on_enter function
        const insert_len = instance.callOnEnter(
            &plugin.fn_on_enter.?,
            WASM_INPUT_OFFSET,
            src_len,
            cursor,
            WASM_OUTPUT_OFFSET,
        ) catch return null;

        if (insert_len == 0 or insert_len > buf.len) return null;

        // Read insert text from WASM memory
        const output_data = instance.readMemory(&memory, WASM_OUTPUT_OFFSET, insert_len) catch return null;
        @memcpy(buf[0..insert_len], output_data);
        return buf[0..insert_len];
    }

    /// Get active plugins count
    pub fn activeCount(self: *const Self) usize {
        var count: usize = 0;
        for (0..self.plugin_count) |i| {
            if (self.plugins[i].state == .active) {
                count += 1;
            }
        }
        return count;
    }

    /// Get plugin by index
    pub fn getPlugin(self: *const Self, idx: usize) ?*const Plugin {
        if (idx >= self.plugin_count) return null;
        return &self.plugins[idx];
    }

    /// Get run command from plugin (returns null if plugin doesn't support run)
    pub fn getRunCommand(self: *Self, plugin_idx: usize, buf: []u8) ?[]const u8 {
        if (plugin_idx >= self.plugin_count) return null;

        var plugin = &self.plugins[plugin_idx];
        if (plugin.state != .active) return null;
        if (plugin.fn_get_run_command == null or plugin.fn_get_run_command_len == null) return null;
        if (plugin.instance == null) return null;

        var instance = &plugin.instance.?;

        // Get command length
        const cmd_len = instance.callFuncI32(&plugin.fn_get_run_command_len.?) catch return null;
        if (cmd_len == 0 or cmd_len > buf.len) return null;

        // Get command pointer
        const cmd_ptr = instance.callFuncI32(&plugin.fn_get_run_command.?) catch return null;
        if (cmd_ptr == 0) return null;

        // Read from WASM memory
        var memory = instance.getMemory() catch return null;
        const cmd_data = instance.readMemory(&memory, @intCast(cmd_ptr), @intCast(cmd_len)) catch return null;

        @memcpy(buf[0..@intCast(cmd_len)], cmd_data);
        return buf[0..@intCast(cmd_len)];
    }
};

/// Global plugin loader instance
var g_plugin_loader: ?PluginLoader = null;
var g_plugins_initialized: bool = false;

/// Get plugins directory path (~/.mncode/plugins/)
pub fn getPluginsDir(buf: []u8) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    const path = std.fmt.bufPrint(buf, "{s}/.mncode/plugins", .{home}) catch return null;
    return path;
}

/// Ensure ~/.mncode/plugins/ directory exists
pub fn ensurePluginsDir() !void {
    var buf: [512]u8 = undefined;
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

    // Create ~/.mncode if not exists
    const mncode_path = std.fmt.bufPrint(&buf, "{s}/.mncode", .{home}) catch return error.PathTooLong;
    std.fs.makeDirAbsolute(mncode_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create ~/.mncode/plugins if not exists
    const plugins_path = std.fmt.bufPrint(&buf, "{s}/.mncode/plugins", .{home}) catch return error.PathTooLong;
    std.fs.makeDirAbsolute(plugins_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

pub fn getLoader() *PluginLoader {
    if (g_plugin_loader == null) {
        g_plugin_loader = PluginLoader.init(std.heap.page_allocator);
    }
    return &g_plugin_loader.?;
}

/// Get disabled plugins config path
fn getDisabledConfigPath(buf: []u8) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    return std.fmt.bufPrint(buf, "{s}/.mncode/config/disabled.conf", .{home}) catch null;
}

/// Ensure config directory exists
fn ensureConfigDir() void {
    var buf: [512]u8 = undefined;
    const home = std.posix.getenv("HOME") orelse return;
    const config_path = std.fmt.bufPrint(&buf, "{s}/.mncode/config", .{home}) catch return;
    std.fs.makeDirAbsolute(config_path) catch {};
}

/// Check if plugin is disabled
pub fn isPluginDisabled(plugin_name: []const u8) bool {
    var path_buf: [512]u8 = undefined;
    const config_path = getDisabledConfigPath(&path_buf) orelse return false;

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return false;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return false;

    // Check each line
    var lines = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and std.mem.eql(u8, trimmed, plugin_name)) {
            return true;
        }
    }
    return false;
}

/// Disable plugin (add to disabled.conf)
pub fn disablePlugin(plugin_name: []const u8) !void {
    ensureConfigDir();

    var path_buf: [512]u8 = undefined;
    const config_path = getDisabledConfigPath(&path_buf) orelse return error.NoPath;

    // Read existing content
    var existing: [4096]u8 = undefined;
    var existing_len: usize = 0;

    if (std.fs.openFileAbsolute(config_path, .{})) |file| {
        existing_len = file.readAll(&existing) catch 0;
        file.close();
    } else |_| {}

    // Append plugin name
    const file = std.fs.createFileAbsolute(config_path, .{}) catch return error.CantCreateFile;
    defer file.close();

    if (existing_len > 0) {
        _ = file.write(existing[0..existing_len]) catch {};
        if (existing[existing_len - 1] != '\n') {
            _ = file.write("\n") catch {};
        }
    }
    _ = file.write(plugin_name) catch {};
    _ = file.write("\n") catch {};
}

/// Enable plugin (remove from disabled.conf)
pub fn enablePlugin(plugin_name: []const u8) !void {
    var path_buf: [512]u8 = undefined;
    const config_path = getDisabledConfigPath(&path_buf) orelse return error.NoPath;

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return;

    var buf: [4096]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return;
    file.close();

    // Rewrite without the plugin
    const out_file = std.fs.createFileAbsolute(config_path, .{}) catch return;
    defer out_file.close();

    var lines = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and !std.mem.eql(u8, trimmed, plugin_name)) {
            _ = out_file.write(trimmed) catch {};
            _ = out_file.write("\n") catch {};
        }
    }
}

/// Uninstall plugin (move to trash)
pub fn uninstallPlugin(plugin_path: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    // Get filename from path
    var filename: []const u8 = plugin_path;
    if (std.mem.lastIndexOfScalar(u8, plugin_path, '/')) |idx| {
        filename = plugin_path[idx + 1 ..];
    }

    // Create trash directory
    var trash_buf: [512]u8 = undefined;
    const trash_dir = std.fmt.bufPrint(&trash_buf, "{s}/.local/share/Trash/files", .{home}) catch return error.PathTooLong;
    std.fs.makeDirAbsolute(trash_dir) catch {};

    // Move file to trash
    var dest_buf: [1024]u8 = undefined;
    const dest_path = std.fmt.bufPrint(&dest_buf, "{s}/{s}", .{ trash_dir, filename }) catch return error.PathTooLong;

    std.fs.renameAbsolute(plugin_path, dest_path) catch |err| {
        // If rename fails, try copy + delete
        if (err == error.RenameAcrossMountPoints) {
            std.fs.copyFileAbsolute(plugin_path, dest_path, .{}) catch return err;
            std.fs.deleteFileAbsolute(plugin_path) catch return err;
        } else {
            return err;
        }
    };
}

/// Disabled plugin info (minimal, for display purposes)
pub const DisabledPluginInfo = struct {
    name: [128]u8 = [_]u8{0} ** 128,
    name_len: usize = 0,
    path: [512]u8 = [_]u8{0} ** 512,
    path_len: usize = 0,

    pub fn getName(self: *const DisabledPluginInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getPath(self: *const DisabledPluginInfo) []const u8 {
        return self.path[0..self.path_len];
    }
};

/// Global storage for disabled plugins list
var g_disabled_plugins: [32]DisabledPluginInfo = undefined;
var g_disabled_plugin_count: usize = 0;

/// Get list of disabled plugins in the plugins folder
pub fn getDisabledPlugins() []const DisabledPluginInfo {
    return g_disabled_plugins[0..g_disabled_plugin_count];
}

/// Scan for disabled plugins (call periodically)
pub fn scanDisabledPlugins() void {
    g_disabled_plugin_count = 0;

    var path_buf: [512]u8 = undefined;
    const plugins_dir = getPluginsDir(&path_buf) orelse return;

    var dir = std.fs.openDirAbsolute(plugins_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".wasm")) continue;

        // Only include if disabled
        if (!isPluginDisabled(entry.name)) continue;

        if (g_disabled_plugin_count >= 32) break;

        var info = &g_disabled_plugins[g_disabled_plugin_count];

        // Store filename as name (strip .wasm extension)
        const name_end = if (std.mem.endsWith(u8, entry.name, ".wasm"))
            entry.name.len - 5
        else
            entry.name.len;
        const copy_len = @min(name_end, info.name.len);
        @memcpy(info.name[0..copy_len], entry.name[0..copy_len]);
        info.name_len = copy_len;

        // Store full path
        const full_path = std.fmt.bufPrint(&info.path, "{s}/{s}", .{ plugins_dir, entry.name }) catch continue;
        info.path_len = full_path.len;

        g_disabled_plugin_count += 1;
    }
}

/// Remove plugins that no longer exist on disk
/// Returns number of removed plugins
pub fn cleanupMissingPlugins() usize {
    var loader = getLoader();
    var i: usize = 0;
    var removed: usize = 0;

    while (i < loader.plugin_count) {
        const plugin = &loader.plugins[i];
        const path = plugin.getPath();

        // Check if file still exists
        if (std.fs.accessAbsolute(path, .{})) |_| {
            i += 1;
        } else |_| {
            // File doesn't exist - remove from list
            plugin.deinit();
            // Shift remaining plugins
            var j = i;
            while (j + 1 < loader.plugin_count) : (j += 1) {
                loader.plugins[j] = loader.plugins[j + 1];
            }
            loader.plugin_count -= 1;
            removed += 1;
            // Don't increment i - check same index again
        }
    }
    return removed;
}

/// Check for new plugins and load them (called from main loop)
/// Returns total number of changes (added + removed plugins)
pub fn checkAndLoadNewPlugins() usize {
    // Ensure directory exists (creates if not)
    ensurePluginsDir() catch return 0;

    // First cleanup missing plugins
    const removed = cleanupMissingPlugins();

    var path_buf: [512]u8 = undefined;
    const plugins_dir = getPluginsDir(&path_buf) orelse return removed;

    var dir = std.fs.openDirAbsolute(plugins_dir, .{ .iterate = true }) catch return removed;
    defer dir.close();

    var loader = getLoader();
    var loaded: usize = 0;

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".wasm")) continue;

        // Check if disabled
        if (isPluginDisabled(entry.name)) continue;

        // Build full path
        var full_path_buf: [1024]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ plugins_dir, entry.name }) catch continue;

        // Check if already loaded
        var already_loaded = false;
        for (0..loader.plugin_count) |i| {
            const p = &loader.plugins[i];
            if (std.mem.eql(u8, p.getPath(), full_path)) {
                already_loaded = true;
                break;
            }
        }
        if (already_loaded) continue;

        // Try to load
        _ = loader.loadPlugin(full_path) catch continue;
        loaded += 1;
    }

    // Also scan for disabled plugins
    scanDisabledPlugins();

    return loaded + removed;
}

pub fn deinitLoader() void {
    if (g_plugin_loader) |*loader| {
        loader.deinit();
        g_plugin_loader = null;
    }
    g_plugins_initialized = false;
    wasm.deinitRuntime();
}
