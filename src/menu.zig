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
        mainspace.renderer, try directoryManager.getPath(path)
      ),
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

