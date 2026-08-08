const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const menu = @import("../menu.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

var gpa: Allocator = undefined;

const fontQuality = 50; // The point size of the loaded font. Higher values increase quality but also increase vram usage
var menuFont: *sdl.TTF_Font = undefined;

var titleButton: menu.Button = undefined;

const guideText = [_][]const u8{
  "Welcome to the digital version of Mission Bitcoin, a board game by Lexington Fun Games Official (LFGO). Your mission: stack as many bitcoin as you can before anyone reaches the Moon. When that happens, the game ends, and whoever has the most coins wins.",
  "Before playing, choose your rocket ship color and the number of computer players. Each turn, the die is rolled and a pulsing circle of your rocket's color appears around at least two possible spaces for where your rocket can go. Choose carefully, as each dot does something different!",
  "In real life, Bitcoin’s total supply is capped at 21 million, so in Mission Bitcoin there are exactly 21 bitcoin tokens. Landing on a bitcoin adds it to your Exchange Wallet, but it is not truly yours until you land on a Blue space to move it to Cold Storage.",
  "But watch out for the Red spaces! These cause the exchange to get hacked, and every player’s Exchange Wallet coins are moved to their corresponding location on the Moon. The first player to reach the Moon collects their lost coins and adds them back to their stash.",
  "Mission Bitcoin mimics Bitcoin’s halving cycles with three orbits around the Moon. The largest ring starts with 12 bitcoin. Once claimed, the path to the next epoch opens, which has 6 bitcoin in it. After those are taken, the way is revealed to the final epoch and its 3 bitcoin.",
  "When a bitcoin token is claimed, its space becomes either a Blue space or a White Ring space, which lets you take another turn immediately. Either space can only be used after the bitcoin token has been claimed.",
  "Sometimes you will land on an Orange Pill space. Like in the film The Matrix, the \"orange pill\" convinces someone of Bitcoin's importance, and you send one coin to them as a gift. A pulsing circle will appear around each of the other players’ rockets in the upper right, and the one you select will receive a bitcoin from your Exchange Wallet (if you have any there) or your Cold Storage, and into their Cold Storage.",
  "And beware the 6102 space! Executive Order 6102 was signed by FDR in 1933, confiscating everyone's gold and criminalizing gold ownership. Bitcoin in Cold Storage isn't so easy to confiscate, so in the game, if someone lands on that space, ALL bitcoin in Exchange Wallets and on the Moon are stolen by the government and permanently removed from the game.",
  "So what are you waiting for? Start stacking and take your bitcoin to the Moon!"
};

const guideHeight = 0.04;
var scrollOffset: f32 = 0.0;
var guideButtons: std.ArrayList(menu.Button) = .empty;

var backButton: menu.Button = undefined;

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

    titleButton = try .initFromText(
      .{0.5, 0.5}, .{0.5, 0.08}, 0.1, menuFont, "how to play"
    );

    try generateGuideButtons();

    backButton = try .initFromText(
      .{0.5, 0.5},
      .{0.5, guideButtons.getLast().pos[1]+0.1},
      0.1,
      menuFont,
      "back"
    );

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

    sw:switch (event.type)
    {
      sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
        if (event.button.button != sdl.SDL_BUTTON_LEFT)
        {
          break:sw;
        }

        backButton.pos[1] += scrollOffset;
        if (backButton.contains(.{event.button.x, event.button.y}))
        {
          Scene.currentScene = Scene.scenes.getPtrConst(.StartMenu);
        }
        backButton.pos[1] -= scrollOffset;
      },
      sdl.SDL_EVENT_WINDOW_RESIZED => {
        if (Scene.currentScene == Scene.scenes.getPtrConst(.Guide))
        {
          try generateGuideButtons();
        }
      },
      sdl.SDL_EVENT_MOUSE_WHEEL => {
        scrollOffset = std.math.clamp(
          scrollOffset + event.wheel.y*0.05, -backButton.pos[1]+0.9, 0
        );
      },
      sdl.SDL_EVENT_MOUSE_MOTION => {
        if (sdl.SDL_GetMouseState(null, null) & sdl.SDL_BUTTON_LMASK > 0)
        {
          const winSize = mainspace.winSize();
          scrollOffset = std.math.clamp(
            scrollOffset + event.motion.yrel/winSize[1], -backButton.pos[1]+0.9, 0
          );
        }
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
    titleButton.pos[1] += scrollOffset;
    try titleButton.render();
    titleButton.pos[1] -= scrollOffset;

    for (guideButtons.items) |*button|
    {
      button.pos[1] += scrollOffset;
      try button.render();
      button.pos[1] -= scrollOffset;
    }

    backButton.pos[1] += scrollOffset;
    try backButton.render();
    backButton.pos[1] -= scrollOffset;
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    backButton.deinit();

    for (guideButtons.items) |*button|
    {
      button.deinit();
    }
    guideButtons.deinit(gpa);

    sdl.TTF_CloseFont(menuFont);
  }}.deinit,
};

fn generateGuideButtons() !void
{
  guideButtons.clearRetainingCapacity();

  const winSize = mainspace.winSize();
  var yPos: f32 = 0.16;
  for (guideText) |text|
  {
    var line: []const u8 = text[0..0];
    while (@intFromPtr(line.ptr)+line.len < @intFromPtr(text.ptr)+text.len):
      (line.len += 1)
    {
      if (line.len == 0 or line[line.len-1] != ' ')
      {
        continue;
      }

      const lineSize: WinCoord = blk:{
        var size: @Vector(2, c_int) = undefined;
        if (!sdl.TTF_GetStringSize(
          menuFont, line.ptr, line.len, &size[0], &size[1]))
        {
          return error.SDL_RenderFail;
        }

        break:blk .{@floatFromInt(size[0]), @floatFromInt(size[1])};
      };
      const ratio = lineSize[0] / lineSize[1];
      const trueWidth = winSize[1]*guideHeight*ratio;
      
      if (trueWidth > winSize[0]*0.9)
      {
        line.len =
          std.mem.lastIndexOf(u8, line[0..line.len-1], " ") orelse line.len;

        try guideButtons.append(gpa, try .initFromText(
          .{0.0, 0.5},
          .{0.05, yPos},
          guideHeight,
          menuFont,
          line
        ));

        // Increment by an extra one to avoid leading space
        line.ptr += line.len+1;
        line.len = 0;
        yPos += guideHeight;
      }
    }

    try guideButtons.append(gpa, try .initFromText(
      .{0.0, 0.5},
      .{0.05, yPos},
      guideHeight,
      menuFont,
      line
    ));

    yPos += guideHeight*2;
  }

  backButton.pos[1] = guideButtons.getLast().pos[1]+0.1;
}
