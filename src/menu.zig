const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const directoryManager = @import("directory_manager.zig");

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

pub const Button = struct
{
  const Self = @This();

  var showHitboxes = false;

  // Pos and height are relative to the window
  origin: WinCoord,
  pos: WinCoord,
  height: f32,
  texture: *sdl.SDL_Texture,

  pub fn initFromText(
    origin: WinCoord,
    pos: WinCoord,
    height: f32,
    font: *sdl.TTF_Font,
    label: []const u8) error{SDL_LoadFail}!Self
  {
    if (label.len == 0)
    {
      return .{
        .origin = origin,
        .pos = pos,
        .height = height,
        .texture =
          sdl.SDL_CreateTexture(
            mainspace.renderer,
            sdl.SDL_PIXELFORMAT_RGBA32,
            sdl.SDL_TEXTUREACCESS_STATIC,
            1,
            1
          ) orelse return error.SDL_LoadFail,
      };
    }

    const surface = sdl.TTF_RenderText_Solid(font, label.ptr, label.len, .{
      .r = 0xFF,
      .g = 0xFF,
      .b = 0xFF,
      .a = 0xFF
    });
    defer sdl.SDL_DestroySurface(surface);

    return .{
      .origin = origin,
      .pos = pos,
      .height = height,
      .texture =
        sdl.SDL_CreateTextureFromSurface(mainspace.renderer, surface) orelse
          return error.SDL_LoadFail,
    };
  }

  pub fn initFromTexture(
    io: Io,
    origin: WinCoord,
    pos: WinCoord,
    height: f32,
    path: []const []const u8) !Self
  {
    return .{
      .origin = origin,
      .pos = pos,
      .height = height,
      .texture = sdl.IMG_LoadTexture(
        mainspace.renderer, try directoryManager.getPath(io, path)
      ) orelse return error.SDL_LoadFail,
    };
  }

  pub fn deinit(self: *Self) void
  {
    sdl.SDL_DestroyTexture(self.texture);

    self.* = undefined;
  }

  pub fn contains(self: Self, pos: WinCoord) bool
  {
    const winSize = mainspace.winSize();

    const ratio =
      @as(f32, @floatFromInt(self.texture.w)) /
      @as(f32, @floatFromInt(self.texture.h));
    const trueHeight = winSize[1] * self.height;

    const trueCorners = [2]WinCoord{
      .{
        winSize[0]*self.pos[0] - trueHeight*ratio*self.origin[0],
        winSize[1]*self.pos[1] - trueHeight*self.origin[1]
      },
      .{
        winSize[0]*self.pos[0] + trueHeight*ratio*self.origin[0],
        winSize[1]*self.pos[1] + trueHeight*self.origin[1]
      },
    };

    return
      pos[0] > trueCorners[0][0] and pos[1] > trueCorners[0][1] and
      pos[0] < trueCorners[1][0] and pos[1] < trueCorners[1][1];
  }

  pub fn render(self: Self) !void
  {
    const winSize = mainspace.winSize();

    const ratio =
      @as(f32, @floatFromInt(self.texture.w)) /
      @as(f32, @floatFromInt(self.texture.h));
    const trueHeight = winSize[1] * self.height;

    const drawRect = sdl.SDL_FRect{
      .x = winSize[0]*self.pos[0] - trueHeight*ratio*self.origin[0],
      .y = winSize[1]*self.pos[1] - trueHeight*self.origin[1],
      .w = trueHeight * ratio,
      .h = trueHeight 
    };

    if (
      !sdl.SDL_RenderTexture(mainspace.renderer, self.texture, null, &drawRect))
    {
      return error.SDL_RenderFail;
    }

    // Hitbox rendering
    if (showHitboxes)
    {
      _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 1, 1, 1, 1);
      _ = sdl.SDL_RenderRect(mainspace.renderer, &drawRect);
    }
  }
};

pub const TextBox = struct
{
  const Self = @This();

  pub const Oom = Allocator.Error;
  pub const SdlFail = error{SDL_LoadFail};
  pub const Error = Oom || SdlFail;

  /// syncTexture should be run after modification
  text: std.ArrayList(u8),
  font: *sdl.TTF_Font,
  hitbox: Button,

  pub fn init(
    allocator: Allocator,
    origin: WinCoord,
    pos: WinCoord,
    height: f32,
    font: *sdl.TTF_Font) Error!Self
  {
    return .{
      .text = try .initCapacity(allocator, 64),
      .font = font,
      .hitbox = try .initFromText(origin, pos, height, font, ""),
    };
  }

  pub fn deinit(self: *Self, allocator: Allocator) void
  {
    self.hitbox.deinit();
    self.text.deinit(allocator);
  }

  pub fn pushString(self: *Self, allocator: Allocator, text: []const u8)
    Error!void
  {
    try self.text.appendSlice(allocator, text);

    try self.syncTexture();
  }

  /// Pops popLen characters from self.text and updates the texture
  /// If popLen > self.text.items.len, empties self.text
  pub fn popString(self: *Self, popLen: usize)
    SdlFail!void
  {
    if (popLen < self.text.items.len)
    {
      self.text.shrinkRetainingCapacity(self.text.items.len - popLen);
    } else
    {
      self.text.clearRetainingCapacity();
    }

    try self.syncTexture();
  }

  /// renders self.text to self.hitbox.texture
  pub fn syncTexture(self: *Self) SdlFail!void
  {
    const hitboxConfig = self.hitbox;

    self.hitbox.deinit();

    self.hitbox = try .initFromText(
      hitboxConfig.origin,
      hitboxConfig.pos,
      hitboxConfig.height,
      self.font,
      self.text.items);
  }
};
