const mainspace = @import("main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

pub const Button = struct
{
  const Self = @This();
  // Center and height are relative to the window
  center: WinCoord,
  height: f32,
  texture: *sdl.SDL_Texture,

  pub fn init(
    center: WinCoord,
    height: f32,
    font: *sdl.TTF_Font,
    label: []const u8) Self
  {
    var result = Self{
      .center = center,
      .height = height,
      .texture = undefined,
    };

    const surface = sdl.TTF_RenderText_Blended(font, label.ptr, label.len, .{
      .r = 0xFF,
      .g = 0xFF,
      .b = 0xFF,
      .a = 0xFF
    });
    result.texture = sdl.SDL_CreateTextureFromSurface(
      mainspace.renderer, surface);
    sdl.SDL_DestroySurface(surface);

    return result;
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
    const trueCorners = [2]WinCoord{
      .{
        winSize[0] * (self.center[0] - self.height*ratio*0.5),
        winSize[1] * (self.center[1] - self.height*0.5)
      },
      .{
        winSize[0] * (self.center[0] + self.height*ratio*0.5),
        winSize[1] * (self.center[1] + self.height*0.5)
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

    if (!sdl.SDL_RenderTexture(mainspace.renderer, self.texture, null, &.{
      .x = (winSize[0]-trueHeight*ratio)*0.5,
      .y = winSize[1] * (self.center[1]-self.height*0.5),
      .w = trueHeight * ratio,
      .h = trueHeight 
    }))
    {
      return error.SDL_RenderFail;
    }
  }
};

