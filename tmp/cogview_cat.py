#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用智谱 CogView (cogview-3-flash, 免费) 生成图像。

API key 读取顺序：
  1) 环境变量 ZHIPUAI_API_KEY（也兼容 ZHIPU_API_KEY）
  2) 项目根 .env 文件中的一行： ZHIPUAI_API_KEY=你的key

用法：
  python tmp/cogview_cat.py
  COGVIEW_MODEL=cogview-x-flash python tmp/cogview_cat.py             # 换模型
  COGVIEW_SIZE=1440x720    python tmp/cogview_cat.py                   # 换尺寸
  COGVIEW_PROMPT="..." COGVIEW_OUT=tmp/x.png python tmp/cogview_cat.py # 自定义 prompt/输出

无第三方依赖，仅使用 Python 标准库。
"""
import os
import sys
import json
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HERE)


def load_key():
    key = os.environ.get("ZHIPUAI_API_KEY") or os.environ.get("ZHIPU_API_KEY")
    if key:
        return key
    env_path = os.path.join(PROJECT_ROOT, ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("ZHIPUAI_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def main():
    model = os.environ.get("COGVIEW_MODEL", "cogview-3-flash")
    size = os.environ.get("COGVIEW_SIZE", "1024x1024")
    out_path = os.environ.get("COGVIEW_OUT") or os.path.join(HERE, "cogview_cat.png")

    default_prompt = (
        "Pixel art illustration of a cute cat, sitting upright facing forward, "
        "big expressive eyes, small pink nose, whiskers, pointy ears, "
        "tabby orange fur with stripes, 16-bit retro video game sprite aesthetic, "
        "limited color palette (about 12 colors), crisp clean pixels, "
        "centered composition, simple flat pastel background, cheerful mood"
    )
    prompt = os.environ.get("COGVIEW_PROMPT") or default_prompt

    api_key = load_key()
    if not api_key:
        print("ERROR: 未找到 ZHIPUAI_API_KEY。")
        print("请任选一种方式提供：")
        print("  1) 设置环境变量 ZHIPUAI_API_KEY")
        print("  2) 在项目根创建 .env 文件，写入一行： ZHIPUAI_API_KEY=你的key")
        sys.exit(1)

    endpoint = "https://open.bigmodel.cn/api/paas/v4/images/generations"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {"model": model, "prompt": prompt, "size": size}

    print(f"调用 CogView: model={model}, size={size}")
    print(f"prompt: {prompt[:120]}{'...' if len(prompt) > 120 else ''}")
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}: {body}")
        sys.exit(2)
    except urllib.error.URLError as e:
        print(f"网络错误: {e}")
        sys.exit(3)

    print("返回:", json.dumps(result, ensure_ascii=False)[:500])

    try:
        img_url = result["data"][0]["url"]
    except (KeyError, IndexError):
        print("ERROR: 返回里没有图片 URL，请检查上面的返回内容。")
        sys.exit(4)

    print(f"下载图片: {img_url}")
    urllib.request.urlretrieve(img_url, out_path)
    print(f"已保存: {out_path}")


if __name__ == "__main__":
    main()
