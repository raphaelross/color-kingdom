import json
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

base = Path(__file__).resolve().parent
meta = json.loads((base / 'regions.json').read_text())
regions = meta['acceptedRegions']
w = meta['source']['width']
h = meta['source']['height']

region_map = np.array(Image.open(base / 'region_map.png').convert('RGBA'))
line = np.array(Image.open(Path('c:/Users/rross/color_kingdom/assets/coloring_pages/animals/lovely_kitten_raster_poc/line_art_foreground.png')).convert('RGBA'))

color_to_idx = {tuple(r['mapColorRgba']): i for i, r in enumerate(regions)}
label = np.full((h, w), -1, dtype=np.int32)
for y in range(h):
    for x in range(w):
        label[y, x] = color_to_idx.get(tuple(int(v) for v in region_map[y, x]), -1)

# Build coverage image
coverage = np.full((h, w, 3), 255, dtype=np.uint8)
children_inc = np.array([bool(r['profiles']['childrenDetailed']['included']) for r in regions], dtype=bool)
for i, r in enumerate(regions):
    m = label == i
    if children_inc[i]:
        coverage[m] = (70, 185, 95)
    else:
        coverage[m] = (235, 156, 62)

line_a = line[:, :, 3:4].astype(np.float32) / 255.0
line_rgb = line[:, :, :3].astype(np.float32)
comp = (line_rgb * line_a) + (coverage.astype(np.float32) * (1 - line_a))
coverage = np.clip(comp, 0, 255).astype(np.uint8)

# Rank suspicious exclusions
suspects = []
for i, r in enumerate(regions):
    if children_inc[i]:
        continue
    f = r['features']
    reasons = r['profiles']['childrenDetailed']['reasons']
    score = (f['areaPercent'] * 5.0) + (f['tapTargetRadiusPercent'] * 4.0) + (f['minBoundingDimensionPercent'] * 2.0)
    if len(reasons) == 1:
        score += 2.5
    if f['occupancyRatio'] > 0.2:
        score += 0.5
    suspects.append((score, r))

suspects.sort(key=lambda t: t[0], reverse=True)

img = Image.fromarray(coverage)
draw = ImageDraw.Draw(img)
for rank, (_, r) in enumerate(suspects[:20], start=1):
    b = r['bounds']
    x0, y0 = b['x'], b['y']
    x1, y1 = x0 + b['width'], y0 + b['height']
    draw.rectangle((x0, y0, x1, y1), outline=(190, 0, 0), width=2)
    draw.text((x0 + 2, y0 + 2), f"{rank}:{r['id']}", fill=(90, 0, 0))

img.save(base / 'master_vs_children_detailed_coverage_labeled.png')

print('top_suspects')
for rank, (score, r) in enumerate(suspects[:20], start=1):
    f = r['features']
    print(rank, r['id'], round(score, 3), r['profiles']['childrenDetailed']['reasons'], r['bounds'], r['centroid'], f['areaPixels'], round(f['areaPercent'], 3), round(f['tapTargetRadiusPercent'], 3), round(f['minBoundingDimensionPercent'], 3), round(f['occupancyRatio'], 3), round(f['compactness'], 3), round(f['aspectRatio'], 3))
