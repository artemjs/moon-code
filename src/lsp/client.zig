// Universal LSP Client for Moon-code
// Manages LSP server connections for any language
// Plugins specify their LSP server command via get_lsp_command export

const std = @import("std");

/// LSP Connection state
pub const ConnectionState = enum {
    disconnected,
    connecting,
    initializing,
    ready,
    shutdown,
    error_state,
};

/// LSP Message type
pub const MessageType = enum(u8) {
    request = 1,
    response = 2,
    notification = 3,
};

/// LSP Connection - manages a single LSP server process
pub const Connection = struct {
    id: i32,
    state: ConnectionState = .disconnected,

    // Process info
    process: ?std.process.Child = null,

    // Server command (from plugin)
    command: [256]u8 = [_]u8{0} ** 256,
    command_len: usize = 0,
    args: [512]u8 = [_]u8{0} ** 512,
    args_len: usize = 0,

    // Request tracking
    next_request_id: i32 = 1,

    // Root path for workspace
    root_path: [512]u8 = [_]u8{0} ** 512,
    root_path_len: usize = 0,

    // Buffers for communication
    read_buf: [65536]u8 = undefined,
    write_buf: [65536]u8 = undefined,

    // Pending responses
    pending_requests: [64]PendingRequest = undefined,
    pending_count: usize = 0,

    // Received messages queue
    received_messages: [128]ReceivedMessage = undefined,
    received_count: usize = 0,

    pub fn getCommand(self: *const Connection) []const u8 {
        return self.command[0..self.command_len];
    }

    pub fn getRootPath(self: *const Connection) []const u8 {
        return self.root_path[0..self.root_path_len];
    }
};

/// Pending request awaiting response
pub const PendingRequest = struct {
    id: i32,
    method: [64]u8 = [_]u8{0} ** 64,
    method_len: usize = 0,
    timestamp_ms: i64 = 0,
    callback_id: u32 = 0, // For plugin callbacks
};

/// Received message from LSP server
pub const ReceivedMessage = struct {
    msg_type: MessageType = .notification,
    id: i32 = 0, // For responses
    method: [64]u8 = [_]u8{0} ** 64,
    method_len: usize = 0,
    // Result/params stored in shared buffer
    data_offset: usize = 0,
    data_len: usize = 0,
};

/// Completion item from LSP
pub const CompletionItem = struct {
    label: [128]u8 = [_]u8{0} ** 128,
    label_len: usize = 0,
    kind: u8 = 1, // CompletionItemKind
    detail: [256]u8 = [_]u8{0} ** 256,
    detail_len: usize = 0,
    insert_text: [256]u8 = [_]u8{0} ** 256,
    insert_text_len: usize = 0,
    sort_text: [64]u8 = [_]u8{0} ** 64,
    sort_text_len: usize = 0,

    pub fn getLabel(self: *const CompletionItem) []const u8 {
        return self.label[0..self.label_len];
    }

    pub fn getDetail(self: *const CompletionItem) []const u8 {
        return self.detail[0..self.detail_len];
    }

    pub fn getInsertText(self: *const CompletionItem) []const u8 {
        if (self.insert_text_len > 0) {
            return self.insert_text[0..self.insert_text_len];
        }
        return self.label[0..self.label_len];
    }
};

/// Diagnostic from LSP
pub const Diagnostic = struct {
    start_line: u32 = 0,
    start_col: u32 = 0,
    end_line: u32 = 0,
    end_col: u32 = 0,
    severity: u8 = 1, // 1=error, 2=warning, 3=info, 4=hint
    message: [512]u8 = [_]u8{0} ** 512,
    message_len: usize = 0,
    source: [64]u8 = [_]u8{0} ** 64,
    source_len: usize = 0,
    code: [32]u8 = [_]u8{0} ** 32,
    code_len: usize = 0,

    pub fn getMessage(self: *const Diagnostic) []const u8 {
        return self.message[0..self.message_len];
    }
};

/// Hover info from LSP
pub const HoverInfo = struct {
    content: [4096]u8 = [_]u8{0} ** 4096,
    content_len: usize = 0,
    is_markdown: bool = false,

    pub fn getContent(self: *const HoverInfo) []const u8 {
        return self.content[0..self.content_len];
    }
};

