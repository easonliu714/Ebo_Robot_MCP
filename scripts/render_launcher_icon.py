from pathlib import Path
from PIL import Image, ImageDraw, ImageChops

# Approved 3D icon / widget art is committed as WebP to keep Git history small.
# Expand to PNG for flutter_launcher_icons and Android widget drawables in CI.
root = Path('assets/branding')
launcher = Image.open(root / 'ebo_launcher_v3.webp').convert('RGBA')
# Clip stray neon pixels outside the approved rounded-square tile. Keep the
# cyan/blue gradient and all robot/controller artwork *inside* the tile.
w, h = launcher.size
ss = 4
tile_mask = Image.new('L', (w * ss, h * ss), 0)
draw = ImageDraw.Draw(tile_mask)
draw.rounded_rectangle((int(w*.018)*ss, int(h*.018)*ss,
                        int(w*.982)*ss, int(h*.982)*ss),
                       radius=int(min(w, h)*.205)*ss, fill=255)
tile_mask = tile_mask.resize((w, h), Image.Resampling.LANCZOS)
launcher.putalpha(ImageChops.multiply(launcher.getchannel('A'), tile_mask))
out = Path('assets/icon/ebo_launcher_v3.png')
out.parent.mkdir(parents=True, exist_ok=True)
launcher.resize((1024, 1024), Image.Resampling.LANCZOS).save(out, optimize=True)
if launcher.getpixel((0, 0))[3] != 0:
    raise SystemExit('Launcher outer corners must be transparent')

names = ('widget_qa', 'widget_mcp', 'widget_dock', 'widget_patrol',
         'widget_pet', 'widget_photo', 'preview_qa', 'preview_mcp',
         'preview_dual', 'preview_quick')
res = Path('android/app/src/main/res/drawable-nodpi')
res.mkdir(parents=True, exist_ok=True)
for name in names:
    source = root / (name + '.webp')
    im = Image.open(source).convert('RGBA')
    im.save(res / ('ebo_' + name + '.png'), optimize=True)
print('Installed approved transparent 3D launcher and', len(names),
      'widget artwork/preview resources.')