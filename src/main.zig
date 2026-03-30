const builtin = @import("builtin");

const std = @import("std");
const log = std.log;

pub const sdl = @cImport({
  @cDefine("SDL_MAIN_HANDLED", {});
  @cInclude("SDL3/SDL.h");
  @cInclude("SDL3/SDL_main.h");
  @cInclude("SDL3_image/SDL_image.h");
  @cInclude("SDL3_ttf/SDL_ttf.h");
});

pub const stdio = @cImport({
  @cInclude("stdio.h");
});

const Allocator = std.mem.Allocator;

const Scene = @import("scene.zig");

const logger = @import("log.zig");
pub const std_options = std.Options{
  .logFn = logger.logFn,
};

pub var startTime: i64 = undefined;

pub var window: *sdl.SDL_Window = undefined;
pub var renderer: *sdl.SDL_Renderer = undefined;
pub const WinCoord = @Vector(2, f32);
pub fn winSize() WinCoord
{
  var size: @Vector(2, c_int) = undefined;
  
  if (!sdl.SDL_GetRenderLogicalPresentation(renderer, &size[0], &size[1], null))
    unreachable;

  if (@reduce(.And, size == @as(@TypeOf(size), @splat(0))))
  {
    if (!sdl.SDL_GetWindowSizeInPixels(window, &size[0], &size[1]))
      unreachable;
  }

  //log.info("Get window size: {}\n", .{size});
  return .{@floatFromInt(size[0]), @floatFromInt(size[1])};
}

var randomEngine: std.Random.DefaultPrng = undefined;
pub var rand = randomEngine.random();

pub var running = true;
var lastFrameTick: i64 = 0;

var allocator = if (builtin.os.tag == .emscripten)
  @as(void, undefined)
  //std.heap.DebugAllocator(.{
  //  .stack_trace_frames = 0}){
  //  .backing_allocator = std.heap.wasm_allocator
  //}
else
  std.heap.DebugAllocator(.{}).init;
pub var gpa = if (builtin.os.tag == .emscripten)
  std.heap.c_allocator
else
  allocator.allocator();

fn init(appstate: ?*?*anyopaque, argc: i32, argv: ?[*]?[*:0]u8) callconv(.c)
  sdl.SDL_AppResult
{
  _ = appstate;
  _ = argc;
  _ = argv;
  startTime = @intCast(std.time.nanoTimestamp());

  randomEngine = .init(@intCast(@abs(std.time.milliTimestamp())));

  log.info("loading default world layout\n", .{});

  if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO))
  {
    log.err(
      "SDL failed to initialize video drivers: {s}\n", .{sdl.SDL_GetError()}
    );
    return sdl.SDL_APP_FAILURE;
  }

  if (!sdl.TTF_Init())
  {
    log.err(
      "SDL failed to initialize text library: {s}\n", .{sdl.SDL_GetError()}
    );
    return sdl.SDL_APP_FAILURE;
  }

  window, renderer = blk:
  {
    var optionalWindow: ?*sdl.SDL_Window = null;
    var optionalRenderer: ?*sdl.SDL_Renderer = null;

    if (!sdl.SDL_CreateWindowAndRenderer(
      "Mission Bitcoin",
      512, 512,
      sdl.SDL_WINDOW_RESIZABLE,
      &optionalWindow, &optionalRenderer) or
      optionalWindow == null or optionalRenderer == null)
    {
      log.err("Failed to initialize window: {s}\n", .{sdl.SDL_GetError()});
      return sdl.SDL_APP_FAILURE;
    }

    break:blk .{optionalWindow.?, optionalRenderer.?};
  };

  //if (!sdl.SDL_SetRenderLogicalPresentation(renderer,
  //  512, 512,
  //  sdl.SDL_LOGICAL_PRESENTATION_LETTERBOX))
  //{
  //  return sdl.SDL_APP_FAILURE;
  //}

  for (Scene.scenes.values) |scene|
  {
    _ = scene.init(gpa) catch |e|
    {
      log.err("Failed to initialize scene {} {s}\n", .{e, sdl.SDL_GetError()});

      if (@errorReturnTrace()) |trace|
      {
        std.debug.dumpStackTrace(trace.*);
      }

      return sdl.SDL_APP_FAILURE;
    };
  }

  return sdl.SDL_APP_CONTINUE;
}

