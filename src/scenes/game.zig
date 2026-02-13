const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const sin = std.math.sin;
const cos = std.math.cos;

const Scene = @import("../scene.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

const Space = @import("../space.zig");
const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

pub const totalTokens = 21;
pub const TokenType = std.math.IntFittingRange(0, totalTokens);

var spaceHasTokenTexture: *sdl.SDL_Texture = undefined;
var spaceRerollTextures: [2]*sdl.SDL_Texture = undefined;
var spaceTypeTextures =
  std.EnumArray(Space.Type, *sdl.SDL_Texture).initUndefined();

var playerTexture: *sdl.SDL_Texture = undefined;

var totalSpaces: usize = 0;
pub fn getTotalSpaces() usize {return totalSpaces;}
var board: std.json.Parsed([][]Space) = undefined;

var players: [4]Player = @splat(.{
  .pos = Player.startingPos,
  .exchangeTokens = 0,
  .coldStorageTokens = 0,
  .lostTokens = 0,
});

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    spaceHasTokenTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath("assets/images/spaces/token_space.svg"));
    spaceRerollTextures[0] = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath("assets/images/spaces/no_reroll.svg"));
    spaceRerollTextures[1] = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath("assets/images/spaces/reroll.svg"));
    inline for (0..spaceTypeTextures.values.len) |t|
    {
      const spaceType: Space.Type = @enumFromInt(t);

      const filename = spaceType.toSnakeStr();
      const path =
        "assets/images/spaces/" ++ filename[0..filename.len-1] ++ ".svg";
      log.debug("Loading \"{s}\"\n", .{path});

      spaceTypeTextures.values[t] = sdl.IMG_LoadTexture(
        mainspace.renderer,
        try directoryManager.getPath(path));
    }

    playerTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath("assets/images/player.svg"));

    try loadBoard(allocator);

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
    try renderSpaces(board.value);

    const winSize = mainspace.winSize();
    const size = @min(winSize[0], winSize[1]) * 0.025;

    for (players) |player|
    {
      const pos = getSpacePos(board.value, player.pos);

      if (!sdl.SDL_RenderTexture(
        mainspace.renderer, playerTexture, null,
        &.{
          .x = pos[0],
          .y = pos[1],
          .w = size,
          .h = size,
        }))
      {
        return error.SDL_RenderFail;
      }
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    board.deinit();
  }}.deinit,
};

fn loadBoard(allocator: Allocator) !void
{
  const boardFilePath =
    try directoryManager.getPath("assets/metadata/board.json");
  var boardFile = try std.fs.openFileAbsolute(boardFilePath, .{});
  defer boardFile.close();

  var readBuffer: [1024]u8 = undefined;
  var fileReader = boardFile.reader(&readBuffer);
  var jsonReader = std.json.Reader.init(allocator, &fileReader.interface);
  defer jsonReader.deinit();

  const spaces = try std.json.parseFromTokenSource(
    [][]Space,
    allocator,
    &jsonReader,
    .{});

  board = spaces;

  for (board.value) |ring|
  {
    totalSpaces += ring.len;
  }
}

fn renderSpaces(spaces: [][]Space) !void
{
  for (spaces, 0..spaces.len) |ring, y|
  {
    for (ring, 0..ring.len) |space, x|
    {
      try renderSpace(space, getSpacePos(spaces, .{@intCast(x), @intCast(y)}));
    }
  }
}

fn renderRing(ring: []const Space, radius: f32) !void
{
  const center = mainspace.winSize() * @as(WinCoord, @splat(0.5));

  const angleOffset = (std.math.pi*2) / @as(f32, @floatFromInt(ring.len));
  for (0..ring.len) |s|
  {
    const angle = ringStartAngle() + angleOffset*@as(f32, @floatFromInt(s));

    try renderSpace(
      ring[s],
      center + WinCoord{cos(angle), sin(angle)}*@as(WinCoord, @splat(radius)));
  }
}

fn renderSpace(space: Space, pos: mainspace.WinCoord) !void
{
  const winSize = mainspace.winSize();
  const radius = @min(winSize[0], winSize[1]) * 0.025;

  //const radius = 20;

  if (space.canHaveToken)
  {
    if (!sdl.SDL_RenderTexture(
      mainspace.renderer, spaceHasTokenTexture, null,
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

  if (!sdl.SDL_RenderTexture(
    mainspace.renderer, spaceRerollTextures[@intFromBool(space.reroll)], null,
    &.{
      .x = pos[0]-radius,
      .y = pos[1]-radius,
      .w = radius*2,
      .h = radius*2,
    }))
  {
    return error.SDL_RenderFail;
  }
  if (!sdl.SDL_RenderTexture(
    mainspace.renderer, spaceTypeTextures.get(space.type), null,
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

pub fn getSpacePos(spaces: [][]Space, pos: BoardCoord) WinCoord
{
  if (pos == null or @reduce(.And, pos.? == Player.endingPos.?))
  { // TODO: Put actual logic here
    return .{0, 0};
  }

  const center = mainspace.winSize() * @as(WinCoord, @splat(0.5));
  
  const startAngle = ringStartAngle(pos.?[1]);
  const angleOffset =
    (std.math.pi*2) / @as(f32, @floatFromInt(spaces[pos.?[1]].len));
  const angle = startAngle + angleOffset*@as(f32, @floatFromInt(pos.?[0]));

  const dir = WinCoord{cos(angle), sin(angle)};
  const radius = getRingRadius(@intCast(spaces.len), pos.?[1]);
  return center + dir*@as(WinCoord, @splat(radius));
}

pub fn getRingRadius(ringCount: u8, index: u8) f32
{
  const winSize = mainspace.winSize();
  const maxRadius = @min(winSize[0], winSize[1]) * 0.45;

  const radiusOffset = maxRadius / @as(f32, @floatFromInt(ringCount));

  return maxRadius - radiusOffset*@as(f32, @floatFromInt(index));
}

fn ringStartAngle(ringIndex: u8) f32
{
  return @as(f32, @floatFromInt(ringIndex % 2)) * 0.1;
}
