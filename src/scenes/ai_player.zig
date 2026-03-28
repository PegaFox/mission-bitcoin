const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

const Ring = @import("../ring.zig");
const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

var gpa: Allocator = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

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
    if (Player.moves.len == 0)
    {
      return;
    }

    var best = struct {move: BoardCoord, score: i16}{.move = null, .score = 0};
    for (Player.moves) |move|
    {
      const score = spaceValue(game.board.items, move);

      if (best.move == null or score > best.score)
      {
        best = .{.move = move, .score = score};
      }
    }
  }}.update,
  
  .render = struct {fn render() !void
  {

  }}.render,
  
  .deinit = struct {fn deinit() !void
  {

  }}.deinit,
};

fn moveRandom() void
{
  const currentPlayer = &game.players.items[game.currentPlayer].value;

  var otherPlayer = @mod(
    mainspace.rand.uintLessThan(usize, game.players.items.len-1) +
    game.currentPlayer+1,
    game.players.items.len
  );
  while (game.players.items[otherPlayer].controller == null)
  {
    otherPlayer = @mod(
      mainspace.rand.uintLessThan(usize, game.players.items.len-1) +
      game.currentPlayer+1,
      game.players.items.len
    );
  }

  currentPlayer.move(
    game.board.items,
    Player.moves[mainspace.rand.uintLessThan(u3, @intCast(Player.moves.len))],
    &game.players.items[otherPlayer].value
  ) catch unreachable;
}

/// No reason to take enemy positions into account, players can move too much in one turn for that to work
/// Avoid orange pills and spaces halfway between orange pills
/// Prefer cold storage, scaling with number of exchange tokens
/// Use exchange hack if exchange is empty or low relative to enemy exchange accounts
/// Avoid token spaces of exchange account is too full
/// Prefer proximity to exit space if ring tokens are low
/// Avoid 6102 unless exchange/lost tokens are low
/// Prefer reroll spaces if nothing else is particularly attractive

fn spaceValue(board: []Ring, pos: BoardCoord) i16
{
  if (pos == null)
  {
    return std.math.minInt(i16);
  }

  const currentPlayer = &game.players.items[game.currentPlayer].value;

  const ring = &board[pos.?[1]];
  const space = &ring.spaces[pos.?[0]];

  var score: i16 = 0;

  if (space.hasToken == true)
  {
    if (currentPlayer.exchangeTokens < 3)
    {
      score += 10;
    }
  } else
  {
    score += switch (space.type)
    {
      .Default => 0,
      .ColdStorage => 0,
      .ExchangeHack => 0,
      .OrangePill => 0,
      .Exec6102 => 0,
      .Moon => 2140,
    };
  }

  // Prefer spaces closer to the next epoch
  if (currentPlayer.pos != null and ring.tokenCount < 6)
  {
    score += @min(0, 5 - ring.distance(currentPlayer.pos.?[0], pos.?[0]));
  }

  return score;
}
