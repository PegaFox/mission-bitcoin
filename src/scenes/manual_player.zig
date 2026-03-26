const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const game = @import("game.zig");

const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

var gpa: Allocator = undefined;

var selectedTexture: *sdl.SDL_Texture = undefined;

var state: union(enum)
{
  MoveInput: void,
  PillInput: struct {move: Player.Pos},
  Moving: struct {move: Player.Pos, pillPlayer: ?*Player}
} = .MoveInput;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    selectedTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath(&.{"assets", "images", "selected.svg"})
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
      switch (state)
      {
        .MoveInput => {
          const selected = hoveredSpace();

          for (Player.moves) |move|
          {
            if (@reduce(.And, move.? == selected.?))
            {
              const space = game.board.items[move.?[1]].spaces[move.?[0]];

              log.info("moving to {}: {}\n", .{
                move.?, space
              });

              if (space.type == .OrangePill)
              {
                state = .{.PillInput = .{.move = move}};
              } else
              {
                state = .{.Moving = .{.move = move, .pillPlayer = null}};
              }
            }
          }
        },
        .PillInput => |m| {
          for (0.., game.players.items) |p, *player|
          {
            if (p == game.currentPlayer or player.value.pos == null)
            {
              continue;
            }

            const walletArea = game.walletRenderArea(p);
            if (
              event.button.x > walletArea[0][0] - walletArea[1][1]*0.5 and
              event.button.y > walletArea[0][1] + walletArea[1][1]*0.25 and
              event.button.x < walletArea[0][0] and
              event.button.y < walletArea[0][0] + walletArea[1][1])
            {
              log.info("chose player {}\n", .{
                player
              });

              state = .{.Moving = .{
                .move = m.move,
                .pillPlayer = &player.value
              }};
            }
          }
        },
        .Moving => {}
      }
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
    switch (state)
    {
      .MoveInput => {},
      .PillInput => {},
      .Moving => |m| {
        var currentPlayer = &game.players.items[game.currentPlayer].value;
        currentPlayer.move(game.board.items, m.move, m.pillPlayer) catch
          unreachable;

        state = .MoveInput;
      }
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    const currentPlayer = &game.players.items[game.currentPlayer];
    if (!sdl.SDL_SetTextureColorModFloat(selectedTexture,
      currentPlayer.color[0],
      currentPlayer.color[1],
      currentPlayer.color[2]))
    {
      return error.SDL_RenderFail;
    }
    switch (state)
    {
      .MoveInput => {
        for (Player.moves) |move|
        {
          try renderSelectionCircleAtSpace(move);
        }
      },
      .PillInput => {
        if (!sdl.SDL_SetRenderDrawColorFloat(
          mainspace.renderer, 1.0, 0.5, 0.0, 1.0))
        {
          return error.SDL_RenderFail;
        }

        for (0.., game.players.items) |p, player|
        {
          if (p == game.currentPlayer or player.value.pos == null)
          {
            continue;
          }

          const walletArea = game.walletRenderArea(p);
          try renderSelectionCircleAtPixel(.{
            walletArea[0][0] - walletArea[1][1]*0.25,
            walletArea[0][1] + walletArea[1][1]*0.5
          });
        }
      },
      .Moving => {}
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {

  }}.deinit,
};

fn renderSelectionCircleAtSpace(pos: Player.Pos)
  error{InvalidPos, SDL_RenderFail}!void
{
  try renderSelectionCircleAtPixel(
    try game.boardToWindowPos(game.board.items, null, pos)
  );
}

fn renderSelectionCircleAtPixel(pos: WinCoord)
  error{SDL_RenderFail}!void
{
  var timeOffset: f32 = 
    @floatFromInt(@mod(std.time.milliTimestamp(), 1000));
  timeOffset = @sin(timeOffset * 0.002 * std.math.pi);

  const winSize = game.boardRenderArea()[1];
  //const center = winSize * @as(mainspace.WinCoord, @splat(0.5));
  const radius = @min(winSize[0], winSize[1]) * (0.025 + timeOffset*0.004);

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
