const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

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

var gpa: Allocator = undefined;

var spaceHasTokenTexture: *sdl.SDL_Texture = undefined;
var spaceRerollTextures: [2]*sdl.SDL_Texture = undefined;
var spaceTypeTextures =
  std.EnumArray(Space.Type, *sdl.SDL_Texture).initUndefined();

var playerTexture: *sdl.SDL_Texture = undefined;

var spaces = std.ArrayList(Space).empty;
var board = std.ArrayList([]Space).empty;

const Color = @Vector(4, f32);
var players: std.ArrayList(struct {color: Color, value: Player}) = .empty;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    try loadTextures();

    const jsonOut =
      try jsonFromFile(allocator, [][3]f32, "assets/metadata/players.json");
    defer jsonOut.deinit();

    try players.ensureTotalCapacity(allocator, jsonOut.value.len);
    for (jsonOut.value) |player|
    {
      players.append(allocator, .{
        .color = player ++ .{1.0},
        .value = .{
          .pos = Player.startingPos,
          .exchangeTokens = 0,
          .coldStorageTokens = 0,
          .lostTokens = 0,
        }
      }) catch unreachable;
    }

    try loadBoard(allocator);

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

    if (event.type == sdl.SDL_EVENT_KEY_DOWN)
    {
      _ = players.items[0].value.move(1);
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {

  }}.update,
  
  .render = struct {fn render() !void
  {
    try renderSpaces(board.items);

    const winSize = mainspace.winSize();
    const size = @min(winSize[0], winSize[1]) * 0.05;

    for (players.items, 0..players.items.len) |player, p|
    {
      const pos = getSpacePos(board.items, @intCast(p), player.value.pos) catch
        unreachable;

      _ = sdl.SDL_SetTextureColorModFloat(
        playerTexture,
        player.color[0],
        player.color[1],
        player.color[2]);
      if (!sdl.SDL_RenderTexture(
        mainspace.renderer, playerTexture, null,
        &.{
          .x = pos[0] - size*0.5,
          .y = pos[1] - size*0.5,
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
    board.deinit(gpa);
    spaces.deinit(gpa);

    players.deinit(gpa);

    sdl.SDL_DestroyTexture(spaceHasTokenTexture);
    sdl.SDL_DestroyTexture(spaceRerollTextures[0]);
    sdl.SDL_DestroyTexture(spaceRerollTextures[1]);
    for (spaceTypeTextures.values) |texture|
    {
      sdl.SDL_DestroyTexture(texture);
    }
    sdl.SDL_DestroyTexture(playerTexture);
  }}.deinit,
};

fn loadTextures() !void
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
}

fn loadBoard(allocator: Allocator) !void
{
  const jsonOut =
    try jsonFromFile(allocator, [][]Space, "assets/metadata/board.json");
  defer jsonOut.deinit();

  const spaceCount = blk:{
    var spaceCount: u16 = 0;

    for (jsonOut.value) |ring|
    {
      spaceCount += @intCast(ring.len);
    }

    break:blk spaceCount;
  };

  try spaces.ensureTotalCapacity(allocator, spaceCount);
  try board.ensureTotalCapacity(allocator, jsonOut.value.len);

  for (jsonOut.value) |ring|
  {
    board.append(
      allocator,
      spaces.items[spaces.items.len..spaces.items.len]) catch
      unreachable;

    for (ring) |space|
    {
      spaces.append(allocator, space) catch unreachable;

      board.items[board.items.len-1].len += 1;
    }
  }
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

fn renderSpaces(spaceArr: [][]Space) !void
{
  for (spaceArr, 0..spaceArr.len) |ring, y|
  {
    for (ring, 0..ring.len) |space, x|
    {
      try renderSpace(
        space,
        try getSpacePos(spaceArr, null, .{@intCast(x), @intCast(y)}));
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
    const dir = WinCoord{@cos(angle), @sin(angle)};

    try renderSpace(
      ring[s],
      center + dir*@as(WinCoord, @splat(radius)));
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

pub fn getSpacePos(spaceArr: [][]Space, playerIndex: ?u8, pos: BoardCoord)
  error{InvalidPos}!WinCoord
{
  const winSize = mainspace.winSize();
  const center = winSize * @as(WinCoord, @splat(0.5));
  
  if (pos == Player.startingPos or @reduce(.And, pos.? == Player.endingPos.?))
  {
    const playerIndexF: f32 =
      @floatFromInt(playerIndex orelse {return error.InvalidPos;});
    const angle = std.math.pi*0.25 + playerIndexF * std.math.pi*0.5;

    const dir = WinCoord{@cos(angle), @sin(angle)};
    const dis =
      if (pos == Player.startingPos)
        @min(winSize[0], winSize[1]) * 0.6
      else
        10.0;

    return center + dir*@as(WinCoord, @splat(dis));
  }

  const startAngle = ringStartAngle(pos.?[1]);
  const angleOffset =
    (std.math.pi*2) / @as(f32, @floatFromInt(spaceArr[pos.?[1]].len));
  const angle = startAngle + angleOffset*@as(f32, @floatFromInt(pos.?[0]));

  const dir = WinCoord{@cos(angle), @sin(angle)};
  const radius = getRingRadius(@intCast(spaceArr.len), pos.?[1]);
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
