#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

MODE = sys.argv[1] if len(sys.argv) > 1 else ""
if MODE not in {"restore", "save"}:
    raise SystemExit("usage: persist-userdata-macos.py restore|save")

home = Path.home()
mount = home / "Desktop" / "AList共享"
backup = mount / "yan" / "workflow-userdata" / "macos"

profiles = {
    "chrome": "Library/Application Support/Google/Chrome",
    "edge": "Library/Application Support/Microsoft Edge",
    "firefox": "Library/Application Support/Firefox",
    "safari": "Library/Safari",
    "safari-container": "Library/Containers/com.apple.Safari/Data/Library/Safari",
    "bilibili": "Library/Application Support/bilibili",
    "bilibili-cn": "Library/Application Support/哔哩哔哩",
    "bilibili-container": "Library/Containers/tv.danmaku.bili/Data/Library/Application Support",
    "qq": "Library/Application Support/QQ",
    "qq-container": "Library/Containers/com.tencent.qq/Data/Library/Application Support/QQ",
    "qq-documents": "Library/Containers/com.tencent.qq/Data/Documents",
    "wechat": "Library/Application Support/com.tencent.xinWeChat",
    "wechat-container": "Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat",
    "wechat-documents": "Library/Containers/com.tencent.xinWeChat/Data/Documents",
}

if not mount.exists():
    print("AList mount is unavailable; profile persistence was skipped.", flush=True)
    raise SystemExit(0)
if MODE == "restore" and not backup.exists():
    print("No saved macOS profiles were found yet.", flush=True)
    raise SystemExit(0)
if MODE == "save":
    backup.mkdir(parents=True, exist_ok=True)
    for app in ("Google Chrome", "Microsoft Edge", "Firefox", "Safari", "QQ", "WeChat", "哔哩哔哩"):
        subprocess.run(["osascript", "-e", f'tell application "{app}" to quit'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

cache_args = [
    "--exclude=Cache/",
    "--exclude=Code Cache/",
    "--exclude=GPUCache/",
    "--exclude=ShaderCache/",
    "--exclude=GrShaderCache/",
    "--exclude=DawnCache/",
    "--exclude=Crashpad/",
]
count = 0
for name, relative in profiles.items():
    local = home / relative
    remote = backup / name
    if MODE == "restore":
        if not remote.exists():
            continue
        source, destination = remote, local
    else:
        if not local.exists():
            continue
        source, destination = local, remote
        destination.mkdir(parents=True, exist_ok=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["rsync", "-aE", *cache_args, str(source) + "/", str(destination) + "/"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode not in (0, 24):
        print(f"Profile copy failed for {name}: rsync exit {result.returncode}", flush=True)
    else:
        count += 1

print(f"{MODE.capitalize()} complete. Profile groups copied: {count}", flush=True)
