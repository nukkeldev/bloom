const std = @import("std");

const bloom = @import("bloom");

const c = bloom.ffi.c;
const SDL = bloom.ffi.SDL;
const zgui = bloom.zgui;

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

        .resizable = false,

        .initial_user_state = .{},
    };

    var my_app = try bloom.initializeApp(UserState, allocator, init);
    const MyApp = @TypeOf(my_app);

    defer my_app.deinit() catch @panic("Failed to deinitialize app!");

    const AppFuncs = struct {
        pub fn render(app: *const MyApp, cmd: SDL.GPUCommandBuffer, rpass: SDL.GPURenderPass, delta_ns: u64) anyerror!void {
            _ = app;

            zgui.backend.newFrame(init.window_size[0], init.window_size[1], 1.0);

            if (zgui.begin("Debug", .{})) {
                defer zgui.end();

                zgui.text("Test: `runApp`", .{});
                zgui.text("Delta time: {}", .{std.fmt.fmtDuration(delta_ns)});
            }

            zgui.render();

            zgui.backend.prepareDrawData(cmd.handle);
            zgui.backend.renderDrawData(cmd.handle, rpass.handle, null);
        }

        pub fn update(app: *MyApp, delta_ns: u64) anyerror!void {
            _ = delta_ns;

            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event)) {
                if (event.type == c.SDL_EVENT_QUIT) {
                    app.user_state.should_exit = true;
                }
            }
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
