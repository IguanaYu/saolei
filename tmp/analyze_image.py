#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用智谱 GLM-4.6V-Flash（免费视觉模型）分析图片。

用法：
  python tmp/analyze_image.py <图片路径> [问题]
  python tmp/analyze_image.py tmp/asset_robots.png "逐一描述每个机器人的颜色和胸前符号"

环境变量：
  VISION_MODEL  视觉模型名，默认 glm-4.6v-flash

API key 复用 .env 里的 ZHIPUAI_API_KEY。无第三方依赖。
"""
import os
import sys
import json
import base64
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
    if len(sys.argv) < 2:
        print("用法: python tmp/analyze_image.py <图片路径> [问题]")
        sys.exit(1)

    img_path = sys.argv[1]
    question = sys.argv[2] if len(sys.argv) > 2 else (
        "详细描述这张图的内容、风格、配色和主要元素。"
    )

    if not os.path.exists(img_path):
        img_path = os.path.join(PROJECT_ROOT, img_path)
    if not os.path.exists(img_path):
        print(f"ERROR: 图片不存在: {img_path}")
        sys.exit(1)

    api_key = load_key()
    if not api_key:
        print("ERROR: 未找到 ZHIPUAI_API_KEY")
        sys.exit(1)

    with open(img_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    ext = os.path.splitext(img_path)[1].lower().lstrip(".")
    mime = "jpeg" if ext in ("jpg", "jpeg") else "png"
    data_url = f"data:image/{mime};base64,{b64}"

    endpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": os.environ.get("VISION_MODEL", "glm-4.6v-flash"),
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": question},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
    }

    print(f"分析图片: {os.path.basename(img_path)}")
    print(f"模型: {payload['model']}")
    print(f"问题: {question}")
    print("---")
    import time
    max_retries = 4
    result = None
    for attempt in range(1, max_retries + 1):
        req = urllib.request.Request(
            endpoint,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code == 429 and attempt < max_retries:
                wait = 10 * attempt
                print(f"HTTP 429 限流，{wait}s 后重试（第 {attempt}/{max_retries - 1} 次）...")
                time.sleep(wait)
                continue
            print(f"HTTP {e.code}: {body}")
            sys.exit(2)
        except urllib.error.URLError as e:
            print(f"网络错误: {e}")
            sys.exit(3)
    if result is None:
        print("ERROR: 重试耗尽")
        sys.exit(2)

    try:
        content = result["choices"][0]["message"]["content"]
        print(content)
    except (KeyError, IndexError):
        print("返回:", json.dumps(result, ensure_ascii=False)[:800])


if __name__ == "__main__":
    main()