fn update(appstate: ?*anyopaque) callconv(.c) sdl.SDL_AppResult
{
  _ = appstate;

  if (sdl.SDL_GetWindowFlags(window) & sdl.SDL_WINDOW_INPUT_FOCUS > 0)
  {
    if (std.time.milliTimestamp() - lastFrameTick > std.time.ms_per_s / 60)
    {
      lastFrameTick = std.time.milliTimestamp();

      Scene.currentScene.update() catch |e|
      {
        log.err("Failed to update scene: {}\n", .{e});

        if (@errorReturnTrace()) |trace|
        {
          std.debug.dumpStackTrace(trace.*);
        }

        return sdl.SDL_APP_FAILURE;
      };

      if (!sdl.SDL_SetRenderDrawColorFloat(renderer, 0.0, 0.0, 0.0, 1.0))
      {
        log.err("Failed to set clear color\n", .{});
      }
      if (!sdl.SDL_RenderClear(renderer))
      {
        log.err("Failed to clear screen\n", .{});
      }

      Scene.currentScene.render() catch |e|
      {
        log.err("Failed to render scene: {}\n", .{e});

        if (@errorReturnTrace()) |trace|
        {
          std.debug.dumpStackTrace(trace.*);
        }

        return sdl.SDL_APP_FAILURE;
      };

      if (!sdl.SDL_RenderPresent(renderer))
      {
        log.err("Failed to swap buffers\n", .{});
      }
    }
  }

  return sdl.SDL_APP_CONTINUE;
}

fn handleEvent(appstate: ?*anyopaque, event: ?*sdl.SDL_Event)
  callconv(.c) sdl.SDL_AppResult
{
  _ = appstate;

  if (event.?.type == sdl.SDL_EVENT_QUIT)
  {
    return sdl.SDL_APP_SUCCESS;
  }

  //if (event.?.type == sdl.SDL_EVENT_MOUSE_MOTION)
  //{
  //  log.debug("Mouse moved to {}\n", .{.{event.?.motion.x, event.?.motion.y}});
  //}

  const keys = kys:{
    var len: c_int = undefined;
    const ptr = sdl.SDL_GetKeyboardState(&len);

    break:kys ptr[0..@intCast(len)];
  };

  var mPos: @Vector(2, f32) = undefined;
  const mButtons: sdl.SDL_MouseButtonFlags =
    sdl.SDL_GetMouseState(&mPos[0], &mPos[1]);

  _ =
    Scene.currentScene.getInput(event.?.*, keys, mPos, mButtons) catch |e|
    {
      log.err("Scene failed to get event: {}\n", .{e});

      if (@errorReturnTrace()) |trace|
      {
        std.debug.dumpStackTrace(trace.*);
      }

      return sdl.SDL_APP_FAILURE;
    };

  return sdl.SDL_APP_CONTINUE;
}

fn deinit(appstate: ?*anyopaque, result: sdl.SDL_AppResult) callconv(.c) void
{
  _ = appstate;

  if (result == sdl.SDL_APP_FAILURE)
  {
    log.err("Returned a failure\n", .{});
  }

  for (Scene.scenes.values) |scene|
  {
    scene.deinit() catch
      if (@errorReturnTrace()) |trace|
      {
        std.debug.dumpStackTrace(trace.*);
      };
  }

  sdl.SDL_DestroyRenderer(renderer);
  sdl.SDL_DestroyWindow(window);

  sdl.SDL_Quit();

  if (builtin.os.tag != .emscripten)
  {
    if (allocator.deinit() == .leak)
    {
      log.warn("Program closed without deallocating all memory\n", .{});
    }
  }
}

pub fn main() u8
{
  sdl.SDL_SetMainReady();

  const status =
    sdl.SDL_EnterAppMainCallbacks(0, null, init, update, handleEvent, deinit);

  return @bitCast(@as(i8, @truncate(status)));
}
