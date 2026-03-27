const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var startButton: menu.Button = undefined;
var joinButton: menu.Button = undefined;
var creditsButton: menu.Button = undefined;
var quitButton: menu.Button = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    _ = allocator;

    log.info("Initializing start menu\n", .{});

    menuFont = sdl.TTF_OpenFont(
      try directoryManager.getPath(&.{
        "assets", "fonts", "3270NerdFont-Regular.ttf"
      }),
      fontQuality
    ) orelse
    {
      log.err("Failed to load font: {s}\n", .{sdl.SDL_GetError()});
      return error.SDL_LoadFail;
    };

    startButton = .initFromText(.{0.5, 0.2}, 0.1, menuFont, "start");
    joinButton = .initFromText(.{0.5, 0.4}, 0.1, menuFont, "join");
    if (!sdl.SDL_SetTextureColorModFloat(joinButton.texture, 0.25, 0.25, 0.25))
    {
      return error.SDL_RenderFail;
    }
    creditsButton = .initFromText(.{0.5, 0.6}, 0.1, menuFont, "credits");
    quitButton = .initFromText(.{0.5, 0.8}, 0.1, menuFont, "quit");

    return &scene;
  }}.init,
  
  .getInput = struct {fn getInput(
    event: sdl.SDL_Event,
    keys: []const bool,
    mPos: @Vector(2, f32),
    mButtons: sdl.SDL_MouseButtonFlags) !bool
  {
    _ = keys;
    _ = mPos;
    _ = mButtons;

    if (
      event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN and
      event.button.button == sdl.SDL_BUTTON_LEFT)
    {
      if (startButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.CreateMenu);
        //Scene.currentScene = Scene.scenes.getPtrConst(.Game);
      } else if (joinButton.contains(.{event.button.x, event.button.y}))
      {
        //Scene.currentScene = Scene.scenes.getPtrConst(.JoinMenu);
      } else if (creditsButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.Credits);
      } else if (quitButton.contains(.{event.button.x, event.button.y}))
      {
        var quitEvent: sdl.SDL_Event = .{.quit = .{
          .type = sdl.SDL_EVENT_QUIT,
          .timestamp = sdl.SDL_GetTicksNS()
        }};
        if (!sdl.SDL_PushEvent(&quitEvent))
        {
          log.err("Failed to quit game: {s}\n", .{sdl.SDL_GetError()});
        }
      }
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {

  }}.update,
  
  .render = struct {fn render() !void
  {
    try startButton.render();
    try joinButton.render();
    try creditsButton.render();
    try quitButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    quitButton.deinit();
    creditsButton.deinit();
    joinButton.deinit();
    startButton.deinit();

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};
