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

var playerLabel: menu.Button = undefined;
var playerButton: menu.Button = undefined;
var selectedPlayer: usize = 0;

var aiLabel: menu.Button = undefined;
var aiText: menu.Button = undefined;
var addAi: menu.Button = undefined;
var subAi: menu.Button = undefined;
var aiCount: usize = 0;

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var startButton: menu.Button = undefined;
var backButton: menu.Button = undefined;

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

    playerLabel = .initFromText(
      .{0.5, 0.5}, .{0.5, 0.075}, 0.05, menuFont, "choose a color"
    );
    playerButton = try .initFromTexture(.{0.5, 0.5}, .{0.0, 0.2}, 0.15, &.{
      "assets", "images", "player.svg"
    });

    aiLabel =
      .initFromText(.{0.5, 0.5}, .{0.5, 0.325}, 0.05, menuFont, "AI players");
    aiText = .initFromText(.{0.5, 0.5}, .{0.5, 0.4}, 0.1, menuFont, "0");
    try initAiChangeButtons();

    startButton =
      .initFromText(.{0.5, 0.5}, .{0.5, 0.6}, 0.1, menuFont, "start");
    backButton = .initFromText(.{0.5, 0.5}, .{0.5, 0.8}, 0.1, menuFont, "back");

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
        playerButton.pos[0] = playerButtonPos(p)[0];

        if (playerButton.contains(.{event.button.x, event.button.y}))
        {
          log.info("Selected player updated to {}\n", .{p});

          selectedPlayer = p;
        }
      }

      if (
        subAi.contains(.{event.button.x, event.button.y}) and
        aiCount > 0)
      {
        aiCount -= 1;
        aiText.deinit();
        var printBuffer: [32]u8 = undefined;
        aiText = .initFromText(
          .{0.5, 0.5}, .{0.5, 0.4}, 0.1, menuFont,
          try std.fmt.bufPrint(&printBuffer, "{}", .{aiCount}));
      }
      if (
        addAi.contains(.{event.button.x, event.button.y}) and
        aiCount < game.players.items.len-1)
      {
        aiCount += 1;
        aiText.deinit();
        var printBuffer: [32]u8 = undefined;
        aiText = .initFromText(
          .{0.5, 0.5}, .{0.5, 0.4}, 0.1, menuFont,
          try std.fmt.bufPrint(&printBuffer, "{}", .{aiCount}));
      }

      if (startButton.contains(.{event.button.x, event.button.y}))
      {
        game.players.items[selectedPlayer].controller =
          Scene.scenes.getPtrConst(.Manual);

        for (0..aiCount) |ai|
        {
          const playerOffset: usize = switch (ai)
          {
            0 => 2,
            1 => 1,
            2 => 3,
            else => 0
          };
          game.players.items[
            @rem(selectedPlayer+playerOffset, game.players.items.len)
          ].controller = Scene.scenes.getPtrConst(.AI);
        }

        Scene.currentScene = Scene.scenes.getPtrConst(.Dice);
      }
      if (backButton.contains(.{event.button.x, event.button.y}))
      {
        Scene.currentScene = Scene.scenes.getPtrConst(.StartMenu);
      }
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {

  }}.update,
  
  .render = struct {fn render() !void
  {
    try playerLabel.render();
    for (0.., game.players.items) |p, player|
    {
      playerButton.pos[0] = playerButtonPos(p)[0];
                
      const selected = selectedPlayer == p;
      const colorDivisor =
        @as(f32, @floatFromInt(@intFromBool(!selected)))+1;
      if (!sdl.SDL_SetTextureColorModFloat(playerButton.texture,
        player.color[0] / colorDivisor,
        player.color[1] / colorDivisor,
        player.color[2] / colorDivisor))
      {
        return error.SDL_RenderFail;
      }
      try playerButton.render();
    }

    try aiLabel.render();
    try aiText.render();
    try subAi.render();
    try addAi.render();

    try startButton.render();
    try backButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    backButton.deinit();
    startButton.deinit();

    addAi.deinit();
    subAi.deinit();
    aiText.deinit();
    aiLabel.deinit();

    playerButton.deinit();
    playerLabel.deinit();

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};

fn playerButtonPos(index: usize) WinCoord
{
  const playerOffset = 1.0/@as(f32, @floatFromInt(game.players.items.len));

  return .{
    playerOffset*0.5 + playerOffset*@as(f32, @floatFromInt(index)),
    playerButton.pos[1]
  };
}

fn initAiChangeButtons() error{SDL_RenderFail}!void
{
  var noErr = true;

  // Surface size can be anything high enough
  const renderSurface: *sdl.SDL_Surface =
    sdl.SDL_CreateSurface(512, 512, sdl.SDL_PIXELFORMAT_RGB24);
  defer sdl.SDL_DestroySurface(renderSurface);

  const surfaceRenderer = sdl.SDL_CreateSoftwareRenderer(renderSurface);
  defer sdl.SDL_DestroyRenderer(surfaceRenderer);
  noErr &= sdl.SDL_RenderGeometry(surfaceRenderer, null, &[_]sdl.SDL_Vertex{
    .{
      .position = .{.x = 0, .y = 0},
      .color = .{.r = 1, .g = 1, .b = 1, .a = 1}
    },
    .{
      .position = .{
        .x = @floatFromInt(renderSurface.w),
        .y = @floatFromInt(@divTrunc(renderSurface.h, 2))
      },
      .color = .{.r = 1, .g = 1, .b = 1, .a = 1}
    },
    .{
      .position = .{.x = 0, .y = @floatFromInt(renderSurface.h)},
      .color = .{.r = 1, .g = 1, .b = 1, .a = 1}
    },
  }, 3, &[_]c_int{0, 1, 2}, 3);
  noErr &= sdl.SDL_RenderPresent(surfaceRenderer);

  addAi = .{
    .origin = .{0.5, 0.5},
    .pos = .{0.7, 0.4},
    .height = 0.1,
    .texture = 
      sdl.SDL_CreateTextureFromSurface(mainspace.renderer, renderSurface),
  };

  noErr &= sdl.SDL_FlipSurface(renderSurface, sdl.SDL_FLIP_HORIZONTAL);

  subAi = .{
    .origin = .{0.5, 0.5},
    .pos = .{0.3, 0.4},
    .height = 0.1,
    .texture = 
      sdl.SDL_CreateTextureFromSurface(mainspace.renderer, renderSurface),
  };
}
