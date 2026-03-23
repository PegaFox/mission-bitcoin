const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");
const game = @import("game.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

var playerButton: menu.Button = undefined;
var selectedPlayer: usize = 0;

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var startButton: menu.Button = undefined;
var joinButton: menu.Button = undefined;
var settingsButton: menu.Button = undefined;
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

    playerButton = try .initFromTexture(.{0.0, 0.166}, 0.15, &.{
      "assets", "images", "player.svg"
    });

    startButton = .initFromText(.{0.5, 0.333}, 0.1, menuFont, "start");
    joinButton = .initFromText(.{0.5, 0.499}, 0.1, menuFont, "join");
    settingsButton = .initFromText(.{0.5, 0.666}, 0.1, menuFont, "settings");
    quitButton = .initFromText(.{0.5, 0.833}, 0.1, menuFont, "quit");

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
      for (0..game.players.items.len) |p|
      {
        playerButton.center[0] = playerButtonPos(p)[0];

        if (playerButton.contains(.{event.button.x, event.button.y}))
        {
          log.info("Selected player updated to {}\n", .{p});
          selectedPlayer = p;
        }
      }

      if (startButton.contains(.{event.button.x, event.button.y}))
      {
        //Scene.currentScene = Scene.scenes.getPtrConst(.CreateMenu);
        Scene.currentScene = Scene.scenes.getPtrConst(.Game);
      } else if (joinButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.JoinMenu);
      } else if (settingsButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.SettingsMenu);
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
    for (0..game.players.items.len) |p|
    {
      playerButton.center[0] = playerButtonPos(p)[0];
                
      const colorDivisor =
        @as(f32, @floatFromInt(@intFromBool(selectedPlayer != p)))+1;
      if (!sdl.SDL_SetTextureColorModFloat(playerButton.texture,
        game.players.items[p].color[0] / colorDivisor,
        game.players.items[p].color[1] / colorDivisor,
        game.players.items[p].color[2] / colorDivisor))
      {
        return error.SDL_RenderFail;
      }
      try playerButton.render();
    }

    try startButton.render();
    try joinButton.render();
    try settingsButton.render();
    try quitButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    quitButton.deinit();
    settingsButton.deinit();
    joinButton.deinit();
    startButton.deinit();

    playerButton.deinit();

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};

fn playerButtonPos(index: usize) WinCoord
{
  const playerOffset = 1.0/@as(f32, @floatFromInt(game.players.items.len));

  return .{
    playerOffset*0.5 + playerOffset*@as(f32, @floatFromInt(index)),
    playerButton.center[1]
  };
}
