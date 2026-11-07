from pathlib import Path
from PIL import Image, ImageFilter, ImageChops

# Reproducible edit of the existing EBO launcher icon. No generated-art
# binary, secret or external network asset is needed in the repository.
source = Path('assets/icon/ebo_launcher.png')
output = Path('assets/icon/ebo_launcher_v2.png')
if not source.exists():
    raise SystemExit('Original EBO launcher icon missing')
icon = Image.open(source).convert('RGB')
size = icon.width
if size != icon.height:
    raise SystemExit('Launcher icon must be square')

# Reconstruct the dark-blue / teal background, deleting all Wi-Fi arcs.
base = Image.new('RGB', (size, size))
pixels = base.load()
for y in range(size):
    v = y / (size - 1)
    for x in range(size):
        u = x / (size - 1)
        tl, tr, bl, br = (1, 13, 43), (0, 75, 105), (1, 31, 83), (0, 196, 181)
        pixels[x, y] = tuple(round(
            (1-v)*((1-u)*tl[k] + u*tr[k]) +
            v*((1-u)*bl[k] + u*br[k])) for k in range(3))

alpha = Image.new('L', (size, size))
mask = alpha.load()
original = icon.load()
for y in range(size):
    for x in range(size):
        r,g,b = original[x,y]
        if y < size * (52/192):
            continue
        bright = max(0, min(255, round((min(g,b)-110)*2))) \
            if r < 120 and g-r > 110 and b-r > 100 else 0
        if ((x-size*.5)**2 + (y-size*.49)**2) < (size*.092)**2:
            bright = 255
        mask[x,y] = bright
glow = alpha.filter(ImageFilter.GaussianBlur(radius=max(1,size*.013)))
glow = glow.point(lambda value: round(value*.24))
alpha = ImageChops.lighter(alpha, glow)
subject = icon.convert('RGBA')
subject.putalpha(alpha)

# Scale exactly 1.5x and re-center; app icon adaptive mask clips corners.
scale = 1.5
magnified = subject.resize((round(size*scale), round(size*scale)),
                           Image.Resampling.LANCZOS)
x0 = round(size*.5*scale-size*.5)
y0 = round(size*.59*scale-size*.5)
magnified = magnified.crop((x0, y0, x0+size, y0+size))
base.paste(magnified, (0,0), magnified)
output.parent.mkdir(parents=True,exist_ok=True)
base.resize((1024,1024),Image.Resampling.LANCZOS).save(output,optimize=True)
print('Created 1024x1024 EBO launcher: radio waves removed, content 1.5x')
