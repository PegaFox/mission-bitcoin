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

var winner: ?usize = null;

var endingText: menu.Button = undefined;
var winnerText: ?menu.Button = null;
var restartButton: menu.Button = undefined;
var menuButton: menu.Button = undefined;

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

    endingText =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.2}, 0.1, menuFont, "Game Over!");
    restartButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.6}, 0.1, menuFont, "Play again");
    menuButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.8}, 0.1, menuFont, "Main menu");

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

    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN)
    {
      if (restartButton.contains(.{event.button.x, event.button.y}))
      {
        winnerText.?.deinit();
        winnerText = null;

        game.reset();
        Scene.currentScene = Scene.scenes.getPtrConst(.Dice);
      }
      if (menuButton.contains(.{event.button.x, event.button.y}))
      {
        winnerText.?.deinit();
        winnerText = null;

        game.reset();
        Scene.currentScene = Scene.scenes.getPtrConst(.StartMenu);
      }
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
    if (winnerText == null)
    {
      winner = blk:{
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
        try menu.Button.initFromText(
          .{0.5, 0.5}, .{0.5, 0.4}, 0.1, menuFont,
          if (
            game.players.items[winner.?].controller ==
            Scene.scenes.getPtrConst(.Manual)) "Congratulations! You won!"
          else
            switch (winner.?) {
              0 => "Red wins!",
              1 => "Green wins!",
              2 => "Blue wins!",
              3 => "Yellow wins!",
              else => "Hacker wins!",
            });
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    try Scene.scenes.get(.Game).render();

    if (
      game.players.items[winner.?].controller ==
      Scene.scenes.getPtrConst(.Manual))
    {
      try endingText.render();
    }
    if (winnerText) |text|
    {
      try text.render();
    }
    try restartButton.render();
    try menuButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    menuButton.deinit();
    restartButton.deinit();
    if (winnerText) |*text|
    {
      text.deinit();
    }
    endingText.deinit();
  }}.deinit,
};

