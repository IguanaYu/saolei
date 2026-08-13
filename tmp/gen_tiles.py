#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
程序化生成 seamless（可无缝平铺）的像素 tile 纹理。

原理：value noise 在环面（torus）上采样，即网格坐标用 modulo 包裹，
所以左右边缘、上下边缘的像素天然连续 → 拼接无接缝。

配色匹配 warm pixel 矿洞风（暖棕底）。
依赖：Pillow (PIL)
"""
import os
import random
from PIL import Image


def smooth(t):
    """hermite 平滑，让噪声过渡自然"""
    return t * t * (3 - 2 * t)


def value_noise(size, grid, seed):
    """环面上的 value noise，天然 seamless。返回 size×size 的 0~1 二维数组。"""
    rng = random.Random(seed)
    vals = [[rng.random() for _ in range(grid)] for _ in range(grid)]
    cell = size / grid
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            gx, gy = x / cell, y / cell
            x0, y0 = int(gx) % grid, int(gy) % grid
            x1, y1 = (x0 + 1) % grid, (y0 + 1) % grid
            fx, fy = smooth(gx - int(gx)), smooth(gy - int(gy))
            top = vals[y0][x0] * (1 - fx) + vals[y0][x1] * fx
            bot = vals[y1][x0] * (1 - fx) + vals[y1][x1] * fx
            out[y][x] = top * (1 - fy) + bot * fy
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def colorize(noise, lo, hi):
    size = len(noise)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = noise[y][x]
            px[x, y] = (
                int(lerp(lo[0], hi[0], v)),
                int(lerp(lo[1], hi[1], v)),
                int(lerp(lo[2], hi[2], v)),
            )
    return img


def add_specks(img, count, color, seed):
    """随机散点细节（裂纹/石子），坐标在尺寸内随机即天然 wraparound 友好。"""
    rng = random.Random(seed)
    size = img.size[0]
    px = img.load()
    for _ in range(count):
        px[rng.randint(0, size - 1), rng.randint(0, size - 1)] = color
    return img


def make_tile(out_path, lo, hi, grid, seed, speck_color, speck_count, native=64, display=256):
    n = value_noise(native, grid, seed)
    img = colorize(n, lo, hi)
    img = add_specks(img, speck_count, speck_color, seed + 1)
    img = img.resize((display, display), Image.NEAREST)  # NEAREST 保留像素硬边
    img.save(out_path)
    print("saved", out_path)


if __name__ == "__main__":
    out_dir = os.path.dirname(os.path.abspath(__file__))
    # 岩石（未开格子）：暖灰
    make_tile(
        os.path.join(out_dir, "tile_rock_procedural.png"),
        lo=(58, 52, 48), hi=(122, 112, 102),
        grid=8, seed=42, speck_color=(40, 36, 32), speck_count=140,
    )
    # 地砖（已开格子）：暖棕泥土
    make_tile(
        os.path.join(out_dir, "tile_floor_procedural.png"),
        lo=(90, 62, 36), hi=(172, 130, 78),
        grid=8, seed=7, speck_color=(60, 42, 24), speck_count=110,
    )
