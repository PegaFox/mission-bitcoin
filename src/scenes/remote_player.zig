const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const serialize = @import("../serialize.zig");

const logger = @import("../log.zig");
const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

var gpa: Allocator = undefined;

var selectedTexture: *sdl.SDL_Texture = undefined;

/// Several types that can be sent over sockets
pub const NetPlayerIndex = serialize.Type(game.PlayerIndex);
pub const NetPlayerPos = serialize.Type(Player.Pos);
pub const NetPlayer = serialize.Type(Player);
pub const NetPlayerOpt = serialize.Type(?Player);
pub const NetPlayersPacket = serialize.Type([game.maxPlayers]?Player);
pub const NetIpAddress = serialize.Type(net.IpAddress);

pub var serverFuture:
  ?Io.Future(@typeInfo(@TypeOf(awaitConnections)).@"fn".return_type.?) = null;

var clientFuture:
  ?Io.Future(@typeInfo(@TypeOf(awaitRemoteMove)).@"fn".return_type.?) = null;
var clientFutureReady: std.atomic.Value(bool) = .{.raw = false};

var localAddress: net.IpAddress = .{.ip4 = .loopback(0)};
var connectionBuffer: [game.maxPlayers-1]net.Stream = undefined;
pub var connections: std.ArrayList(net.Stream) = .initBuffer(&connectionBuffer);
/// Associates connection indexes with player indexes. Used to allow multiple players from one connection
pub var playerConnections: [game.maxPlayers]?*net.Stream = @splat(null);

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    selectedTexture = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath(mainspace.io, &.{
        "assets", "images", "selected.svg"
      })
    );

    if (getLocalIp(mainspace.io)) |address|
    {
      localAddress = address;

      serverFuture =
        mainspace.io.concurrent(awaitConnections, .{mainspace.io}) catch
      blk:{
        log.err(
          "Concurrency unavailable. Multiplayer games cannot be hosted\n",
          .{}
        );
        break:blk null;
      };
    } else |e|
    {
      log.err(
        "Network unavailable: {}. Multiplayer games cannot be hosted\n",
        .{e}
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
    if (clientFuture == null)
    {
      clientFuture = mainspace.io.async(
        awaitRemoteMove, .{mainspace.io, game.players.items}
      );
    }

    // I have no idea how atomic ordering works, but I think this works well enough
    if (!clientFutureReady.load(.acquire))
    {
      return;
    }

    const move = clientFuture.?.await(mainspace.io) catch |e|
    {
      log.err(
        "Failed to get move for peer {f}: {}\n",
        .{playerConnections[game.currentPlayer].?.socket.address, e}
      );
      return;
    };
    clientFuture = null;
    clientFutureReady.store(false, .release);

    try game.players.items[game.currentPlayer].value.move(
      game.board.items,
      move.pos,
      move.target,
    );
  }}.update,
  
  .render = struct {fn render() !void
  {
    //var timeOffset: f32 = 
    //  @floatFromInt(@mod(mainspace.lastFrameTick.toMilliseconds(), 1000));
    //timeOffset = @sin(timeOffset * 0.002 * std.math.pi);

    //const winSize = game.boardRenderArea()[1];
    ////const center = winSize * @as(mainspace.WinCoord, @splat(0.5));
    //const radius = @min(winSize[0], winSize[1]) * (0.025 + timeOffset*0.002);

    //const currentPlayer = &game.players.items[game.currentPlayer];
    //if (!sdl.SDL_SetTextureColorModFloat(selectedTexture,
    //  currentPlayer.color[0],
    //  currentPlayer.color[1],
    //  currentPlayer.color[2]))
    //{
    //  return error.SDL_RenderFail;
    //}
    //for (Player.moves) |move|
    //{
    //  const pos = try game.boardToWindowPos(game.board.items, null, move);
    //  
    //  if (!sdl.SDL_RenderTexture(
    //    mainspace.renderer, selectedTexture, null,
    //    &.{
    //      .x = pos[0]-radius,
    //      .y = pos[1]-radius,
    //      .w = radius*2,
    //      .h = radius*2,
    //    }))
    //  {
    //    return error.SDL_RenderFail;
    //  }
    //}
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    if (serverFuture) |*future|
    {
      future.cancel(mainspace.io) catch |e|
      {
        if (e != error.Canceled)
        {
          return e;
        }
      };
    }

    while (connections.items.len > 0)
    {
      connections.pop().?.close(mainspace.io);
    }
  }}.deinit,
};

fn getLocalIp(io: Io) !net.IpAddress
{
  const remoteAddress =
    net.IpAddress{.ip4 = .{.bytes = @splat(1), .port = 0}};

  const stream =
    try remoteAddress.connect(io, .{.protocol = .udp, .mode = .dgram});
  defer stream.close(mainspace.io);

  var result = stream.socket.address;
  result.setPort(0);

  return result;
}

