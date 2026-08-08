const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

const remote = @import("remote_player.zig");

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var logoButton: menu.Button = undefined;
var startButton: menu.Button = undefined;
var joinButton: menu.Button = undefined;
var guideButton: menu.Button = undefined;
var creditsButton: menu.Button = undefined;
var quitButton: menu.Button = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    _ = allocator;

    menuFont = sdl.TTF_OpenFont(
      try directoryManager.getPath(mainspace.io, &.{
        "assets", "fonts", "3270NerdFont-Regular.ttf"
      }),
      fontQuality
    ) orelse
    {
      log.err("Failed to load font: {s}\n", .{sdl.SDL_GetError()});
      return error.SDL_LoadFail;
    };

    logoButton = try .initFromTexture(
      mainspace.io,
      .{0.5, 0.5}, .{0.5, 1.0/7.0}, 0.1, &.{"assets", "images", "logo.png"}
    );
    
    startButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 2.0/7.0}, 0.1, menuFont, "start");
    joinButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 3.0/7.0}, 0.1, menuFont, "join");
    guideButton = try .initFromText(
      .{0.5, 0.5}, .{0.5, 4.0/7.0}, 0.1, menuFont, "how to play"
    );
    creditsButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 5.0/7.0}, 0.1, menuFont, "credits");
    quitButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 6.0/7.0}, 0.1, menuFont, "quit");

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
      } else if (
        remote.serverFuture != null and
        joinButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.JoinMenu);
      } else if (guideButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.Guide);
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
    try logoButton.render();
    try startButton.render();

    const c: f32 = if (remote.serverFuture == null) 0.25 else 1.0;
    if (!sdl.SDL_SetTextureColorModFloat(joinButton.texture, c, c, c))
    {
      return error.SDL_RenderFail;
    }
    try joinButton.render();
    try guideButton.render();
    try creditsButton.render();
    try quitButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    quitButton.deinit();
    creditsButton.deinit();
    guideButton.deinit();
    joinButton.deinit();
    startButton.deinit();
    logoButton.deinit();

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};
