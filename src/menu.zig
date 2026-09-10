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

    const surface = sdl.TTF_RenderText_Solid_Wrapped(
      font,
      label.ptr,
      label.len,
      .{
        .r = 0xFF,
        .g = 0xFF,
        .b = 0xFF,
        .a = 0xFF
      },
      0
    );
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
    const trueBounds = self.pixelBounds();

    return
      pos[0] > trueBounds[0][0] and
      pos[1] > trueBounds[0][1] and
      pos[0] < trueBounds[0][0]+trueBounds[1][0] and
      pos[1] < trueBounds[0][1]+trueBounds[1][1];
  }

  /// Hitbox in unnormalized space
  pub fn pixelBounds(self: Self) [2]WinCoord
  {
    const winSize = mainspace.winSize();

    const ratio =
      @as(f32, @floatFromInt(self.texture.w)) /
      @as(f32, @floatFromInt(self.texture.h));
    const trueHeight = winSize[1] * self.height;

    return .{
      .{
        winSize[0]*self.pos[0] - trueHeight*ratio*self.origin[0],
        winSize[1]*self.pos[1] - trueHeight*self.origin[1]
      },
      .{
        trueHeight*ratio,
        trueHeight
      },
    };
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
  /// Optional limits for text length
  overflowMode: union(enum)
  {
    /// Ignore text length
    None,
    /// Scroll previous text backwards after the limit, showing only a window
    Scroll: usize,
    /// Restrict text size to a specific value
    Clamp: usize
  },
  /// Position of the cursor in the string
  writePos: usize,
  showCursor: bool,

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
      .overflowMode = .None,
      .writePos = 0,
      .showCursor = true,
      .font = font,
      .hitbox = try .initFromText(origin, pos, height, font, ""),
    };
  }

  pub fn deinit(self: *Self, allocator: Allocator) void
  {
    self.hitbox.deinit();
    self.text.deinit(allocator);
  }

  /// Moves writePos to the end of inserted text
  pub fn insertString(
    self: *Self,
    allocator: Allocator,
    text: []const u8) Error!void
  {
    try self.text.insertSlice(allocator, self.writePos, text);
    self.writePos += text.len;

    try self.syncTexture();
  }

  /// Removes len characters from self.text and updates the texture
  /// If len > self.text.items.len, empties self.text
  /// Before treats the removal like backspace. Otherwise like delete
  pub fn removeString(self: *Self, count: usize, before: bool)
    SdlFail!void
  {
    if (before and count > self.writePos)
    {
      self.text.replaceRangeAssumeCapacity(
        0, self.writePos, &.{}
      );

      self.writePos = 0;
    } else if (!before and self.writePos + count > self.text.items.len)
    {
      self.text.replaceRangeAssumeCapacity(
        self.writePos, self.text.items.len - self.writePos, &.{}
      );
    } else
    {
      if (before)
      {
        self.writePos -= count;
      }

      self.text.replaceRangeAssumeCapacity(self.writePos, count, &.{});
    }

    try self.syncTexture();
  }

  /// renders self.text to self.hitbox.texture
  pub fn syncTexture(self: *Self) SdlFail!void
  {
    const hitboxConfig = self.hitbox;

    self.hitbox.deinit();

    if (
      self.overflowMode == .Scroll and
      self.text.items.len > self.overflowMode.Scroll)
    {
      self.hitbox = try .initFromText(
        hitboxConfig.origin,
        hitboxConfig.pos,
        hitboxConfig.height,
        self.font,
        self.text.items[self.text.items.len-self.overflowMode.Scroll..]
      );
    } else
    {
      self.hitbox = try .initFromText(
        hitboxConfig.origin,
        hitboxConfig.pos,
        hitboxConfig.height,
        self.font,
        self.text.items
      );
    }
  }

  pub fn render(self: Self) error{SDL_RenderFail}!void
  {
    try self.hitbox.render();

    if (self.showCursor)
    {
      const bounds = self.hitbox.pixelBounds();

      const chWidth =
        if (self.text.items.len > 0)
          bounds[1][0] / @as(f32, @floatFromInt(self.text.items.len))
        else
          0;

      const xPos =
        self.hitbox.pos[0] +
        (chWidth * @as(f32, @floatFromInt(self.writePos))) /
        mainspace.winSize()[0];

      if (!mainspace.renderer.SetRenderDrawColorFloat(1.0, 1.0, 1.0, 1.0))
      {
        return error.SDL_RenderFail;
      }
      if (!mainspace.renderer.RenderFillRect(&.{
        .x = xPos*mainspace.winSize()[0],
        .y = bounds[0][1],
        .w = 0.005*mainspace.winSize()[0],
        .h = self.hitbox.height*mainspace.winSize()[1],
      }))
      {
        return error.SDL_RenderFail;
      }
    }
  }
};