/// Location for goto definition/references
pub const Location = struct {
    uri: [512]u8 = [_]u8{0} ** 512,
    uri_len: usize = 0,
    start_line: u32 = 0,
    start_col: u32 = 0,
    end_line: u32 = 0,
    end_col: u32 = 0,

    pub fn getUri(self: *const Location) []const u8 {
        return self.uri[0..self.uri_len];
    }

    /// Convert file:// URI to path
    pub fn getPath(self: *const Location, buf: []u8) ?[]const u8 {
        const uri = self.getUri();
        if (std.mem.startsWith(u8, uri, "file://")) {
            const path = uri[7..];
            if (path.len <= buf.len) {
                @memcpy(buf[0..path.len], path);
                return buf[0..path.len];
            }
        }
        return null;
    }
};

/// LSP Client - manages multiple connections
pub const LspClient = struct {
    connections: [MAX_CONNECTIONS]Connection = undefined,
    connection_count: usize = 0,
    next_conn_id: i32 = 1,

    // Shared data buffer for received message content
    data_buffer: [262144]u8 = undefined, // 256KB
    data_buffer_used: usize = 0,

    // Results storage
    completions: [256]CompletionItem = undefined,
    completion_count: usize = 0,

    diagnostics: [512]Diagnostic = undefined,
    diagnostic_count: usize = 0,

    hover: HoverInfo = .{},
    has_hover: bool = false,

    locations: [64]Location = undefined,
    location_count: usize = 0,

    const MAX_CONNECTIONS = 16;
    const Self = @This();

    pub fn init() Self {
        var client = Self{};
        for (0..MAX_CONNECTIONS) |i| {
            client.connections[i] = Connection{ .id = 0 };
        }
        return client;
    }

    /// Start LSP server with given command
    /// Returns connection ID or -1 on error
    pub fn startServer(self: *Self, command: []const u8, args: []const u8, root_path: []const u8) i32 {
        if (self.connection_count >= MAX_CONNECTIONS) {
            return -1;
        }

        // Find free slot
        var slot: ?usize = null;
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].state == .disconnected) {
                slot = i;
                break;
            }
        }

        if (slot == null) return -1;
        const idx = slot.?;

        var conn = &self.connections[idx];
        conn.id = self.next_conn_id;
        self.next_conn_id += 1;
        conn.state = .connecting;

        // Store command
        const cmd_len = @min(command.len, conn.command.len);
        @memcpy(conn.command[0..cmd_len], command[0..cmd_len]);
        conn.command_len = cmd_len;

        // Store args
        const args_len = @min(args.len, conn.args.len);
        @memcpy(conn.args[0..args_len], args[0..args_len]);
        conn.args_len = args_len;

        // Store root path
        const root_len = @min(root_path.len, conn.root_path.len);
        @memcpy(conn.root_path[0..root_len], root_path[0..root_len]);
        conn.root_path_len = root_len;

        // Parse args into argv
        var argv: [32][]const u8 = undefined;
        var argc: usize = 1;
        argv[0] = conn.command[0..cmd_len];

        if (args_len > 0) {
            var iter = std.mem.splitScalar(u8, conn.args[0..args_len], ' ');
            while (iter.next()) |arg| {
                if (arg.len > 0 and argc < 31) {
                    argv[argc] = arg;
                    argc += 1;
                }
            }
        }

        // Spawn process
        var child = std.process.Child.init(argv[0..argc], std.heap.page_allocator);
        child.stdin_behavior = .pipe;
        child.stdout_behavior = .pipe;
        child.stderr_behavior = .pipe;

        child.spawn() catch {
            conn.state = .error_state;
            return -1;
        };

        conn.process = child;
        conn.state = .initializing;
        self.connection_count += 1;

        // Send initialize request
        self.sendInitialize(conn) catch {
            conn.state = .error_state;
            return -1;
        };

        return conn.id;
    }

    /// Stop LSP server
    pub fn stopServer(self: *Self, conn_id: i32) void {
        const conn = self.getConnection(conn_id) orelse return;

        if (conn.state == .ready) {
            // Send shutdown request
            self.sendShutdown(conn) catch {};
        }

        // Kill process
        if (conn.process) |*proc| {
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};
        }

        conn.process = null;
        conn.state = .disconnected;
        self.connection_count -|= 1;
    }

    /// Get connection by ID
    pub fn getConnection(self: *Self, conn_id: i32) ?*Connection {
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].id == conn_id and self.connections[i].state != .disconnected) {
                return &self.connections[i];
            }
        }
        return null;
    }

    /// Send raw JSON-RPC message
    pub fn sendMessage(self: *Self, conn: *Connection, json: []const u8) !void {
        _ = self;
        if (conn.process == null) return error.NotConnected;

        var stdin = conn.process.?.stdin orelse return error.NoStdin;

        // LSP header
        var header_buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{json.len}) catch return error.FormatError;

        _ = stdin.write(header) catch return error.WriteError;
        _ = stdin.write(json) catch return error.WriteError;
    }

    /// Send initialize request
    fn sendInitialize(self: *Self, conn: *Connection) !void {
        const root = conn.getRootPath();

        var uri_buf: [600]u8 = undefined;
        const root_uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{root}) catch return error.FormatError;

        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [4096]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"initialize","params":{{
            \\"processId":{d},
            \\"rootUri":"{s}",
            \\"capabilities":{{
            \\"textDocument":{{
            \\"completion":{{"completionItem":{{"snippetSupport":true}}}},
            \\"hover":{{}},
            \\"definition":{{}},
            \\"references":{{}},
            \\"publishDiagnostics":{{}}
            \\}}
            \\}}
            \\}}}}
        , .{ req_id, std.os.linux.getpid(), root_uri }) catch return error.FormatError;

        try self.sendMessage(conn, json);

        // Track pending request
        if (conn.pending_count < 64) {
            var pending = &conn.pending_requests[conn.pending_count];
            pending.id = req_id;
            const method = "initialize";
            @memcpy(pending.method[0..method.len], method);
            pending.method_len = method.len;
            conn.pending_count += 1;
        }
    }

    /// Send initialized notification
    fn sendInitialized(self: *Self, conn: *Connection) !void {
        const json = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";
        try self.sendMessage(conn, json);
        conn.state = .ready;
    }

    /// Send shutdown request
    fn sendShutdown(self: *Self, conn: *Connection) !void {
        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"shutdown","params":null}}
        , .{req_id}) catch return error.FormatError;

        conn.state = .shutdown;
        try self.sendMessage(conn, json);
    }

    /// Send textDocument/didOpen notification
    pub fn didOpen(self: *Self, conn_id: i32, uri: []const u8, language_id: []const u8, text: []const u8) !void {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        // Escape text for JSON
        var escaped_buf: [65536]u8 = undefined;
        const escaped = escapeJsonString(text, &escaped_buf) catch return error.TextTooLong;

        var json_buf: [65536]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{{
            \\"textDocument":{{"uri":"{s}","languageId":"{s}","version":1,"text":"{s}"}}
            \\}}}}
        , .{ uri, language_id, escaped }) catch return error.FormatError;

        try self.sendMessage(conn, json);
    }

    /// Send textDocument/didChange notification
    pub fn didChange(self: *Self, conn_id: i32, uri: []const u8, version: i32, text: []const u8) !void {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        var escaped_buf: [65536]u8 = undefined;
        const escaped = escapeJsonString(text, &escaped_buf) catch return error.TextTooLong;

        var json_buf: [65536]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","method":"textDocument/didChange","params":{{
            \\"textDocument":{{"uri":"{s}","version":{d}}},
            \\"contentChanges":[{{"text":"{s}"}}]
            \\}}}}
        , .{ uri, version, escaped }) catch return error.FormatError;

        try self.sendMessage(conn, json);
    }

    /// Send textDocument/didClose notification
    pub fn didClose(self: *Self, conn_id: i32, uri: []const u8) !void {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        var json_buf: [1024]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","method":"textDocument/didClose","params":{{
            \\"textDocument":{{"uri":"{s}"}}
            \\}}}}
        , .{uri}) catch return error.FormatError;

        try self.sendMessage(conn, json);
    }

    /// Request completion at position
    pub fn requestCompletion(self: *Self, conn_id: i32, uri: []const u8, line: u32, character: u32) !i32 {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [2048]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/completion","params":{{
            \\"textDocument":{{"uri":"{s}"}},
            \\"position":{{"line":{d},"character":{d}}}
            \\}}}}
        , .{ req_id, uri, line, character }) catch return error.FormatError;

        try self.sendMessage(conn, json);

        // Track request
        if (conn.pending_count < 64) {
            var pending = &conn.pending_requests[conn.pending_count];
            pending.id = req_id;
            const method = "textDocument/completion";
            @memcpy(pending.method[0..method.len], method);
            pending.method_len = method.len;
            conn.pending_count += 1;
        }

        return req_id;
    }

    /// Request hover info at position
    pub fn requestHover(self: *Self, conn_id: i32, uri: []const u8, line: u32, character: u32) !i32 {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [2048]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/hover","params":{{
            \\"textDocument":{{"uri":"{s}"}},
            \\"position":{{"line":{d},"character":{d}}}
            \\}}}}
        , .{ req_id, uri, line, character }) catch return error.FormatError;

        try self.sendMessage(conn, json);

        return req_id;
    }

    /// Request go to definition
    pub fn requestDefinition(self: *Self, conn_id: i32, uri: []const u8, line: u32, character: u32) !i32 {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [2048]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/definition","params":{{
            \\"textDocument":{{"uri":"{s}"}},
            \\"position":{{"line":{d},"character":{d}}}
            \\}}}}
        , .{ req_id, uri, line, character }) catch return error.FormatError;

        try self.sendMessage(conn, json);

        return req_id;
    }

    /// Request references
    pub fn requestReferences(self: *Self, conn_id: i32, uri: []const u8, line: u32, character: u32) !i32 {
        const conn = self.getConnection(conn_id) orelse return error.InvalidConnection;
        if (conn.state != .ready) return error.NotReady;

        const req_id = conn.next_request_id;
        conn.next_request_id += 1;

        var json_buf: [2048]u8 = undefined;
        const json = std.fmt.bufPrint(&json_buf,
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/references","params":{{
            \\"textDocument":{{"uri":"{s}"}},
            \\"position":{{"line":{d},"character":{d}}},
            \\"context":{{"includeDeclaration":true}}
            \\}}}}
        , .{ req_id, uri, line, character }) catch return error.FormatError;

        try self.sendMessage(conn, json);

        return req_id;
    }

    /// Poll for incoming messages (non-blocking)
    pub fn poll(self: *Self) void {
        for (0..MAX_CONNECTIONS) |i| {
            const conn = &self.connections[i];
            if (conn.state == .disconnected) continue;
            if (conn.process == null) continue;

            self.pollConnection(@constCast(conn));
        }
    }

    fn pollConnection(self: *Self, conn: *Connection) void {
        var stdout = conn.process.?.stdout orelse return;

        // Try to read (non-blocking would be better but this works for now)
        const bytes_read = stdout.read(&conn.read_buf) catch return;
        if (bytes_read == 0) return;

        // Parse LSP messages
        self.parseMessages(conn, conn.read_buf[0..bytes_read]);
    }

    fn parseMessages(self: *Self, conn: *Connection, data: []const u8) void {
        var pos: usize = 0;

        while (pos < data.len) {
            // Find Content-Length header
            const header_end = std.mem.indexOf(u8, data[pos..], "\r\n\r\n") orelse break;
            const header = data[pos .. pos + header_end];

            // Parse Content-Length
            var content_len: usize = 0;
            var header_iter = std.mem.splitSequence(u8, header, "\r\n");
            while (header_iter.next()) |line| {
                if (std.mem.startsWith(u8, line, "Content-Length:")) {
                    const len_str = std.mem.trim(u8, line[15..], " ");
                    content_len = std.fmt.parseInt(usize, len_str, 10) catch 0;
                    break;
                }
            }

            if (content_len == 0) break;

            const body_start = pos + header_end + 4;
            if (body_start + content_len > data.len) break;

            const body = data[body_start .. body_start + content_len];
            self.handleMessage(conn, body);

            pos = body_start + content_len;
        }
    }

    fn handleMessage(self: *Self, conn: *Connection, json: []const u8) void {
        // Simple JSON parsing for LSP responses
        // Check if it's a response (has "id" and "result" or "error")
        if (std.mem.indexOf(u8, json, "\"result\"") != null or std.mem.indexOf(u8, json, "\"error\"") != null) {
            // It's a response
            if (std.mem.indexOf(u8, json, "\"method\":\"initialize\"") != null or
                (conn.state == .initializing and std.mem.indexOf(u8, json, "\"capabilities\"") != null))
            {
                // Initialize response - send initialized notification
                self.sendInitialized(conn) catch {};
                return;
            }

            // Check for completion response
            if (std.mem.indexOf(u8, json, "\"items\"") != null or
                std.mem.indexOf(u8, json, "\"label\"") != null)
            {
                self.parseCompletionResponse(json);
                return;
            }

            // Check for hover response
            if (std.mem.indexOf(u8, json, "\"contents\"") != null) {
                self.parseHoverResponse(json);
                return;
            }

            // Check for definition/references response (locations)
            if (std.mem.indexOf(u8, json, "\"uri\"") != null and
                std.mem.indexOf(u8, json, "\"range\"") != null)
            {
                self.parseLocationResponse(json);
                return;
            }
        }

        // Check for notifications
        if (std.mem.indexOf(u8, json, "\"method\":\"textDocument/publishDiagnostics\"") != null) {
            self.parseDiagnosticsNotification(json);
            return;
        }
    }

    fn parseCompletionResponse(self: *Self, json: []const u8) void {
        self.completion_count = 0;

        // Find items array
        var pos: usize = 0;
        while (pos < json.len and self.completion_count < 256) {
            // Find next "label" field
            const label_start = std.mem.indexOf(u8, json[pos..], "\"label\":\"") orelse break;
            const label_content_start = pos + label_start + 9;

            // Find end of label string
            var label_end = label_content_start;
            while (label_end < json.len and json[label_end] != '"') {
                if (json[label_end] == '\\' and label_end + 1 < json.len) {
                    label_end += 2;
                } else {
                    label_end += 1;
                }
            }

            if (label_end > label_content_start) {
                var item = &self.completions[self.completion_count];
                const label = json[label_content_start..label_end];
                const copy_len = @min(label.len, item.label.len);
                @memcpy(item.label[0..copy_len], label[0..copy_len]);
                item.label_len = copy_len;

                // Try to find kind
                item.kind = 1;
                const search_region = json[pos..@min(pos + 500, json.len)];
                if (std.mem.indexOf(u8, search_region, "\"kind\":")) |kind_pos| {
                    const kind_start = kind_pos + 7;
                    if (kind_start < search_region.len) {
                        var kind_end = kind_start;
                        while (kind_end < search_region.len and
                            search_region[kind_end] >= '0' and search_region[kind_end] <= '9')
                        {
                            kind_end += 1;
                        }
                        if (kind_end > kind_start) {
                            item.kind = std.fmt.parseInt(u8, search_region[kind_start..kind_end], 10) catch 1;
                        }
                    }
                }

                // Try to find detail
                item.detail_len = 0;
                if (std.mem.indexOf(u8, search_region, "\"detail\":\"")) |detail_pos| {
                    const detail_start = detail_pos + 10;
                    var detail_end = detail_start;
                    while (detail_end < search_region.len and search_region[detail_end] != '"') {
                        if (search_region[detail_end] == '\\' and detail_end + 1 < search_region.len) {
                            detail_end += 2;
                        } else {
                            detail_end += 1;
                        }
                    }
                    if (detail_end > detail_start) {
                        const detail = search_region[detail_start..detail_end];
                        const detail_copy_len = @min(detail.len, item.detail.len);
                        @memcpy(item.detail[0..detail_copy_len], detail[0..detail_copy_len]);
                        item.detail_len = detail_copy_len;
                    }
                }

                // Try to find insertText
                item.insert_text_len = 0;
                if (std.mem.indexOf(u8, search_region, "\"insertText\":\"")) |insert_pos| {
                    const insert_start = insert_pos + 14;
                    var insert_end = insert_start;
                    while (insert_end < search_region.len and search_region[insert_end] != '"') {
                        if (search_region[insert_end] == '\\' and insert_end + 1 < search_region.len) {
                            insert_end += 2;
                        } else {
                            insert_end += 1;
                        }
                    }
                    if (insert_end > insert_start) {
                        const insert = search_region[insert_start..insert_end];
                        const insert_copy_len = @min(insert.len, item.insert_text.len);
                        @memcpy(item.insert_text[0..insert_copy_len], insert[0..insert_copy_len]);
                        item.insert_text_len = insert_copy_len;
                    }
                }

                self.completion_count += 1;
            }

            pos = label_end + 1;
        }
    }

    fn parseHoverResponse(self: *Self, json: []const u8) void {
        self.has_hover = false;
        self.hover.content_len = 0;
        self.hover.is_markdown = false;

        // Look for "value" field in contents
        if (std.mem.indexOf(u8, json, "\"value\":\"")) |value_pos| {
            const content_start = value_pos + 9;
            var content_end = content_start;

            while (content_end < json.len and json[content_end] != '"') {
                if (json[content_end] == '\\' and content_end + 1 < json.len) {
                    content_end += 2;
                } else {
                    content_end += 1;
                }
            }

            if (content_end > content_start) {
                const content = json[content_start..content_end];
                const copy_len = @min(content.len, self.hover.content.len);
                @memcpy(self.hover.content[0..copy_len], content[0..copy_len]);
                self.hover.content_len = copy_len;
                self.has_hover = true;

                // Check if markdown
                if (std.mem.indexOf(u8, json, "\"kind\":\"markdown\"") != null) {
                    self.hover.is_markdown = true;
                }
            }
        }
    }

    fn parseLocationResponse(self: *Self, json: []const u8) void {
        self.location_count = 0;

        var pos: usize = 0;
        while (pos < json.len and self.location_count < 64) {
            // Find next "uri" field
            const uri_start = std.mem.indexOf(u8, json[pos..], "\"uri\":\"") orelse break;
            const uri_content_start = pos + uri_start + 7;

            var uri_end = uri_content_start;
            while (uri_end < json.len and json[uri_end] != '"') : (uri_end += 1) {}

            if (uri_end > uri_content_start) {
                var loc = &self.locations[self.location_count];
                const uri = json[uri_content_start..uri_end];
                const copy_len = @min(uri.len, loc.uri.len);
                @memcpy(loc.uri[0..copy_len], uri[0..copy_len]);
                loc.uri_len = copy_len;

                // Find range/start/line and character
                const search_start = uri_end;
                const search_end = @min(search_start + 200, json.len);
                const search_region = json[search_start..search_end];

                if (std.mem.indexOf(u8, search_region, "\"line\":")) |line_pos| {
                    const line_start = line_pos + 7;
                    var line_end = line_start;
                    while (line_end < search_region.len and
                        search_region[line_end] >= '0' and search_region[line_end] <= '9')
                    {
                        line_end += 1;
                    }
                    if (line_end > line_start) {
                        loc.start_line = std.fmt.parseInt(u32, search_region[line_start..line_end], 10) catch 0;
                    }
                }

                if (std.mem.indexOf(u8, search_region, "\"character\":")) |char_pos| {
                    const char_start = char_pos + 12;
                    var char_end = char_start;
                    while (char_end < search_region.len and
                        search_region[char_end] >= '0' and search_region[char_end] <= '9')
                    {
                        char_end += 1;
                    }
                    if (char_end > char_start) {
                        loc.start_col = std.fmt.parseInt(u32, search_region[char_start..char_end], 10) catch 0;
                    }
                }

                self.location_count += 1;
            }

            pos = uri_end + 1;
        }
    }

    fn parseDiagnosticsNotification(self: *Self, json: []const u8) void {
        self.diagnostic_count = 0;

        var pos: usize = 0;
        while (pos < json.len and self.diagnostic_count < 512) {
            // Find next "message" field (each diagnostic has one)
            const msg_start = std.mem.indexOf(u8, json[pos..], "\"message\":\"") orelse break;
            const msg_content_start = pos + msg_start + 11;

            var msg_end = msg_content_start;
            while (msg_end < json.len and json[msg_end] != '"') {
                if (json[msg_end] == '\\' and msg_end + 1 < json.len) {
                    msg_end += 2;
                } else {
                    msg_end += 1;
                }
            }

            if (msg_end > msg_content_start) {
                var diag = &self.diagnostics[self.diagnostic_count];
                const msg = json[msg_content_start..msg_end];
                const copy_len = @min(msg.len, diag.message.len);
                @memcpy(diag.message[0..copy_len], msg[0..copy_len]);
                diag.message_len = copy_len;

                // Look backwards for range info
                const search_start = if (pos + msg_start > 200) pos + msg_start - 200 else 0;
                const search_region = json[search_start .. pos + msg_start];

                // Find severity
                diag.severity = 1;
                if (std.mem.lastIndexOf(u8, search_region, "\"severity\":")) |sev_pos| {
                    const sev_start = sev_pos + 11;
                    if (sev_start < search_region.len and
                        search_region[sev_start] >= '1' and search_region[sev_start] <= '4')
                    {
                        diag.severity = search_region[sev_start] - '0';
                    }
                }

                // Find line
                if (std.mem.lastIndexOf(u8, search_region, "\"line\":")) |line_pos| {
                    const line_start = line_pos + 7;
                    var line_end = line_start;
                    while (line_end < search_region.len and
                        search_region[line_end] >= '0' and search_region[line_end] <= '9')
                    {
                        line_end += 1;
                    }
                    if (line_end > line_start) {
                        diag.start_line = std.fmt.parseInt(u32, search_region[line_start..line_end], 10) catch 0;
                    }
                }

                // Find character
                if (std.mem.lastIndexOf(u8, search_region, "\"character\":")) |char_pos| {
                    const char_start = char_pos + 12;
                    var char_end = char_start;
                    while (char_end < search_region.len and
                        search_region[char_end] >= '0' and search_region[char_end] <= '9')
                    {
                        char_end += 1;
                    }
                    if (char_end > char_start) {
                        diag.start_col = std.fmt.parseInt(u32, search_region[char_start..char_end], 10) catch 0;
                    }
                }

                self.diagnostic_count += 1;
            }

            pos = msg_end + 1;
        }
    }

    /// Get current completions
    pub fn getCompletions(self: *const Self) []const CompletionItem {
        return self.completions[0..self.completion_count];
    }

    /// Get current diagnostics
    pub fn getDiagnostics(self: *const Self) []const Diagnostic {
        return self.diagnostics[0..self.diagnostic_count];
    }

    /// Get current hover info
    pub fn getHover(self: *const Self) ?*const HoverInfo {
        if (self.has_hover) {
            return &self.hover;
        }
        return null;
    }

    /// Get current locations
    pub fn getLocations(self: *const Self) []const Location {
        return self.locations[0..self.location_count];
    }

    /// Clear completions
    pub fn clearCompletions(self: *Self) void {
        self.completion_count = 0;
    }

    /// Shutdown all connections
    pub fn deinit(self: *Self) void {
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].state != .disconnected) {
                self.stopServer(self.connections[i].id);
            }
        }
    }
};

