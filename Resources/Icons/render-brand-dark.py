#!/usr/bin/env python3

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Resources/Icons/Source/Brand.png"
OUTPUT = ROOT / "Resources/Icons/Source/dark/Brand.png"
FRONT = (0xF2, 0xF2, 0xF7)
BACK = (0x8E, 0x8E, 0x93)

image = Image.open(SOURCE).convert("RGBA")
width, height = image.size
pixels = image.load()
labels = [[None] * width for _ in range(height)]
queue = deque()

for y in range(height):
    for x in range(width):
        red, green, blue, alpha = pixels[x, y]
        if alpha == 255:
            labels[y][x] = 0 if (red + green + blue) / 3.0 < 96.0 else 1
            queue.append((x, y))

while queue:
    x, y = queue.popleft()
    for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
        if 0 <= next_x < width and 0 <= next_y < height and labels[next_y][next_x] is None:
            if pixels[next_x, next_y][3] > 0:
                labels[next_y][next_x] = labels[y][x]
                queue.append((next_x, next_y))

for y in range(height):
    for x in range(width):
        _, _, _, alpha = pixels[x, y]
        if alpha == 0:
            pixels[x, y] = (0, 0, 0, 0)
        else:
            color = FRONT if labels[y][x] == 0 else BACK
            pixels[x, y] = (*color, alpha)

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUTPUT)
