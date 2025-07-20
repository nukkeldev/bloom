// -- Imports -- //

const std = @import("std");

pub const zgui = @import("zgui");
pub const ffi = @import("util/ffi.zig");
pub const tracy = @import("util/tracy.zig");

const SDL = @import("util/ffi.zig").SDL;
const c = @import("util/ffi.zig").c;

// -- Constants -- //

const log = std.log.scoped(.bloom);

// -- Initialization -- //

pub fn BloomInit(comptime UserState: type) type {
    return struct {
        window_title: []const u8,
        window_size: [2]u32,

        window_position: [2]u32 = .{ c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED },
        hdpi: bool = true,
        resizable: bool = true,

        shader_formats: c.SDL_GPUShaderFormat = c.SDL_GPU_SHADERFORMAT_SPIRV,

        initial_user_state: UserState,
    };
}

pub fn BloomApp(comptime UserState: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,

        window: SDL.Window,
        device: SDL.GPUDevice,

        user_state: UserState,

        start_time_ns: u64 = 0,
        time_ns: u64 = 0,

        last_update_ns: u64 = 0,
        last_frame_ns: u64 = 0,

        next_frame_ns: u64 = 0,
        next_update_ns: u64 = 0,

        // ---

        pub fn deinit(self: *@This()) !void {
            try self.device.waitForIdle();

            try self.device.destroy();
            try self.window.destroy();

            zgui.backend.deinit();
            zgui.deinit();

            c.SDL_Quit();
            self.arena.deinit();
        }

        // ---

        pub fn getElapsedTimeNs(self: *const @This()) u64 {
            return self.time_ns - self.start_time_ns;
        }

        // ---

        pub const UpdateFn = fn (app: *@This(), delta_ns: u64) anyerror!void;
        pub const RenderFn = fn (app: *const @This(), cmd: SDL.GPUCommandBuffer, rpass: SDL.GPURenderPass, delta_ns: u64) anyerror!void;
        pub const ShouldExitFn = fn (app: *const @This()) anyerror!bool;

        pub fn run(
            app: *@This(),
            update_fn: UpdateFn,
            update_rate_ns: u64,
            render_fn: RenderFn,
            render_rate_ns: u64,
            should_exit_fn: ShouldExitFn,
        ) !void {
            app.time_ns = @intCast(std.time.nanoTimestamp());
            app.start_time_ns = app.time_ns;
            app.last_update_ns = app.time_ns;
            app.last_frame_ns = app.time_ns;
            app.next_update_ns = app.time_ns;
            app.next_frame_ns = app.time_ns;

            log.info("Starting app...", .{});

            while (!try should_exit_fn(app)) {
                app.time_ns = @intCast(std.time.nanoTimestamp());

                if (app.time_ns >= app.next_update_ns) {
                    try update_fn(app, app.time_ns - app.last_update_ns);
                    app.next_update_ns = app.time_ns + update_rate_ns;
                }

                if (app.time_ns >= app.next_frame_ns) render: {
                    const cmd = try SDL.GPUCommandBuffer.acquire(&app.device);

                    const swapchain_texture: ?*c.SDL_GPUTexture = try cmd.waitAndAcquireSwapchainTexture(&app.window);
                    if (swapchain_texture == null) break :render;

                    const tex = swapchain_texture.?;

                    const color_target_info = c.SDL_GPUColorTargetInfo{
                        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
                        .texture = tex,
                        .load_op = c.SDL_GPU_LOADOP_CLEAR,
                        .store_op = c.SDL_GPU_STOREOP_STORE,
                    };

                    const rpass = try SDL.GPURenderPass.begin(&cmd, &.{color_target_info}, null);

                    try render_fn(app, cmd, rpass, app.time_ns - app.last_frame_ns);

                    rpass.end();
                    try cmd.submit();

                    app.next_frame_ns = app.time_ns + render_rate_ns;
                }
            }
        }
    };
}

pub fn initializeApp(comptime UserState: type, allocator: std.mem.Allocator, init: BloomInit(UserState)) !BloomApp(UserState) {
    var app: BloomApp(UserState) = undefined;

    app.arena = std.heap.ArenaAllocator.init(allocator);

    app.user_state = init.initial_user_state;
    app.time_ns = @intCast(std.time.nanoTimestamp());

    // -- SDL -- //

    try SDL.initialize(c.SDL_INIT_VIDEO);

    const props = c.SDL_CreateProperties();
    if (props == 0) {
        SDL.err("CreateProperties", "", .{});
        return error.SDLError;
    }

    _ = c.SDL_SetStringProperty(props, c.SDL_PROP_WINDOW_CREATE_TITLE_STRING, try app.allocator.dupeZ(u8, init.window_title));
    _ = c.SDL_SetBooleanProperty(props, c.SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN, init.hdpi);
    _ = c.SDL_SetBooleanProperty(props, c.SDL_PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN, init.resizable);
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, @intCast(init.window_size[0]));
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, @intCast(init.window_size[1]));
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_X_NUMBER, @intCast(init.window_position[0]));
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_Y_NUMBER, @intCast(init.window_position[1]));

    app.window = try SDL.Window.create(props);
    app.device = try SDL.GPUDevice.createAndClaimForWindow(init.shader_formats, false, null, &app.window);

    // -- ImGui -- //

    zgui.init(app.arena.allocator());
    zgui.backend.init(app.window.handle, .{
        .device = app.device.handle,
        .color_target_format = c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM, // TODO: Might want to expose this to the user.
        .msaa_samples = c.SDL_GPU_SAMPLECOUNT_1, // TODO: Ditto prior.
    });

    // ---

    return app;
}

// -- Tests -- //

test "initializeApp" {
    const init = BloomInit(void){
        .window_title = "Bloom Test",
        .window_size = .{ 800, 600 },
        .initial_user_state = {},
    };

    var app = try initializeApp(void, std.testing.allocator, init);
    defer app.deinit() catch @panic("Failed to deinitialize app!");

    try app.device.waitForIdle();
}

// Need a test for running the app with proper rendering.
