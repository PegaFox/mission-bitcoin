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

var selectedTexture: *sdl.SDL_Texture = undefined;

var moves: [4]BoardCoord = @splat(null);

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    selectedTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath("assets/images/selected.svg")
    );

    moves = game.currentPlayer.value.getMoves(
      game.board.items,
      mainspace.rand.intRangeAtMost(u8, 1, 6)
    );

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
      const selected = hoveredSpace();
      for (moves) |move|
      {
        if (move == null)
        {
          break;
        }

        if (@reduce(.And, move.? == selected.?))
        {
          game.currentPlayer.value.move(game.board.items, move);

          moves = game.currentPlayer.value.getMoves(
            game.board.items,
            mainspace.rand.intRangeAtMost(u8, 1, 6)
          );
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
    const winSize = mainspace.winSize();
    //const center = winSize * @as(mainspace.WinCoord, @splat(0.5));
    const radius = @min(winSize[0], winSize[1]) * 0.025;

    if (!sdl.SDL_SetTextureColorModFloat(selectedTexture,
      game.currentPlayer.color[0],
      game.currentPlayer.color[1],
      game.currentPlayer.color[2]))
    {
      return error.SDL_RenderFail;
    }
    for (moves) |move|
    {
      if (move == null)
      {
        break;
      }

      const pos = try game.boardToWindowPos(game.board.items, null, move);
      
      if (!sdl.SDL_RenderTexture(
        mainspace.renderer, selectedTexture, null,
        &.{
          .x = pos[0]-radius,
          .y = pos[1]-radius,
          .w = radius*2,
          .h = radius*2,
        }))
      {
        return error.SDL_RenderFail;
      }
    }

    //const pos =
    //  game.boardToWindowPos(game.board.items, null, hoveredSpace()) catch
    //    return;
    //const dis = std.math.hypot(pos[0] - center[0], pos[1] - center[1]);

    //if (!sdl.SDL_RenderTexture(
    //  mainspace.renderer, selectedTexture, null,
    //  &.{
    //    .x = center[0] - dis,
    //    .y = center[1] - dis,
    //    .w = dis*2,
    //    .h = dis*2,
    //  }))
    //{
    //  return error.SDL_RenderFail;
    //}

    //if (!sdl.SDL_RenderTexture(
    //  mainspace.renderer, selectedTexture, null,
    //  &.{
    //    .x = pos[0] - radius,
    //    .y = pos[1] - radius,
    //    .w = radius*2,
    //    .h = radius*2,
    //  }))
    //{
    //  return error.SDL_RenderFail;
    //}
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {

  }}.deinit,
};

pub fn hoveredSpace() BoardCoord
{
  var mPos: @Vector(2, f32) = undefined;
  _ = sdl.SDL_GetMouseState(&mPos[0], &mPos[1]);

  return game.windowToBoardPos(game.board.items, .{
    mPos[0],
    mPos[1]
  });
}

// Parsed data must be freed with .deinit()
fn jsonFromFile(allocator: Allocator, T: type, path: []const u8)
  !std.json.Parsed(T)
{
  const boardFilePath =
    try directoryManager.getPath(path);
  var boardFile = try std.fs.openFileAbsolute(boardFilePath, .{});
  defer boardFile.close();

  var readBuffer: [1024]u8 = undefined;
  var fileReader = boardFile.reader(&readBuffer);
  var jsonReader = std.json.Reader.init(allocator, &fileReader.interface);
  defer jsonReader.deinit();

  return try std.json.parseFromTokenSource(T, allocator, &jsonReader, .{});
}
