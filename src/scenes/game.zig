const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");
const menu = @import("../menu.zig");

const Space = @import("../space.zig");
const Ring = @import("../ring.zig");
const Player = @import("../player.zig");

const dice = @import("dice.zig");
const manual = @import("manual_player.zig");

const BoardCoord = Player.Pos;

pub const totalTokens = 21;
pub const TokenType = std.math.IntFittingRange(0, totalTokens);

var gpa: Allocator = undefined;

var ringTexture: *sdl.SDL_Texture = undefined;

var spaceHasTokenTexture: *sdl.SDL_Texture = undefined;
var spaceRerollTextures: [2]*sdl.SDL_Texture = undefined;
var spaceTypeTextures =
  std.EnumArray(Space.Type, *sdl.SDL_Texture).initUndefined();
var arrowTexture: *sdl.SDL_Texture = undefined;

var tokenTexture: *sdl.SDL_Texture = undefined;

var playerTexture: *sdl.SDL_Texture = undefined;

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;
var exchangeLabel: menu.Button = undefined;
var coldStorageLabel: menu.Button = undefined;

var spaces = std.ArrayList(Space).empty;
pub var board = std.ArrayList(Ring).empty;

const Color = @Vector(4, f32);
pub const PlayerEntry = struct {
  color: Color,
  controller: ?*const Scene,
  value: Player,
};
pub var players: std.ArrayList(PlayerEntry) = .empty;

pub var currentPlayer: u8 = undefined;

// Updates currentPlayerIndex and currentPlayer to be the next in line
pub fn nextTurn() void
{
  currentPlayer =
    (currentPlayer + 1) % @as(u8, @intCast(players.items.len));
}

