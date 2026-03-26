const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");
const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

const Player = @import("../player.zig");

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var endingText: menu.Button = undefined;
var winnerText: ?menu.Button = null;

var gpa: Allocator = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

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

    endingText = .initFromText(.{0.5, 0.2}, 0.1, menuFont, "Game Completed!");

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
    if (winnerText == null)
    {
      const winner = blk:{
        var best: usize = 0;
        for (0.., game.players.items) |p, player| {
          if (
            game.players.items[best].value.totalTokens() <
            player.value.totalTokens())
          {
            best = p;
          }
        }
        break:blk best;
      };
      winnerText =
        menu.Button.initFromText(
          .{0.5, 0.4}, 0.1, menuFont,
          switch (winner) {
            0 => "Player red wins!",
            1 => "Player green wins!",
            2 => "Player blue wins!",
            3 => "Player yellow wins!",
            else => "Hacker wins!",
          });
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    try Scene.scenes.get(.Game).render();

    try endingText.render();
    if (winnerText) |text|
    {
      try text.render();
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    if (winnerText) |*text|
    {
      text.deinit();
    }
    endingText.deinit();
  }}.deinit,
};

