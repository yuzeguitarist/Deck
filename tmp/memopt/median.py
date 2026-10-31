#!/usr/bin/env python3
"""Median the three suite runs into tmp/memopt/median.json."""

import json
import statistics
from pathlib import Path

root = Path("/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/runs")
runs = []
for index in (1, 2, 3):
    path = root / f"run-{index}.json"
    if not path.exists():
        raise SystemExit(f"missing {path}")
    runs.append(json.loads(path.read_text()))

names = [scenario["name"] for scenario in runs[0]["scenarios"]]
scenarios = []
for name in names:
    group = []
    for run in runs:
        match = next(item for item in run["scenarios"] if item["name"] == name)
        group.append(match)
    hashes = {item["canonical_sha256"] for item in group}
    latencies = [statistics.median(item["latency_ms"]) for item in group if item["latency_ms"]]
    scenarios.append({
        "name": name,
        "canonical_sha256": group[0]["canonical_sha256"],
        "canonical_stable": len(hashes) == 1,
        "result_count": group[0]["result_count"],
        "phys_after": statistics.median(item["phys_after"] for item in group),
        "phys_peak": statistics.median(item["phys_peak"] for item in group),
        "phys_before": statistics.median(item["phys_before"] for item in group),
        "rss_after": statistics.median(item["rss_after"] for item in group),
        "rss_peak": statistics.median(item["rss_peak"] for item in group),
        "malloc_in_use": statistics.median(item["malloc_in_use"] for item in group),
        "malloc_in_use_runs": [item["malloc_in_use"] for item in group],
        "rss_after_runs": [item["rss_after"] for item in group],
        "rss_peak_runs": [item["rss_peak"] for item in group],
        "sqlite_mem": statistics.median(item["sqlite_mem"] for item in group),
        "latency_ms_median": statistics.median(latencies) if latencies else None,
        "latency_ms_runs": latencies,
        "phys_after_runs": [item["phys_after"] for item in group],
        "phys_peak_runs": [item["phys_peak"] for item in group],
    })

persistence = {run["persistence_sha256"] for run in runs}
report = {
    "item_count": runs[0]["item_count"],
    "embedding_count": runs[0]["embedding_count"],
    "persistence_sha256": runs[0]["persistence_sha256"],
    "persistence_stable": len(persistence) == 1,
    "scenarios": scenarios,
}
destination = Path("/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/median.json")
destination.write_text(json.dumps(report, indent=2) + "\n")
print(destination)
for scenario in scenarios:
    phys = scenario["phys_after"] / (1024 * 1024)
    peak = scenario["phys_peak"] / (1024 * 1024)
    latency = scenario["latency_ms_median"]
    stable = "stable" if scenario["canonical_stable"] else "UNSTABLE"
    print(
        f"{scenario['name']}: phys_after={phys:.2f} MiB peak={peak:.2f} MiB "
        f"latency={latency:.1f} ms n={scenario['result_count']} {stable}"
    )
