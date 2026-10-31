#!/usr/bin/env python3
"""Compare tmp/memopt/median.json with the retained baseline.

Exit 0 when the round should be kept, 1 otherwise.
Prints a Chinese explanation.
"""

import json
import sys
from pathlib import Path

root = Path("/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt")
baseline = json.loads((root / "baseline-median.json").read_text())
current = json.loads((root / "median.json").read_text())

MIB = 1024 * 1024


def mib(value):
    return value / MIB


def index(report):
    return {item["name"]: item for item in report["scenarios"]}


base = index(baseline)
now = index(current)
problems = []
wins = []

if not current.get("persistence_stable", False):
    problems.append("三次运行的持久化哈希不一致")
if current.get("persistence_sha256") != baseline.get("persistence_sha256"):
    problems.append(
        f"持久化哈希变化 {baseline.get('persistence_sha256')} -> {current.get('persistence_sha256')}"
    )

for name, old in base.items():
    new = now.get(name)
    if new is None:
        problems.append(f"缺少场景 {name}")
        continue
    if not new.get("canonical_stable", False):
        problems.append(f"{name} 三次正确性哈希不一致")
    if new.get("canonical_sha256") != old.get("canonical_sha256"):
        problems.append(f"{name} 正确性哈希变化")
    if new.get("result_count") != old.get("result_count"):
        problems.append(
            f"{name} 结果条数 {old.get('result_count')} -> {new.get('result_count')}"
        )

    old_lat = old["latency_ms_median"]
    new_lat = new["latency_ms_median"]
    lat_spread = max(old["latency_ms_runs"]) - min(old["latency_ms_runs"])
    if old_lat > 0:
        lat_ratio = (new_lat - old_lat) / old_lat
        if lat_ratio > 0.03 and (new_lat - old_lat) > lat_spread:
            problems.append(
                f"{name} 延迟 {old_lat:.2f} ms -> {new_lat:.2f} ms（{lat_ratio * 100:+.1f}%，极差 {lat_spread:.2f} ms）"
            )

    for metric, label in (("phys_after", "物理足迹"), ("phys_peak", "峰值物理足迹")):
        old_value = old[metric]
        new_value = new[metric]
        spread = max(old[f"{metric}_runs"]) - min(old[f"{metric}_runs"])
        delta = old_value - new_value
        ratio = delta / old_value if old_value else 0
        if new_value > old_value + spread:
            problems.append(
                f"{name} {label} 上升 {mib(old_value):.2f} -> {mib(new_value):.2f} MiB（超过极差 {mib(spread):.2f} MiB）"
            )
        runs = new[f"{metric}_runs"]
        beyond_noise = delta > spread and ratio >= 0.01
        consistent = all(run <= old_value for run in runs)
        if beyond_noise and consistent:
            wins.append(
                f"{name} {label} {mib(old_value):.2f} -> {mib(new_value):.2f} MiB（-{mib(delta):.2f} MiB，-{ratio * 100:.1f}%）"
            )

if problems:
    print("回滚")
    for line in problems:
        print("- " + line)
    if wins:
        print("同时看到的改善（仍回滚）：")
        for line in wins:
            print("- " + line)
    sys.exit(1)

if not wins:
    print("回滚")
    print("- 正确性和延迟通过，但没有任何场景的物理足迹下降超过噪声")
    sys.exit(1)

print("保留")
for line in wins:
    print("- " + line)
sys.exit(0)
