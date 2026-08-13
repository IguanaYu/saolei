#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI 像素画后处理：把 CogView 出的"假像素画"(100+色)压成真像素画(16-32色)。
社区标准流程：降色(median-cut quantize) + NEAREST 缩放。
用法：python tmp/postprocess.py <输入> <输出> [颜色数, 默认16]
依赖：Pillow
"""
import sys
from PIL import Image


def to_pixelart(src: str, out: str, colors: int = 16) -> str:
    img = Image.open(src).convert("RGB")
    q = img.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
    q.save(out)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python tmp/postprocess.py <输入> <输出> [颜色数]")
        sys.exit(1)
    colors = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    out = to_pixelart(sys.argv[1], sys.argv[2], colors)
    print("saved", out, "colors=", colors)