fn awaitConnections(io: Io) (error{Canceled} || net.IpAddress.ListenError)!void
{
  var server = try localAddress.listen(io, .{.reuse_address = true}); 
  defer server.deinit(io);

  log.debug("Entering accept loop\n", .{});

  // This should never practically exit, but if it does, we can avoid a buffer overflow here
  while (connections.items.len < connections.capacity)
  {
    log.debug(
      "Awaiting connection to {f}...\n",
      .{server.socket.address}
    );
    const connection = server.accept(io) catch |e|
    {
      log.err("Failed to make connection: {}\n", .{e});

      if (e == net.Server.AcceptError.Canceled)
      {
        return;
      } else
      {
        continue;
      }
    };
    log.debug("Received connection from {f}\n", .{connection.socket.address});

    // Upon connection: 
    // - Send other player IPs
    // - Send known player data
    // - Receive client player data
    
    var writeBuffer: [256]u8 = undefined;
    var connWriter = connection.writer(io, &writeBuffer);

    log.debug("Sending connection count to client\n", .{});
    connWriter.interface.writeInt(
      NetPlayerIndex, @intCast(connections.items.len), .big
    ) catch
    {
      log.err(
        "Failed to send connection count to client: {?}\n",
        .{connWriter.err}
      );
    };
    log.debug("Sending ip addresses to client\n", .{});
    for (connections.items) |conn|
    {
      connWriter.interface.writeStruct(
        serialize.serialize(conn.socket.address), .big
      ) catch
      {
        log.err(
          "Failed to send ip address to client: {?}\n",
          .{connWriter.err}
        );
      };
    }

    connWriter.interface.flush() catch
    {
      log.err(
        "Failed to send remaining data to client: {?}\n",
        .{connWriter.err}
      );
    };

    log.debug("Sending player list to client\n", .{});
    sendLocalPlayers(mainspace.io, connection) catch |e|
    {
      log.err("Failed to send player list to client: {}\n", .{e});
    };

    var readBuffer: [256]u8 = undefined;
    var connReader = connection.reader(io, &readBuffer);

    var newPlayerBuffer: NetPlayersPacket = undefined;
    connReader.interface.readSliceEndian(
      NetPlayerOpt, &newPlayerBuffer, .big
    ) catch |e|
    {
      if (e == Io.Reader.Error.EndOfStream)
      {
        log.err("Failed to get remote players from client: {}\n", .{e});
      } else
      {
        log.err(
          "Failed to get remote players from client: {?}\n",
          .{connReader.err}
        );
      }
    };
    log.debug("Got player list from client\n", .{});

    connections.appendAssumeCapacity(connection);
    for (0.., newPlayerBuffer) |p, netPlayer|
    {
      const player = serialize.deserialize(?Player, netPlayer);

      if (player == null)
      {
        continue;
      }

      game.players.items[p].value = player.?;

      game.players.items[p].controller = Scene.scenes.getPtrConst(.Remote);
      playerConnections[p] = &connections.items[connections.items.len-1];
    }

    log.debug("Sending current player to client\n", .{});
    connWriter.interface.writeInt(
      NetPlayerIndex, game.currentPlayer, .big
    ) catch
    {
      log.err(
        "Failed to send current player to client: {}\n",
        .{connWriter.err.?});
    };
    log.debug("Sending rng state ({any}) to client\n", .{game.randomGen.s});
    connWriter.interface.writeSliceEndian(u64, &game.randomGen.s, .big) catch
    {
      log.err(
        "Failed to send rng state to client: {}\n",
        .{connWriter.err.?});
    };
    connWriter.interface.flush() catch
    {
      log.err(
        "Failed to send remaining data to client: {?}\n",
        .{connWriter.err}
      );
    };

    log.debug("Connected!\n", .{});
  }
}

pub fn sendLocalPlayers(io: Io, connection: net.Stream)
  net.Stream.Writer.Error!void
{
  var writeBuffer: [@sizeOf(NetPlayersPacket)]u8 = undefined;
  var connWriter = connection.writer(io, &writeBuffer);
  const writer = &connWriter.interface;

  // Using optional players allows us to store positional information alongside other info
  var ownedPlayers: [game.maxPlayers]?Player = @splat(null);
  for (0.., game.players.items) |p, player|
  {
    if (player.controller) |controller|
    {
      if (
        controller == Scene.scenes.getPtrConst(.Manual) or
        controller == Scene.scenes.getPtrConst(.AI))
      {
        ownedPlayers[p] = player.value;
      }
    }
  }

  writer.writeSliceEndian(
    NetPlayerOpt, &serialize.serialize(ownedPlayers), .big
  ) catch return connWriter.err.?;

  writer.flush() catch return connWriter.err.?;
}

/// Waits until a response is given
fn awaitRemoteMove(io: Io, players: []game.PlayerEntry)
  (error{EndOfStream, Canceled} || net.Stream.Reader.Error)!
  struct {pos: Player.Pos, target: ?*Player}
{
  var readBuffer: [@sizeOf(NetPlayer)]u8 = undefined;
  var connReader =
    playerConnections[game.currentPlayer].?.reader(io, &readBuffer);
  const reader = &connReader.interface;

  const pos = serialize.deserialize(
    Player.Pos,
    reader.takeStruct(NetPlayerPos, .big) catch |e|
    {
      if (e == Io.Reader.Error.EndOfStream)
      {
        return @errorCast(e);
      } else
      {
        return connReader.err.?;
      }
    }
  );

  const target = serialize.deserialize(
    game.PlayerIndex,
    reader.takeInt(NetPlayerIndex, .big) catch |e|
    {
      if (e == Io.Reader.Error.EndOfStream)
      {
        return @errorCast(e);
      } else
      {
        return connReader.err.?;
      }
    }
  );

  // I have no idea how atomic ordering works, but I think this works well enough
  clientFutureReady.store(true, .release);
  return .{
    .pos = pos,
    .target =
      if (target == std.math.maxInt(game.PlayerIndex)) null
      else &players[target].value,
  };
}
