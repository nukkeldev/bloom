const std = @import("std");

const bloom = @import("bloom");

const c = bloom.ffi.c;
const SDL = bloom.ffi.SDL;
const zgui = bloom.zgui;

const log = std.log.scoped(.app);

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = if (@import("builtin").mode == .Debug) da.allocator() else std.heap.smp_allocator;

    const UserState = struct {
        should_exit: bool = false,
    };

    const init = bloom.BloomInit(UserState){
        .window_title = "Bloom Test",
        .window_size = .{ 800, 600 },

        .initial_user_state = .{},
    };

    var my_app = try bloom.initializeApp(UserState, allocator, init);
    const MyApp = @TypeOf(my_app);
    defer my_app.deinit() catch @panic("Failed to deinitialize app!");

    const AppFuncs = struct {
        pub fn render(app: *const MyApp, cmd: SDL.GPUCommandBuffer, rpass: SDL.GPURenderPass, delta_ns: u64) anyerror!void {
            _ = app;
            _ = cmd;
            _ = rpass;
            _ = delta_ns;

            // zgui.showDemoWindow(null);
            zgui.showMetricsWindow(null);
        }

        pub fn update(app: *MyApp, sdl_events: []const c.SDL_Event, delta_ns: u64) anyerror!void {
            _ = app;
            _ = sdl_events;
            _ = delta_ns;
        }

        pub fn shouldExit(app: *const MyApp) anyerror!bool {
            return app.user_state.should_exit;
        }
    };

    try my_app.run(
        AppFuncs.update,
        std.time.ns_per_ms,
        AppFuncs.render,
        std.time.ns_per_s / 60,
        AppFuncs.shouldExit,
    );
}
