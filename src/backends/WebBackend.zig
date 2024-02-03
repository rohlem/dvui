const std = @import("std");
const dvui = @import("dvui");

const WebBackend = @This();

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const EventTemp = struct {
    kind: u8,
    int1: u8,
    int2: u8,
    float1: f32,
    float2: f32,
};

pub var event_temps = std.ArrayList(EventTemp).init(gpa);

pub const wasm = struct {
    pub extern fn wasm_panic(ptr: [*]const u8, len: usize) void;
    pub extern fn wasm_log_write(ptr: [*]const u8, len: usize) void;
    pub extern fn wasm_log_flush() void;

    pub extern fn wasm_now() f64;
    pub extern fn wasm_sleep(ms: u32) void;

    pub extern fn wasm_pixel_width() f32;
    pub extern fn wasm_pixel_height() f32;
    pub extern fn wasm_canvas_width() f32;
    pub extern fn wasm_canvas_height() f32;

    pub extern fn wasm_clear() void;
    pub extern fn wasm_textureCreate(pixels: [*]u8, width: u32, height: u32) u32;
    pub extern fn wasm_textureDestroy(u32) void;
    pub extern fn wasm_renderGeometry(texture: u32, index_ptr: [*]const u8, index_len: usize, vertex_ptr: [*]const u8, vertex_len: usize, sizeof_vertex: u8, offset_pos: u8, offset_col: u8, offset_uv: u8) void;
};

export const __stack_chk_guard: c_ulong = 0xBAAAAAAD;
export fn __stack_chk_fail() void {}

export fn dvui_c_alloc(size: usize) ?*anyopaque {
    //std.log.debug("dvui_c_alloc {d}", .{size});
    const buffer = gpa.alignedAlloc(u8, 16, size + 16) catch {
        //std.log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeIntNative(usize, buffer[0..@sizeOf(usize)], buffer.len);
    return buffer.ptr + 16;
}

export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(16) u8, @alignCast(@ptrCast(ptr orelse return))) - 16;
    const len = std.mem.readIntNative(usize, buffer[0..@sizeOf(usize)]);
    //std.log.debug("dvui_c_free {d}", .{len - 16});

    gpa.free(buffer[0..len]);
}

export fn dvui_c_realloc_sized(ptr: ?*anyopaque, oldsize: usize, newsize: usize) ?*anyopaque {
    _ = oldsize;
    //std.log.debug("dvui_c_realloc_sized {d} {d}", .{ oldsize, newsize });

    if (ptr == null) {
        return dvui_c_alloc(newsize);
    }

    const buffer = @as([*]u8, @ptrCast(ptr.?)) - 16;
    const len = std.mem.readIntNative(usize, buffer[0..@sizeOf(usize)]);

    var slice = buffer[0..len];
    _ = gpa.resize(slice, newsize + 16);

    std.mem.writeIntNative(usize, slice[0..@sizeOf(usize)], slice.len);
    return slice.ptr + 16;
}

export fn dvui_c_panic(msg: [*c]const u8) noreturn {
    wasm.wasm_panic(msg, std.mem.len(msg));
    unreachable;
}

export fn dvui_c_pow(x: f64, y: f64) f64 {
    return @exp(@log(x) * y);
}

export fn dvui_c_ldexp(x: f64, n: c_int) f64 {
    return x * @exp2(@as(f64, @floatFromInt(n)));
}

export fn add_event(kind: u8, int1: u8, int2: u8, float1: f32, float2: f32) void {
    event_temps.append(.{
        .kind = kind,
        .int1 = int1,
        .int2 = int2,
        .float1 = float1,
        .float2 = float2,
    }) catch |err| {
        var msg = std.fmt.allocPrint(gpa, "{!}", .{err}) catch "allocPrint OOM";
        wasm.wasm_panic(msg.ptr, msg.len);
    };
}

pub fn hasEvent(_: *WebBackend) bool {
    return event_temps.items.len > 0;
}

