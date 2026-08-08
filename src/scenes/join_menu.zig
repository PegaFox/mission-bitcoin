const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");

const Player = @import("../player.zig");

const game = @import("game.zig");
const remote = @import("remote_player.zig");
const serialize = @import("../serialize.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

var gpa: Allocator = undefined;

const fontQuality = 100; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var playerLabel: menu.Button = undefined;
var playerButton: menu.Button = undefined;

var joinCodeButton: menu.Button = undefined;
var joinCodeInputActive: bool = false;
var joinCodeInput: menu.TextBox = undefined;

var connectButton: menu.Button = undefined;

var backButton: menu.Button = undefined;

var state: union(enum)
{
  Disconnected,
  ChoosingPlayer: struct {
    selectedPlayer: game.PlayerIndex,
    playerOptions: [game.maxPlayers]bool,
  },
} = .Disconnected;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    menuFont = sdl.TTF_OpenFont(
      try directoryManager.getPath(mainspace.io, &.{
        "assets", "fonts", "3270NerdFont-Regular.ttf"
      }),
      fontQuality
    ) orelse
    {
      log.err("Failed to load font: {s}\n", .{sdl.SDL_GetError()});
      return error.SDL_LoadFail;
    };

    playerLabel = try .initFromText(
      .{0.5, 0.5}, .{0.5, 0.075}, 0.05, menuFont, "choose a color"
    );
    playerButton = try .initFromTexture(mainspace.io,
      .{0.5, 0.5}, .{0.0, 0.2}, 0.15, &.{
        "assets", "images", "player.svg"
      }
    );

    joinCodeButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.4}, 0.1, menuFont, "join code");
    joinCodeInput = 
      try .init(allocator, .{0.5, 0.5}, .{0.5, 0.5}, 0.1, menuFont);
    connectButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.7}, 0.1, menuFont, "connect");
    backButton =
      try .initFromText(.{0.5, 0.5}, .{0.5, 0.85}, 0.1, menuFont, "back");

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

    switch (event.type)
    {
      sdl.SDL_EVENT_MOUSE_BUTTON_DOWN =>
      {
        if (event.button.button != sdl.SDL_BUTTON_LEFT)
        {
          return true;
        }

        if (state == .ChoosingPlayer)
        {
          for (0..game.players.items.len) |p|
          {
            log.debug("{}, {}\n", .{p, state.ChoosingPlayer.playerOptions.len});
            if (!state.ChoosingPlayer.playerOptions[p])
            {
              continue;
            }

            playerButton.pos[0] = playerButtonPos(p)[0];

            if (playerButton.contains(.{event.button.x, event.button.y}))
            {
              log.info("Selected player updated to {}\n", .{p});

              state.ChoosingPlayer.selectedPlayer = @intCast(p);

              game.players.items[p].controller =
                Scene.scenes.getPtrConst(.Manual);

              log.debug("Sending player list to peers\n", .{});
              for (remote.connections.items) |connection|
              {
                remote.sendLocalPlayers(mainspace.io, connection) catch |e|
                {
                  log.err(
                    "Failed to send initial player info to {f}: {}",
                    .{connection.socket.address, e}
                  );
                };
              }

              var readBuffer:
                [@sizeOf(remote.NetPlayerIndex) + @sizeOf(u64)*4]u8 = undefined;
              for (0.., remote.connections.items) |c, connection|
              {
                var connReader = connection.reader(mainspace.io, &readBuffer);

                const newCurrentPlayer = serialize.deserialize(
                  game.PlayerIndex,
                  connReader.interface.takeInt(
                    remote.NetPlayerIndex, .big
                  ) catch |e|
                  blk:{
                    if (e == Io.Reader.Error.EndOfStream)
                    {
                      log.err(
                        "Failed to get current player from {f}: {}",
                        .{connection.socket.address, e}
                      );
                    } else
                    {
                      log.err(
                        "Failed to get current player from {f}: {}",
                        .{connection.socket.address, connReader.err.?}
                      );
                    }
                    break:blk 0;
                  }
                );
                log.debug(
                  "Got current player from peer {f}\n",
                  .{connection.socket.address}
                );

                var newRandomState: [4]u64 = undefined;
                connReader.interface.readSliceEndian(
                  u64, &newRandomState, .big
                ) catch |e|
                {
                  if (e == Io.Reader.Error.EndOfStream)
                  {
                    log.err(
                      "Failed to get rng state from {f}: {}",
                      .{connection.socket.address, e}
                    );
                  } else
                  {
                    log.err(
                      "Failed to get rng state from {f}: {}",
                      .{connection.socket.address, connReader.err.?}
                    );
                  }
                };
                log.debug(
                  "Got rng state ({any}) from peer {f}\n",
                  .{newRandomState, connection.socket.address}
                );

                if (c > 0)
                {
                  if (newCurrentPlayer != game.currentPlayer)
                  {
                    log.err(
                      "Client {f} giving conflicting current player ({}, current: {})",
                      .{
                        connection.socket.address,
                        newCurrentPlayer,
                        game.currentPlayer
                      }
                    );
                  }

                  if (!std.mem.eql(u64, &newRandomState, &game.randomGen.s))
                  {
                    log.err(
                      "Client {f} giving conflicting rng state ({any}, current: {any})",
                      .{
                        connection.socket.address,
                        newRandomState,
                        game.randomGen.s
                      }
                    );
                  }
                }

                game.currentPlayer = newCurrentPlayer;
                game.randomGen.s = newRandomState;

                Scene.currentScene = Scene.scenes.getPtrConst(.Game);
              }
            }
          }
        }

        if (joinCodeInput.hitbox.contains(.{event.button.x, event.button.y}))
        {
          joinCodeInputActive = true;
          if (!sdl.SDL_StartTextInput(mainspace.window))
          {
            log.err(
              "SDL failed to start textinput for join code input: {s}",
              .{sdl.SDL_GetError()}
            );
          }
        } else
        {
          joinCodeInputActive = false;
          if (!sdl.SDL_StopTextInput(mainspace.window))
          {
            log.err(
              "SDL failed to stop textinput for join code input: {s}",
              .{sdl.SDL_GetError()}
            );
          }
        }

        if (connectButton.contains(.{event.button.x, event.button.y}))
        connFail: {
          const address =
            net.IpAddress.parseLiteral(joinCodeInput.text.items) catch |e|
          {
            log.err(
              "Failed to parse ip address \"{s}\": {}\n",
              .{joinCodeInput.text.items, e}
            );
            break:connFail;
          };

          const serverData = connect(mainspace.io, address) catch |e|
          {
            switch (e)
            {
              ConnectErrorClass.ConnectError =>
              {
                log.err("Failed to connect to address: {}\n", .{connectErr});
              },
              ConnectErrorClass.ReadAddressCountError =>
              {
                log.err(
                  "Failed to get connection count from server: {}\n",
                  .{connectErr}
                );
              },
              ConnectErrorClass.ReadAddressError =>
              {
                log.err(
                  "Failed to get ip addresses from server: {}\n",
                  .{connectErr}
                );
              },
              ConnectErrorClass.ReadPlayerCountError =>
              {
                log.err(
                  "Failed to get remote player count from server: {}\n",
                  .{connectErr}
                );
              },
              ConnectErrorClass.ReadPlayerError =>
              {
                log.err(
                  "Failed to get remote player list from server: {}\n",
                  .{connectErr}
                );
              },
            }

            break:connFail;
          };

          log.debug(
            "Connected to address {f}\n",
            .{serverData.serverConnection.socket.address}
          );

          state = .{.ChoosingPlayer = .{
            .playerOptions = @splat(true),
            .selectedPlayer = std.math.maxInt(game.PlayerIndex)
          }};

          remote.connections.appendAssumeCapacity(serverData.serverConnection);
          for (0.., serverData.remotePlayers) |p, player|
          {
            if (player == null)
            {
              continue;
            }

            state.ChoosingPlayer.playerOptions[p] = false;

            game.players.items[p].controller =
              Scene.scenes.getPtrConst(.Remote);
            game.players.items[p].value = player.?;

            remote.playerConnections[p] =
              &remote.connections.items[remote.connections.items.len-1];
          }

          for (serverData.friendAddresses[0..serverData.friendAddressCount])
          |friendAddress|
          {
            const peerData = connect(mainspace.io, friendAddress) catch
              break:connFail;
            remote.connections.appendAssumeCapacity(peerData.serverConnection);

            for (0.., peerData.remotePlayers) |p, player|
            {
              if (player == null)
              {
                continue;
              }

              state.ChoosingPlayer.playerOptions[p] = false;

              game.players.items[p].controller =
                Scene.scenes.getPtrConst(.Remote);
              game.players.items[p].value = player.?;

              remote.playerConnections[p] =
                &remote.connections.items[remote.connections.items.len-1];
            }
          }
        }

        if (backButton.contains(.{event.button.x, event.button.y}))
        {
          Scene.currentScene = Scene.scenes.getPtrConst(.StartMenu);
        }
      },
      sdl.SDL_EVENT_KEY_DOWN =>
      {
        if (joinCodeInputActive and event.key.key == sdl.SDLK_BACKSPACE)
        {
          try joinCodeInput.popString(1);
        }
      },
      sdl.SDL_EVENT_TEXT_INPUT =>
      {
        const textSlice = event.text.text[0..std.mem.len(event.text.text)];

        try joinCodeInput.pushString(gpa, textSlice);
      },
      else => {}
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {

  }}.update,
  
  .render = struct {fn render() !void
  {
    if (state == .ChoosingPlayer)
    {
      try playerLabel.render();
      for (0.., game.players.items) |p, player|
      {
        playerButton.pos[0] = playerButtonPos(p)[0];
                  
        const option = state.ChoosingPlayer.playerOptions[p];
        //const selected = state.ChoosingPlayer.selectedPlayer == p;
        const colorDivisor =
          //@as(f32, @floatFromInt(@intFromBool(!option)))*2 + 
          @as(f32, @floatFromInt(@intFromBool(!option)))*3 + 1;
        if (!sdl.SDL_SetTextureColorModFloat(playerButton.texture,
          player.color[0] / colorDivisor,
          player.color[1] / colorDivisor,
          player.color[2] / colorDivisor))
        {
          return error.SDL_RenderFail;
        }
        try playerButton.render();
      }
    }

    try joinCodeButton.render();
    try joinCodeInput.hitbox.render();
    try connectButton.render();
    try backButton.render();
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    backButton.deinit();
    joinCodeInput.deinit(gpa);
    connectButton.deinit();
    joinCodeButton.deinit();

    playerButton.deinit();
    playerLabel.deinit();

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};

fn playerButtonPos(index: usize) WinCoord
{
  const playerOffset = 1.0/@as(f32, @floatFromInt(game.players.items.len));

  return .{
    playerOffset*0.5 + playerOffset*@as(f32, @floatFromInt(index)),
    playerButton.pos[1]
  };
}

const ConnectErrorClass = error
{
  ConnectError,
  ReadAddressCountError,
  ReadAddressError,
  ReadPlayerCountError,
  ReadPlayerError,
};
var connectErr: (
  net.IpAddress.ConnectError ||
  net.Stream.Reader.Error ||
  error {EndOfStream}
) = undefined;

/// Data given by a server to a client upon connection
const GreetingData = struct
{
  serverConnection: net.Stream,

  /// Other addresses known by the server
  friendAddresses: [game.maxPlayers]net.IpAddress,
  friendAddressCount: game.PlayerIndex,

  /// Players owned by the server
  remotePlayers: [game.maxPlayers]?Player,
};

fn connect(io: Io, address: net.IpAddress) ConnectErrorClass!GreetingData
{
  var connection = address.connect(
    io,
    .{.mode = .stream, .protocol = .tcp}
  ) catch |e|
  {
    connectErr = e;

    return ConnectErrorClass.ConnectError;
  };
  // Make sure remote address is stored here. I sure hope this doesn't break anything!
  connection.socket.address = address;

  var readBuffer: [64]u8 = undefined;
  var reader = connection.reader(io, &readBuffer);

  const addressCount =
    reader.interface.takeInt(remote.NetPlayerIndex, .big) catch |e|
  {
    if (e == Io.Reader.Error.EndOfStream)
    {
      connectErr = @errorCast(e);
    } else
    {
      connectErr = @errorCast(reader.err.?);
    }

    return ConnectErrorClass.ReadAddressCountError;
  };
  log.debug("Got connection count from server\n", .{});

  var addresses: [game.maxPlayers]remote.NetIpAddress = undefined;
  reader.interface.readSliceEndian(
    remote.NetIpAddress,
    addresses[0..addressCount],
    .big
  ) catch |e|
  {
    if (e == Io.Reader.Error.EndOfStream)
    {
      connectErr = @errorCast(e);
    } else
    {
      connectErr = @errorCast(reader.err.?);
    }

    return ConnectErrorClass.ReadAddressError;
  };
  log.debug("Got addresses from server\n", .{});

  var remotePlayers: remote.NetPlayersPacket = undefined;
  reader.interface.readSliceEndian(
    remote.NetPlayerOpt,
    &remotePlayers,
    .big
  ) catch |e|
  {
    if (e == Io.Reader.Error.EndOfStream)
    {
      connectErr = @errorCast(e);
    } else
    {
      connectErr = @errorCast(reader.err.?);
    }

    return ConnectErrorClass.ReadPlayerError;
  };
  log.debug("Got players from server\n", .{});

  return .{
    .serverConnection = connection,
    .friendAddressCount = serialize.deserialize(game.PlayerIndex, addressCount),
    .friendAddresses =
      serialize.deserialize([game.maxPlayers]net.IpAddress, addresses),
    .remotePlayers = 
      serialize.deserialize([game.maxPlayers]?Player, remotePlayers),
  };
}
