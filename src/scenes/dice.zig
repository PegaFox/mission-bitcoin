const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

var gpa: Allocator = undefined;

pub var rollTime: u32 = 60;
var tick: u32 = 0;
pub fn reset() void
{
  tick = 0;
}
pub var chosenNumber: u3 = 0;

var baseTexture: *sdl.SDL_Texture = undefined;
var numberTextures: [6]*sdl.SDL_Texture = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    baseTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath(&.{"assets", "images", "dice", "base.svg"})
    );
    for (0..numberTextures.len) |n|
    {
      numberTextures[n] = sdl.IMG_LoadTexture(
        mainspace.renderer,
        try directoryManager.getPath(&.{
          "assets",
          "images",
          "dice",
          (&std.fmt.digitToChar(@truncate(n+1), .lower))[0..1] ++ ".svg"})
      );
    }

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
    if (tick % 2 == 0)
    {
      chosenNumber = mainspace.rand.intRangeAtMost(u3, 1, 6);
    }
    tick += 1;

    if (tick > rollTime)
    {
      _ = game.players.items[game.currentPlayer].value.getMoves(
        game.board.items, chosenNumber
      );

      reset();
      Scene.currentScene = Scene.scenes.getPtrConst(.Game);
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    // Check for main scene to prevent recursion
    if (Scene.currentScene == Scene.scenes.getPtrConst(.Dice))
    {
      try Scene.scenes.get(.Game).render();
    }

    const winSize = mainspace.winSize();

    const renderRect = sdl.SDL_FRect{
      .x = winSize[0]*0.05,
      .y = winSize[1]*0.2,
      .w = winSize[0]*0.025,
      .h = winSize[0]*0.025,
    };
    if (!sdl.SDL_RenderTexture(
      mainspace.renderer, baseTexture, null, &renderRect))
    {
      return error.SDL_RenderFail;
    }
    if (!sdl.SDL_RenderTexture(
      mainspace.renderer, numberTextures[chosenNumber-1], null, &renderRect))
    {
      return error.SDL_RenderFail;
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    sdl.SDL_DestroyTexture(baseTexture);
  }}.deinit,
};