fn buttonFromJS(jsButton: u8) dvui.enums.Button {
    return switch (jsButton) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .four,
        4 => .five,
        else => .six,
    };
}

pub fn addAllEvents(_: *WebBackend, win: *dvui.Window) !void {
    for (event_temps.items) |e| {
        switch (e.kind) {
            1 => _ = try win.addEventMouseMotion(e.float1, e.float2),
            2 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .press),
            3 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .release),
            4 => _ = try win.addEventMouseWheel(if (e.float1 > 0) -20 else 20),
            else => std.log.debug("addAllEvents unknown event kind {d}", .{e.kind}),
        }
    }

    event_temps.clearRetainingCapacity();
}

pub fn init() !WebBackend {
    var back: WebBackend = undefined;
    return back;
}

pub fn deinit(self: *WebBackend) void {
    _ = self;
}

pub fn clear(self: *WebBackend) void {
    _ = self;
    wasm.wasm_clear();
}

pub fn backend(self: *WebBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, free, openURL, refresh);
}

pub fn nanoTime(self: *WebBackend) i128 {
    _ = self;
    return @as(i128, @intFromFloat(wasm.wasm_now())) * 1_000_000;
}

pub fn sleep(self: *WebBackend, ns: u64) void {
    _ = self;
    wasm.wasm_sleep(@intCast(@divTrunc(ns, 1_000_000)));
}

pub fn begin(self: *WebBackend, arena: std.mem.Allocator) void {
    _ = self;
    _ = arena;
}

pub fn end(_: *WebBackend) void {}

pub fn pixelSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_pixel_width(), .h = wasm.wasm_pixel_height() };
}

pub fn windowSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_canvas_width(), .h = wasm.wasm_canvas_height() };
}

pub fn contentScale(_: *WebBackend) f32 {
    return 1.0;
}

pub fn renderGeometry(self: *WebBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
    _ = self;
    var index_slice = std.mem.sliceAsBytes(idx);
    var vertex_slice = std.mem.sliceAsBytes(vtx);

    wasm.wasm_renderGeometry(
        if (texture) |t| @as(u32, @intFromPtr(t)) else 0,
        index_slice.ptr,
        index_slice.len,
        vertex_slice.ptr,
        vertex_slice.len,
        @sizeOf(dvui.Vertex),
        @offsetOf(dvui.Vertex, "pos"),
        @offsetOf(dvui.Vertex, "col"),
        @offsetOf(dvui.Vertex, "uv"),
    );
}

pub fn textureCreate(self: *WebBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    _ = self;

    // convert to premultiplied alpha
    for (0..height) |h| {
        for (0..width) |w| {
            const i = (h * width + w) * 4;
            const a: u16 = pixels[i + 3];
            pixels[i] = @intCast(@divTrunc(@as(u16, pixels[i]) * a, 255));
            pixels[i + 1] = @intCast(@divTrunc(@as(u16, pixels[i + 1]) * a, 255));
            pixels[i + 2] = @intCast(@divTrunc(@as(u16, pixels[i + 2]) * a, 255));
        }
    }

    const id = wasm.wasm_textureCreate(pixels, width, height);
    return @ptrFromInt(id);
}

pub fn textureDestroy(_: *WebBackend, texture: *anyopaque) void {
    wasm.wasm_textureDestroy(@as(u32, @intFromPtr(texture)));
}

pub fn clipboardText(self: *WebBackend) []u8 {
    _ = self;
    var buf: [10]u8 = [_]u8{0} ** 10;
    @memcpy(buf[0..9], "clipboard");
    return &buf;
}

pub fn clipboardTextSet(self: *WebBackend, text: []const u8) !void {
    _ = self;
    _ = text;
    return;
}

pub fn free(self: *WebBackend, p: *anyopaque) void {
    _ = self;
    _ = p;
}

pub fn openURL(self: *WebBackend, url: []const u8) !void {
    _ = self;
    _ = url;
}

pub fn refresh(self: *WebBackend) void {
    _ = self;
}