//var moves: [4]BoardCoord = @splat(null);
//var moveLength: u8 = 0;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    try loadTextures();

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

    exchangeLabel = try .initFromText(
      .{0.5, 0.5}, .{0.45, 0.98}, 0.02, menuFont, "Exchange Wallet"
    );
    coldStorageLabel = try .initFromText(
      .{0.5, 0.5}, .{0.55, 0.98}, 0.02, menuFont, "Cold Storage"
    );

    const jsonOut =
      try jsonFromFile(allocator, []struct {
        color: [3]f32,
        entryIndex: u8,
      }, &.{"assets", "metadata", "players.json"});
    defer jsonOut.deinit();

    try players.ensureTotalCapacity(allocator, jsonOut.value.len);
    log.debug("Player array position: {*}\n", .{players.items});

    for (jsonOut.value) |player|
    {
      log.info("Loading player {any}\n", .{player.color});

      players.append(allocator, .{
        .color = player.color ++ .{1.0},
        .controller = null,//Scene.scenes.getPtrConst(.AI),
        .value = .{
          .pos = Player.startingPos,
          .entryIndex = player.entryIndex,
          .exchangeTokens = 0,
          .coldStorageTokens = 0,
          .lostTokens = 0,
        }
      }) catch unreachable;
    }

    try loadBoard(allocator);

    currentPlayer =
      mainspace.rand.uintLessThan(u8, @intCast(players.items.len));

    return &scene;
  }}.init,
  
  .getInput = struct {fn getInput(
    event: sdl.SDL_Event,
    keys: []const bool,
    mPos: @Vector(2, f32),
    mButtons: sdl.SDL_MouseButtonFlags) !bool
  {
    if (players.items[currentPlayer].controller) |controller|
    {
      _ = try controller.getInput(event, keys, mPos, mButtons);
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
    if (players.items[currentPlayer].controller) |controller|
    {
      try controller.update();
    } else
    {
      nextTurn();
      _ = players.items[currentPlayer].value.getMoves(
        board.items, dice.chosenNumber
      );
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    try renderSpaces(board.items);

    const winSize = boardRenderArea()[1];
    const size = @min(winSize[0], winSize[1]) * 0.1;

    for (0.., players.items) |p, player|
    {
      const pos = blk:{
        const spacePos =
          boardToWindowPos(board.items, @intCast(p), player.value.pos) catch
            unreachable;

        if (player.value.pos == null)
        {
          break:blk spacePos;
        }

        var sharingSpace = false;
        for (0.., players.items) |colP, collidePlayer|
        {
          if (
            colP != p and collidePlayer.value.pos != null and
            @reduce(.And, collidePlayer.value.pos.? == player.value.pos.?))
          {
            sharingSpace = true;
            break;
          }
        }

        if (sharingSpace)
        {
          const offset =
            (try boardToWindowPos(board.items, @truncate(p), null) -
            try boardToWindowPos(board.items, null, .{
              0, @intCast(board.items.len-1)
            })) * @as(WinCoord, @splat(0.025));

          break:blk spacePos + offset;
        } else
        {
          break:blk spacePos;
        }
      };

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

    if (players.items[currentPlayer].controller) |controller|
    {
      try controller.render();
    }

    // Check for main scene to prevent recursion
    // Only this may use a non-equality. Putting this on dice as well would stall the program
    if (Scene.currentScene != Scene.scenes.getPtrConst(.Dice))
    {
      try Scene.scenes.get(.Dice).render();
    }

    // Only show manual player because we don't have single-device multiplayer yet
    for (0.., players.items) |p, player|
    {
      if (player.controller != null)
      {
        try renderPlayerWallet(board.items, p, walletRenderArea(p));
      }
    }
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    board.deinit(gpa);
    spaces.deinit(gpa);

    players.deinit(gpa);

    coldStorageLabel.deinit();
    exchangeLabel.deinit();
    sdl.TTF_CloseFont(menuFont);

    sdl.SDL_DestroyTexture(spaceHasTokenTexture);
    sdl.SDL_DestroyTexture(spaceRerollTextures[0]);
    sdl.SDL_DestroyTexture(spaceRerollTextures[1]);
    sdl.SDL_DestroyTexture(arrowTexture);
    for (spaceTypeTextures.values) |texture|
    {
      sdl.SDL_DestroyTexture(texture);
    }
    sdl.SDL_DestroyTexture(playerTexture);
  }}.deinit,
};

pub fn reset() void
{
  for (players.items) |*player|
  {
    player.value.pos = Player.startingPos;
    player.value.exchangeTokens = 0;
    player.value.coldStorageTokens = 0;
    player.value.lostTokens = 0;
  }

  for (board.items) |*ring|
  {
    for (ring.spaces) |*space|
    {
      if (space.hasToken == false)
      {
        space.hasToken = true;
        ring.tokenCount += 1;
      }
    }
  }
}

fn loadTextures() !void
{
  ringTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{"assets", "images", "selected.svg"})
  ) orelse return error.SDL_LoadFail;

  spaceHasTokenTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{
      "assets", "images", "spaces", "token_space.svg"
    })
  ) orelse return error.SDL_LoadFail;
  spaceRerollTextures[0] = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{
      "assets", "images", "spaces", "no_reroll.svg"
    })
  ) orelse return error.SDL_LoadFail;
  spaceRerollTextures[1] = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{
      "assets", "images", "spaces", "reroll.svg"
    })
  ) orelse return error.SDL_LoadFail;
  inline for (0..spaceTypeTextures.values.len) |t|
  {
    const spaceType: Space.Type = @enumFromInt(t);

    const filename = spaceType.toSnakeStr();
    const path = filename[0..filename.len-1] ++
      switch (@as(Space.Type, @enumFromInt(t)))
      {
        .OrangePill, .Moon => ".png",
        else => ".svg"
      };
    log.debug("Loading \"{s}\"\n", .{path});

    spaceTypeTextures.values[t] = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath(&.{"assets", "images", "spaces", path})
    ) orelse return error.SDL_LoadFail;
  }
  arrowTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{"assets", "images", "epoch_arrow.svg"})
  ) orelse return error.SDL_LoadFail;

  tokenTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{"assets", "images", "token.png"})
  ) orelse return error.SDL_LoadFail;

  playerTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath(&.{"assets", "images", "player.svg"})
  ) orelse return error.SDL_LoadFail;
}

