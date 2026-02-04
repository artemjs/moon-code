const std = @import("std");
pub const c = @cImport({
    @cInclude("wasmtime.h");
});

pub const WasmError = error{
    EngineCreationFailed,
    StoreCreationFailed,
    ModuleCompilationFailed,
    InstanceCreationFailed,
    FunctionNotFound,
    FunctionCallFailed,
    MemoryNotFound,
    InvalidModule,
};

/// WASM Engine - compiler and runtime
pub const Engine = struct {
    ptr: *c.wasm_engine_t,

    pub fn init() !Engine {
        const engine = c.wasm_engine_new();
        if (engine == null) return WasmError.EngineCreationFailed;
        return Engine{ .ptr = engine.? };
    }

    pub fn deinit(self: *Engine) void {
        c.wasm_engine_delete(self.ptr);
    }
};

/// WASM Store - execution context
pub const Store = struct {
    ptr: *c.wasmtime_store_t,
    context: *c.wasmtime_context_t,

    pub fn init(engine: *Engine) !Store {
        const store = c.wasmtime_store_new(engine.ptr, null, null);
        if (store == null) return WasmError.StoreCreationFailed;
        const ctx = c.wasmtime_store_context(store.?) orelse return WasmError.StoreCreationFailed;
        return Store{ .ptr = store.?, .context = ctx };
    }

    pub fn deinit(self: *Store) void {
        c.wasmtime_store_delete(self.ptr);
    }
};

/// WASM Module - compiled module
pub const Module = struct {
    ptr: *c.wasmtime_module_t,

    pub fn fromFile(engine: *Engine, path: []const u8) !Module {
        var err: ?*c.wasmtime_error_t = null;
        var module: ?*c.wasmtime_module_t = null;

        // Read the file
        const file = std.fs.openFileAbsolute(path, .{}) catch return WasmError.InvalidModule;
        defer file.close();

        const stat = file.stat() catch return WasmError.InvalidModule;
        const size = stat.size;

        const allocator = std.heap.page_allocator;
        const buffer = allocator.alloc(u8, size) catch return WasmError.InvalidModule;
        defer allocator.free(buffer);

        const bytes_read = file.readAll(buffer) catch return WasmError.InvalidModule;
        if (bytes_read != size) return WasmError.InvalidModule;

        // Compile the module
        err = c.wasmtime_module_new(engine.ptr, buffer.ptr, buffer.len, &module);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.ModuleCompilationFailed;
        }
        if (module == null) return WasmError.ModuleCompilationFailed;

        return Module{ .ptr = module.? };
    }

    pub fn fromBytes(engine: *Engine, bytes: []const u8) !Module {
        var err: ?*c.wasmtime_error_t = null;
        var module: ?*c.wasmtime_module_t = null;

        err = c.wasmtime_module_new(engine.ptr, bytes.ptr, bytes.len, &module);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.ModuleCompilationFailed;
        }
        if (module == null) return WasmError.ModuleCompilationFailed;

        return Module{ .ptr = module.? };
    }

    pub fn deinit(self: *Module) void {
        c.wasmtime_module_delete(self.ptr);
    }
};