/// Escape string for JSON
fn escapeJsonString(input: []const u8, output: []u8) ![]const u8 {
    var out_pos: usize = 0;

    for (input) |ch| {
        if (out_pos + 2 >= output.len) return error.BufferTooSmall;

        switch (ch) {
            '"' => {
                output[out_pos] = '\\';
                output[out_pos + 1] = '"';
                out_pos += 2;
            },
            '\\' => {
                output[out_pos] = '\\';
                output[out_pos + 1] = '\\';
                out_pos += 2;
            },
            '\n' => {
                output[out_pos] = '\\';
                output[out_pos + 1] = 'n';
                out_pos += 2;
            },
            '\r' => {
                output[out_pos] = '\\';
                output[out_pos + 1] = 'r';
                out_pos += 2;
            },
            '\t' => {
                output[out_pos] = '\\';
                output[out_pos + 1] = 't';
                out_pos += 2;
            },
            else => {
                output[out_pos] = ch;
                out_pos += 1;
            },
        }
    }

    return output[0..out_pos];
}

/// Global LSP client instance (eagerly initialized)
var g_lsp_client: LspClient = LspClient{};
var g_lsp_initialized: bool = false;
var g_lsp_mutex: std.Thread.Mutex = .{};

pub fn getClient() *LspClient {
    g_lsp_mutex.lock();
    defer g_lsp_mutex.unlock();

    if (!g_lsp_initialized) {
        // Initialize connections array
        for (0..16) |i| {
            g_lsp_client.connections[i] = Connection{ .id = 0 };
        }
        g_lsp_initialized = true;
    }
    return &g_lsp_client;
}

pub fn deinitClient() void {
    g_lsp_mutex.lock();
    defer g_lsp_mutex.unlock();

    if (g_lsp_initialized) {
        g_lsp_client.deinit();
        g_lsp_initialized = false;
    }
}