fn loadBoard(allocator: Allocator) !void
{
  const jsonOut =
    try jsonFromFile(allocator, [][]Space,
      &.{"assets", "metadata", "board.json"});
  defer jsonOut.deinit();

  const spaceCount = blk:{
    var spaceCount: u16 = 0;

    for (jsonOut.value) |ring|
    {
      spaceCount += @intCast(ring.len);
    }

    break:blk spaceCount;
  };

  try spaces.ensureTotalCapacity(allocator, spaceCount+1);
  try board.ensureTotalCapacity(allocator, jsonOut.value.len+1);

  for (jsonOut.value) |ring|
  {
    board.append(allocator,
      .{
        .spaces = spaces.items[spaces.items.len..spaces.items.len],
        .tokenCount = 0,
      }) catch
      unreachable;

    for (ring) |space|
    {
      spaces.append(allocator, space) catch unreachable;

      if (space.hasToken == true)
      {
        board.items[board.items.len-1].tokenCount += 1;
      }
      
      board.items[board.items.len-1].spaces.len += 1;
    }
  }

  spaces.append(allocator, .{
    .reroll = false,
    .type = .Moon,
  }) catch unreachable;
  board.append(allocator, .{
    .spaces = spaces.items[spaces.items.len-1..spaces.items.len],
    .tokenCount = 0,
  }) catch unreachable;
}

// Parsed data must be freed with .deinit()
fn jsonFromFile(allocator: Allocator, T: type, path: []const []const u8)
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