/// WASM Instance - module instance
pub const Instance = struct {
    instance: c.wasmtime_instance_t,
    store: *Store,
    module: *Module,

    pub fn init(store: *Store, module: *Module) !Instance {
        var err: ?*c.wasmtime_error_t = null;
        var instance: c.wasmtime_instance_t = undefined;
        var trap: ?*c.wasm_trap_t = null;

        // Create instance without imports (for now)
        err = c.wasmtime_instance_new(store.context, module.ptr, null, 0, &instance, &trap);

        if (trap != null) {
            c.wasm_trap_delete(trap);
            return WasmError.InstanceCreationFailed;
        }
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.InstanceCreationFailed;
        }

        return Instance{
            .instance = instance,
            .store = store,
            .module = module,
        };
    }

    /// Get an exported function
    pub fn getFunc(self: *Instance, name: []const u8) !c.wasmtime_func_t {
        var func: c.wasmtime_extern_t = undefined;
        var found: bool = false;

        found = c.wasmtime_instance_export_get(
            self.store.context,
            &self.instance,
            name.ptr,
            name.len,
            &func,
        );

        if (!found or func.kind != c.WASMTIME_EXTERN_FUNC) {
            return WasmError.FunctionNotFound;
        }

        return func.of.func;
    }

    /// Get module memory
    pub fn getMemory(self: *Instance) !c.wasmtime_memory_t {
        var mem: c.wasmtime_extern_t = undefined;
        var found: bool = false;

        found = c.wasmtime_instance_export_get(
            self.store.context,
            &self.instance,
            "memory",
            6,
            &mem,
        );

        if (!found or mem.kind != c.WASMTIME_EXTERN_MEMORY) {
            return WasmError.MemoryNotFound;
        }

        return mem.of.memory;
    }

    /// Call a function with no arguments that returns i32
    pub fn callFuncI32(self: *Instance, func: *c.wasmtime_func_t) !i32 {
        var trap: ?*c.wasm_trap_t = null;
        var result: c.wasmtime_val_t = undefined;
        var err: ?*c.wasmtime_error_t = null;

        err = c.wasmtime_func_call(self.store.context, func, null, 0, &result, 1, &trap);

        if (trap != null) {
            c.wasm_trap_delete(trap);
            return WasmError.FunctionCallFailed;
        }
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.FunctionCallFailed;
        }

        return @intCast(result.of.i32);
    }

    /// Call the tokenize(src_ptr, src_len, out_ptr, max_tokens) -> count function
    pub fn callTokenize(self: *Instance, func: *c.wasmtime_func_t, src_ptr: u32, src_len: u32, out_ptr: u32, max_tokens: u32) !u32 {
        var trap: ?*c.wasm_trap_t = null;
        var result: c.wasmtime_val_t = undefined;
        var err: ?*c.wasmtime_error_t = null;

        var args: [4]c.wasmtime_val_t = undefined;
        args[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_ptr) } };
        args[1] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_len) } };
        args[2] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(out_ptr) } };
        args[3] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(max_tokens) } };

        err = c.wasmtime_func_call(self.store.context, func, &args, 4, &result, 1, &trap);

        if (trap != null) {
            c.wasm_trap_delete(trap);
            return WasmError.FunctionCallFailed;
        }
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.FunctionCallFailed;
        }

        return @intCast(result.of.i32);
    }

    /// Call the on_char(src_ptr, src_len, cursor, char, out_ptr) -> insert_len function
    pub fn callOnChar(self: *Instance, func: *c.wasmtime_func_t, src_ptr: u32, src_len: u32, cursor: u32, char: u32, out_ptr: u32) !u32 {
        var trap: ?*c.wasm_trap_t = null;
        var result: c.wasmtime_val_t = undefined;
        var err: ?*c.wasmtime_error_t = null;

        var args: [5]c.wasmtime_val_t = undefined;
        args[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_ptr) } };
        args[1] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_len) } };
        args[2] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(cursor) } };
        args[3] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(char) } };
        args[4] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(out_ptr) } };

        err = c.wasmtime_func_call(self.store.context, func, &args, 5, &result, 1, &trap);

        if (trap != null) {
            c.wasm_trap_delete(trap);
            return WasmError.FunctionCallFailed;
        }
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.FunctionCallFailed;
        }

        return @intCast(result.of.i32);
    }

    /// Call the on_enter(src_ptr, src_len, cursor, out_ptr) -> insert_len function
    pub fn callOnEnter(self: *Instance, func: *c.wasmtime_func_t, src_ptr: u32, src_len: u32, cursor: u32, out_ptr: u32) !u32 {
        var trap: ?*c.wasm_trap_t = null;
        var result: c.wasmtime_val_t = undefined;
        var err: ?*c.wasmtime_error_t = null;

        var args: [4]c.wasmtime_val_t = undefined;
        args[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_ptr) } };
        args[1] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(src_len) } };
        args[2] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(cursor) } };
        args[3] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(out_ptr) } };

        err = c.wasmtime_func_call(self.store.context, func, &args, 4, &result, 1, &trap);

        if (trap != null) {
            c.wasm_trap_delete(trap);
            return WasmError.FunctionCallFailed;
        }
        if (err != null) {
            c.wasmtime_error_delete(err);
            return WasmError.FunctionCallFailed;
        }

        return @intCast(result.of.i32);
    }

    /// Write data to WASM module memory
    pub fn writeMemory(self: *Instance, memory: *c.wasmtime_memory_t, offset: u32, data: []const u8) !void {
        const mem_data = c.wasmtime_memory_data(self.store.context, memory);
        const mem_size = c.wasmtime_memory_data_size(self.store.context, memory);

        if (offset + data.len > mem_size) {
            return WasmError.InvalidModule;
        }

        @memcpy(mem_data[offset..][0..data.len], data);
    }

    /// Read data from WASM module memory
    pub fn readMemory(self: *Instance, memory: *c.wasmtime_memory_t, offset: u32, len: usize) ![]const u8 {
        const mem_data = c.wasmtime_memory_data(self.store.context, memory);
        const mem_size = c.wasmtime_memory_data_size(self.store.context, memory);

        if (offset + len > mem_size) {
            return WasmError.InvalidModule;
        }

        return mem_data[offset..][0..len];
    }
};

/// Global WASM runtime
var g_engine: ?Engine = null;

pub fn getEngine() !*Engine {
    if (g_engine == null) {
        g_engine = try Engine.init();
    }
    return &g_engine.?;
}

pub fn deinitRuntime() void {
    if (g_engine) |*engine| {
        engine.deinit();
        g_engine = null;
    }
}
