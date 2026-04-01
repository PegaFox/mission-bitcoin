const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const game = @import("game.zig");
const menu = @import("../menu.zig");

const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var textButton: menu.Button = undefined;
var dismissButton: menu.Button = undefined;
var dontShowButton: menu.Button = undefined;
var tutorialBox: [2]WinCoord = @splat(0);

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    _ = allocator;

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

    dismissButton = try .initFromText(
      .{0.5, 0.5}, @splat(0.0), 0.05, menuFont, "dismiss"
    );
    dontShowButton = try .initFromText(
      .{0.5, 0.5}, @splat(0.0), 0.05, menuFont, "stop showing these"
    );

    return &scene;
  }}.init,
  
  .getInput = struct {fn getInput(
    event: sdl.SDL_Event,
    keys: []const bool,
    mPos: @Vector(2, f32),
    mButtons: sdl.SDL_MouseButtonFlags) !bool
  {
    _ = event;
    _ = keys;
    _ = mPos;
    _ = mButtons;

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {

  }}.update,
  
  .render = struct {fn render() !void
  {
    if (@reduce(.And, tutorialBox[1] > @as(WinCoord, @splat(0))))
    {
      const winSize = mainspace.winSize();

      if (!sdl.SDL_SetRenderDrawColorFloat(
        mainspace.renderer, 0.1, 0.1, 0.1, 1.0))
      {
        return error.SDL_RenderFail;
      }
      if (!sdl.SDL_RenderFillRect(mainspace.renderer, &.{
        .x = tutorialBox[0][0]*winSize[0],
        .y = tutorialBox[0][1]*winSize[1],
        .w = tutorialBox[1][0]*winSize[0],
        .h = tutorialBox[1][1]*winSize[1],
      }))
      {
        return error.SDL_RenderFail;
      }

      try textButton.render();
      try dismissButton.render();
      try dontShowButton.render();
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    dontShowButton.deinit();
    dismissButton.deinit();

    if (@reduce(.And, tutorialBox[1] > @as(WinCoord, @splat(0))))
    {
      textButton.deinit();
    }

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};

fn setTutorialBox(msg: []const u8, pos: BoardCoord) void
{
  const winSize = mainspace.winSize();
  const boxPos = game.boardToWindowPos(game.board.items, null, pos) / winSize;

  textButton.deinit();
  textButton = try .initFromText(
    .{0.0, 0.0}, boxPos, 0.05, menuFont, msg
  );

  tutorialBox = .{boxPos, .{0.2, 0.2}};
}