fn renderSpaces(spaceArr: []Ring) error{SDL_RenderFail, InvalidPos}!void
{
  var noErr = true;
  //const center = boardRenderCenter();

  for (spaceArr, 0..spaceArr.len) |ring, y|
  {
    //const radius = getRingRadius(@intCast(spaceArr.len), @intCast(y));
    //if (!sdl.SDL_RenderTexture(
    //  mainspace.renderer, ringTexture, null,
    //  &.{
    //    .x = center[0]-radius,
    //    .y = center[1]-radius,
    //    .w = radius*2,
    //    .h = radius*2,
    //  }))
    //{
    //  return error.SDL_RenderFail;
    //}

    for (ring.spaces, 0..ring.spaces.len) |space, x|
    {
      const pos =
        try boardToWindowPos(spaceArr, null, .{@intCast(x), @intCast(y)});

      noErr &= sdl.SDL_SetRenderDrawColorFloat(
        mainspace.renderer,
        0.0, 0.25, 1.0, 1.0);

      const nextPos = try boardToWindowPos(
        spaceArr,
        null,
        .{@intCast((x+1)%ring.spaces.len), @intCast(y)});

      noErr &= sdl.SDL_RenderLine(
        mainspace.renderer,
        pos[0], pos[1],
        nextPos[0], nextPos[1]);

      if (ring.tokenCount == 0 and space.jumpIndex != null)
      {
        const i = space.jumpIndex.?;
        const linkPos =
          try boardToWindowPos(spaceArr, null, .{i, @intCast(y+1)});

        noErr &= sdl.SDL_SetRenderDrawColorFloat(
          mainspace.renderer,
          1.0, 0.5, 0.0, 1.0);

        const arrowDir = blk:{
          const arrowVec = WinCoord{linkPos[0]-pos[0], linkPos[1]-pos[1]};
          const len = @sqrt(arrowVec[0]*arrowVec[0] + arrowVec[1]*arrowVec[1]);

          break:blk arrowVec / @as(WinCoord, @splat(len));
        };
        const normDir = WinCoord{-arrowDir[1], arrowDir[0]};
        noErr &= sdl.SDL_RenderTextureAffine(
          mainspace.renderer, arrowTexture, null, &.{
            .x = pos[0]-normDir[0]*25,
            .y = pos[1]-normDir[1]*25
          }, &.{
            .x =
              linkPos[0] -
              arrowDir[0]*getSpaceRadius(spaceArr, .{i, @intCast(y+1)}) -
              normDir[0]*25,
            .y =
              linkPos[1] -
              arrowDir[1]*getSpaceRadius(spaceArr, .{i, @intCast(y+1)}) -
              normDir[1]*25
          }, &.{
            .x = pos[0]+normDir[0]*25,
            .y = pos[1]+normDir[1]*25
          });
        noErr &= sdl.SDL_RenderLine(
          mainspace.renderer,
          pos[0], pos[1],
          linkPos[0], linkPos[1]);
      }

      try renderSpace(space, pos, getSpaceRadius(spaceArr, .{
        @intCast(x),
        @intCast(y)
      }));
    }
  }

  for (0.., players.items) |p, player|
  {
    const pos = try boardToWindowPos(
      spaceArr, @intCast(p), Player.endingPos
    );
    const moonRadius = getSpaceRadius(spaceArr, .{0, @intCast(spaceArr.len-1)});

    if (!sdl.SDL_SetTextureColorModFloat(
      ringTexture, player.color[0], player.color[1], player.color[2]))
    {
      return error.SDL_RenderFail;
    }
    if (!sdl.SDL_RenderTexture(mainspace.renderer, ringTexture, null, &.{
      .x = pos[0] - moonRadius*0.4,
      .y = pos[1] - moonRadius*0.4,
      .w = moonRadius*0.8,
      .h = moonRadius*0.8,
    }))
    {
      return error.SDL_RenderFail;
    }
  }

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

//fn renderRing(ring: []const Space, radius: f32) !void
//{
//  const center = boardRenderCenter();
//
//  const angleOffset = (std.math.pi*2) / @as(f32, @floatFromInt(ring.len));
//  for (0..ring.len) |s|
//  {
//    const angle = ringStartAngle() + angleOffset*@as(f32, @floatFromInt(s));
//    const dir = WinCoord{@cos(angle), @sin(angle)};
//
//    try renderSpace(
//      ring[s],
//      center + dir*@as(WinCoord, @splat(radius)));
//  }
//}

fn renderSpace(space: Space, pos: mainspace.WinCoord, radius: f32)
  error{SDL_RenderFail}!void
{
  var noErr = true;

  if (space.hasToken != null)
  {
    noErr &= sdl.SDL_RenderTexture(
      mainspace.renderer, spaceHasTokenTexture, null,
      &.{
        .x = pos[0]-radius,
        .y = pos[1]-radius,
        .w = radius*2,
        .h = radius*2,
      }
    );
  }
  noErr &= sdl.SDL_RenderTexture(
    mainspace.renderer, spaceRerollTextures[@intFromBool(space.reroll)], null,
    &.{
      .x = pos[0]-radius,
      .y = pos[1]-radius,
      .w = radius*2,
      .h = radius*2,
    });
  noErr &= sdl.SDL_RenderTexture(
    mainspace.renderer, spaceTypeTextures.get(space.type), null,
    &.{
      .x = pos[0]-radius,
      .y = pos[1]-radius,
      .w = radius*2,
      .h = radius*2,
    });
  if (space.hasToken == true)
  {
    noErr &= sdl.SDL_RenderTexture(
      mainspace.renderer, tokenTexture, null,
      &.{
        .x = pos[0]-radius,
        .y = pos[1]-radius,
        .w = radius*2,
        .h = radius*2,
      }
    );
  }

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

fn renderPlayerWallet(
  spaceArr: []Ring, playerIndex: usize, renderArea: [2]WinCoord)
  error{SDL_RenderFail, InvalidPos}!void
{
  var noErr = true;

  const player = &players.items[playerIndex];

  const tokenRadius: f32 = @min(
    renderArea[1][0]*0.2,
    renderArea[1][1]*0.25,
  );

  //const winSize = mainspace.winSize();
  //
  //noErr &= sdl.SDL_SetRenderDrawColorFloat(
  //  mainspace.renderer,
  //  player.color[0]/4, player.color[1]/4, player.color[2]/4, player.color[3]);
  //noErr &= sdl.SDL_RenderFillRect(
  //  mainspace.renderer, &.{
  //    .x = renderArea[0][0],
  //    .y = renderArea[0][1],
  //    .w = renderArea[1][0],
  //    .h = renderArea[1][1],
  //  }
  //);

  //noErr &= sdl.SDL_SetRenderLogicalPresentation(
  //  mainspace.renderer,
  //  @intFromFloat(@ceil(winSize[0]/(renderArea[1][1]*0.025))),
  //  @intFromFloat(@ceil(winSize[1]/(renderArea[1][1]*0.025))),
  //  sdl.SDL_LOGICAL_PRESENTATION_STRETCH
  //);
  //noErr &= sdl.SDL_SetRenderDrawColorFloat(
  //  mainspace.renderer,
  //  player.color[0], player.color[1], player.color[2], player.color[3]);
  //if (playerIndex == currentPlayer)
  //{
  //  noErr &= sdl.SDL_RenderLine(
  //    mainspace.renderer, 
  //    @ceil(renderArea[0][0]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][1]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][0]/(renderArea[1][1]*0.025)) + 
  //    @ceil(renderArea[1][0]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][1]/(renderArea[1][1]*0.025)),
  //  );
  //} else
  //{
  //  noErr &= sdl.SDL_RenderLine(
  //    mainspace.renderer, 
  //    @ceil(renderArea[0][0]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][1]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][0]/(renderArea[1][1]*0.025)),
  //    @ceil(renderArea[0][1]/(renderArea[1][1]*0.025)) + 
  //    @ceil(renderArea[1][1]/(renderArea[1][1]*0.025)),
  //  );
  //}
  //noErr &= sdl.SDL_SetRenderLogicalPresentation(
  //  mainspace.renderer,
  //  0,
  //  0,
  //  sdl.SDL_LOGICAL_PRESENTATION_DISABLED
  //);

  if (player.controller == Scene.scenes.getPtrConst(.AI))
  {
    noErr &= sdl.SDL_SetTextureColorModFloat(
      playerTexture,
      player.color[0], player.color[1], player.color[2]);
    noErr &= sdl.SDL_RenderTexture(mainspace.renderer, playerTexture, null, &.{
      .x = renderArea[0][0] - renderArea[1][1]*0.5,
      .y = renderArea[0][1] + renderArea[1][1]*0.25,
      .w = renderArea[1][1]*0.5,
      .h = renderArea[1][1]*0.5,
    });
  }

  noErr &= sdl.SDL_SetRenderDrawColorFloat(
    mainspace.renderer,
    1.0, 0.0, 0.0, 1.0);
  noErr &= sdl.SDL_RenderRect(
    mainspace.renderer, &.{
      .x = renderArea[0][0] + renderArea[1][0]*0.05,
      .y = renderArea[0][1] + renderArea[1][1]*0.025,
      .w = renderArea[1][0]*0.4,
      .h = renderArea[1][1]*0.95,
    });

  try renderTokenStack(
    .{
      renderArea[0][0] + renderArea[1][0]*0.25,
      renderArea[0][1] + renderArea[1][1]*0.85
    },
    tokenRadius,
    player.value.exchangeTokens
  );

  noErr &= sdl.SDL_SetRenderDrawColorFloat(
    mainspace.renderer,
    0.0, 0.0, 1.0, 1.0);
  noErr &= sdl.SDL_RenderRect(
    mainspace.renderer, &.{
      .x = renderArea[0][0] + renderArea[1][0]*0.55,
      .y = renderArea[0][1] + renderArea[1][1]*0.025,
      .w = renderArea[1][0]*0.4,
      .h = renderArea[1][1]*0.95,
    });

  try renderTokenStack(
    .{
      renderArea[0][0] + renderArea[1][0]*0.75,
      renderArea[0][1] + renderArea[1][1]*0.85
    },
    tokenRadius,
    player.value.coldStorageTokens
  );

  const radius =
    getSpaceRadius(spaceArr, .{0, @intCast(spaceArr.len-1)}) * 0.5;
  try renderTokenStack(
    try boardToWindowPos(
      spaceArr,
      @intCast(players.items.len-playerIndex-1),
      Player.endingPos
    ) + WinCoord{0, radius*0.5},
    radius,
    players.items[players.items.len-playerIndex-1].value.lostTokens
  );

  try exchangeLabel.render();
  try coldStorageLabel.render();

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

fn renderTokenStack(pos: WinCoord, radius: f32, count: TokenType)
  error{SDL_RenderFail}!void
{
  for (0..count) |t|
  {
    if (!sdl.SDL_RenderTextureAffine(mainspace.renderer, tokenTexture, null, &.{
        .x = pos[0] - radius,
        .y = pos[1] - radius - @as(f32, @floatFromInt(t))*radius*0.1,
      }, &.{
        .x = pos[0] + radius,
        .y = pos[1] - radius - @as(f32, @floatFromInt(t))*radius*0.1,
      }, &.{
        .x = pos[0] - radius,
        .y = pos[1] - @as(f32, @floatFromInt(t))*radius*0.1,
      }))
    {
      return error.SDL_RenderFail;
    }
  }

  const winSize = mainspace.winSize();
  var countLabel = menu.Button.initFromText(
    .{0.5, 0.5}, 
    WinCoord{
      pos[0],
      pos[1] - totalTokens*radius*0.1
    } / winSize,
    0.02,
    menuFont,
    &std.fmt.digits2(count)
  ) catch return;

  try countLabel.render();

  countLabel.deinit();
}

pub fn boardToWindowPos(spaceArr: []Ring, playerIndex: ?u8, pos: BoardCoord)
  error{InvalidPos}!WinCoord
{
  const winSize = boardRenderArea()[1];
  const center = boardRenderCenter();
  
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
        getSpaceRadius(spaceArr, .{0, @intCast(spaceArr.len-1)}) * 0.6;

    return center + dir*@as(WinCoord, @splat(dis));
  }

  const startAngle = ringStartAngle(pos.?[1]);
  const angleOffset =
    (std.math.pi*2) / @as(f32, @floatFromInt(spaceArr[pos.?[1]].spaces.len));
  const angle = startAngle + angleOffset*@as(f32, @floatFromInt(pos.?[0]));

  const dir = WinCoord{@cos(angle), @sin(angle)};
  const radius = getRingRadius(@intCast(spaceArr.len), pos.?[1]);
  return center + dir*@as(WinCoord, @splat(radius));
}

pub fn windowToBoardPos(spaceArr: []Ring, pos: WinCoord) BoardCoord
{
  const ringCount: f32 = @floatFromInt(spaceArr.len);

  const center = boardRenderCenter();

  const dis = std.math.hypot(pos[0] - center[0], pos[1] - center[1]);

  const maxRadius = getRingRadius(@intCast(spaceArr.len), 0);
  const radiusOffset = maxRadius / (ringCount-1);

  const ringIndex: u8 = @intFromFloat(std.math.clamp(
    ringCount-@round(dis/radiusOffset)-1,
    0, ringCount-1
  ));

  const ringLen: f32 = @floatFromInt(spaceArr[ringIndex].spaces.len);

  const angle =
    -std.math.atan2(pos[0] - center[0], pos[1] - center[1]) +
    std.math.pi*0.5 -
    ringStartAngle(ringIndex);
  const angleOffset = std.math.pi*2 / ringLen;

  const spaceIndex: u8 =
    @intFromFloat(@mod(@round(angle / angleOffset), ringLen));

  return .{spaceIndex, @intCast(std.math.clamp(ringIndex, 0, spaceArr.len-1))};
}

pub fn getRingRadius(ringCount: u8, index: u8) f32
{
  const winSize = boardRenderArea()[1];
  const maxRadius = @min(winSize[0], winSize[1]) * 0.45;

  const radiusOffset = maxRadius / @as(f32, @floatFromInt(ringCount-1));

  return maxRadius - radiusOffset*@as(f32, @floatFromInt(index));
}

fn getSpaceRadius(spaceArr: []Ring, pos: BoardCoord) f32
{
  if (pos == null)
  {
    return 0.0;
  }

  const winSize = boardRenderArea()[1];
  const boardSize = @min(winSize[0], winSize[1]);

  if (pos.?[1] < spaceArr.len-1)
  {
    return boardSize * @as(f32, 0.025);
  } else
  {
    return boardSize * @as(f32, 0.05);
  }
}

fn ringStartAngle(ringIndex: u8) f32
{
  return @as(f32, @floatFromInt(ringIndex % 2)) * 0.1;
}

pub fn boardRenderArea() [2]WinCoord
{
  const winSize = mainspace.winSize();

  return .{@splat(0), .{winSize[0], winSize[1]*0.8}};
}

fn boardRenderCenter() WinCoord
{
  const winSize = boardRenderArea();

  return (winSize[0]+winSize[1]) * @as(WinCoord, @splat(0.5));
}

pub fn walletRenderArea(playerIndex: usize) [2]WinCoord
{
  const winSize = mainspace.winSize();

  if (
    players.items[playerIndex].controller == Scene.scenes.getPtrConst(.Manual))
  {
    return .{
      .{winSize[0]*0.4, winSize[1]*0.8},
      .{winSize[0]*0.2, winSize[1]*0.2}
    };
  } else
  {
    var aiIndex: usize = 0;
    for (0..playerIndex) |p|
    {
      if (players.items[p].controller) |controller|
      {
        if (controller != Scene.scenes.getPtrConst(.Manual))
        {
          aiIndex += 1;
        }
      }
    }
    return .{
      .{winSize[0]*0.9, winSize[1]*(@as(f32, @floatFromInt(aiIndex))*0.1)},
      .{winSize[0]*0.1, winSize[1]*0.1}
    };
  }
}
