from __future__ import annotations

import csv
import html
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SAMPLE_FIELDS = [
    "repeat", "mode", "phase", "load", "sample", "cpu_ticks",
    "cpu_cycles", "level_before", "level_after", "dma_command",
]
PHASE_FIELDS = ["mode", "phase", "load", "min", "mean", "p95", "max", "violations"]
PHASE_DMA_FIELDS = [
    "mode", "phase", "load", "commands", "dma_MiB_per_s", "dma_cycles",
    "r_wait", "w_wait", "r_windows", "w_windows",
]
SUMMARY_FIELDS = [
    "mode", "min", "mean", "p95", "p99", "max", "violations",
    "dma_commands", "dma_MiB_per_s", "dma_cycles", "r_wait", "w_wait",
    "r_windows", "w_windows", "transitions",
]
PHASE_ORDER = ["OFF_A", "ON_A", "OFF_B", "ON_B"]
MODE_ORDER = [
    "CPU_ONLY", "FIXED_MAX", "STATIC_B8", "RBR_50", "RBR_67",
    "RBR_80", "BURST_ADAPT", "RBR_ADAPT",
]


def number(value: str) -> int | float:
    return float(value) if "." in value else int(value, 0)


def tagged_rows(lines: list[str], tag: str, fields: list[str]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line in lines:
        if not line.startswith(tag + ","):
            continue
        values = next(csv.reader([line]))[1:]
        row: dict[str, object] = {}
        for key, value in zip(fields, values):
            row[key] = value if key in {"mode", "phase"} else number(value)
        rows.append(row)
    return rows


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[math.ceil(percentile * len(ordered)) - 1]


def stats(values: list[float], high: float) -> dict[str, float | int]:
    return {
        "samples": len(values),
        "min_calc": min(values),
        "mean_calc": statistics.fmean(values),
        "p95_calc": nearest_rank(values, 0.95),
        "p99_calc": nearest_rank(values, 0.99),
        "max_calc": max(values),
        "violations_calc": sum(value > high for value in values),
    }


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def text(x: float, y: float, value: str, **attrs: object) -> str:
    attributes = " ".join(
        f'{key.replace("_", "-")}="{item}"' for key, item in attrs.items()
    )
    return f'<text x="{x:.1f}" y="{y:.1f}" {attributes}>{html.escape(value)}</text>'


def trace_svg(samples: list[dict[str, object]], low: float, high: float,
              mode: str, filename: str) -> None:
    rows = [row for row in samples if row["mode"] == mode]
    width, height = 1380, 720
    left, right, top, bottom = 90, 45, 65, 100
    level_height = 125
    gap = 42
    latency_height = height - top - bottom - level_height - gap
    plot_width = width - left - right
    latency_min, latency_max = 85.0, 180.0

    def sx(index: float) -> float:
        return left + index / (len(rows) - 1) * plot_width

    def sy(value: float) -> float:
        return top + (latency_max - value) / (latency_max - latency_min) * latency_height

    level_top = top + latency_height + gap

    def ly(value: float) -> float:
        return level_top + (3.0 - value) / 3.0 * level_height

    colors = {"OFF_A": "#EFF6FF", "ON_A": "#FEF2F2", "OFF_B": "#EFF6FF", "ON_B": "#FEF2F2"}
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#FFFFFF"/>',
        text(width / 2, 34, f"{mode} latency and level trace", text_anchor="middle", font_family="Arial", font_size=22, font_weight="bold", fill="#111827"),
    ]

    for repeat in range(3):
        for phase_index, phase in enumerate(PHASE_ORDER):
            start = repeat * 100 + phase_index * 25
            end = start + 24
            x1 = sx(start)
            x2 = sx(end + 1 if end < 299 else end)
            parts.append(f'<rect x="{x1:.1f}" y="{top}" width="{max(x2 - x1, 1):.1f}" height="{latency_height + gap + level_height}" fill="{colors[phase]}"/>')
            label = "CPU1 OFF" if phase.startswith("OFF") else "CPU1 ON"
            parts.append(text((x1 + x2) / 2, top + 17, label, text_anchor="middle", font_family="Arial", font_size=10, fill="#6B7280"))

    for value in range(100, 181, 20):
        y = sy(float(value))
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#D1D5DB"/>')
        parts.append(text(left - 12, y + 4, str(value), text_anchor="end", font_family="Arial", font_size=12, fill="#374151"))

    for value, label, color in [(low, "low", "#059669"), (high, "high", "#DC2626")]:
        y = sy(value)
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="{color}" stroke-width="2" stroke-dasharray="7 5"/>')
        parts.append(text(left + plot_width - 5, y - 6, f"{label} {value:.2f}", text_anchor="end", font_family="Arial", font_size=11, fill=color))

    points = " ".join(f'{sx(i):.1f},{sy(float(row["cpu_cycles"])):.1f}' for i, row in enumerate(rows))
    parts.append(f'<polyline points="{points}" fill="none" stroke="#2563EB" stroke-width="1.6"/>')

    for i, row in enumerate(rows):
        if int(row["level_before"]) != int(row["level_after"]):
            parts.append(f'<circle cx="{sx(i):.1f}" cy="{sy(float(row["cpu_cycles"])):.1f}" r="4.2" fill="#F59E0B" stroke="#92400E"/>')

    for value in range(4):
        y = ly(float(value))
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#D1D5DB"/>')
        parts.append(text(left - 12, y + 4, f"L{value}", text_anchor="end", font_family="Arial", font_size=12, fill="#374151"))
    level_points = " ".join(f'{sx(i):.1f},{ly(float(row["level_after"])):.1f}' for i, row in enumerate(rows))
    parts.append(f'<polyline points="{level_points}" fill="none" stroke="#7C3AED" stroke-width="2.3"/>')

    for repeat in range(4):
        index = min(repeat * 100, 299)
        x = sx(index)
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{level_top + level_height}" stroke="#6B7280" stroke-width="1.4"/>')

    parts.append(text(left + plot_width / 2, height - 26, f"{mode} sample index (3 repeats × OFF/ON/OFF/ON)", text_anchor="middle", font_family="Arial", font_size=14, fill="#111827"))
    parts.append(f'<text x="25" y="{top + latency_height / 2:.1f}" transform="rotate(-90 25 {top + latency_height / 2:.1f})" text-anchor="middle" font-family="Arial" font-size="14" fill="#111827">CPU cycles/access</text>')
    parts.append("</svg>")
    (ROOT / filename).write_text("\n".join(parts), encoding="utf-8")


def tradeoff_svg(summary: list[dict[str, object]]) -> None:
    rows = [row for row in summary if row["mode"] != "CPU_ONLY"]
    width, height = 980, 650
    left, right, top, bottom = 95, 55, 65, 85
    plot_width = width - left - right
    plot_height = height - top - bottom
    x_max, y_min, y_max = 105.0, 300.0, 720.0

    def sx(value: float) -> float:
        return left + value / x_max * plot_width

    def sy(value: float) -> float:
        return top + (y_max - value) / (y_max - y_min) * plot_height

    colors = {
        "FIXED_MAX": "#DC2626",
        "STATIC_B8": "#F59E0B",
        "FIXED_RBR": "#7C3AED",
        "FIXED_L1": "#0284C7",
        "FIXED_L2": "#0891B2",
        "RBR_50": "#0284C7",
        "RBR_67": "#0891B2",
        "RBR_80": "#7C3AED",
        "BURST_ADAPT": "#F97316",
        "RBR_ADAPT": "#059669",
    }
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#FFFFFF"/>',
        text(width / 2, 34, "DMA throughput versus latency-limit violations", text_anchor="middle", font_family="Arial", font_size=21, font_weight="bold", fill="#111827"),
    ]
    for value in range(0, 101, 20):
        x = sx(float(value))
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{top + plot_height}" stroke="#E5E7EB"/>')
        parts.append(text(x, top + plot_height + 25, str(value), text_anchor="middle", font_family="Arial", font_size=12, fill="#374151"))
    for value in range(300, 721, 60):
        y = sy(float(value))
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#E5E7EB"/>')
        parts.append(text(left - 12, y + 4, str(value), text_anchor="end", font_family="Arial", font_size=12, fill="#374151"))
    for row in rows:
        x = sx(float(row["violation_rate_percent"]))
        y = sy(float(row["dma_MiB_per_s"]))
        mode = str(row["mode"])
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="{colors[mode]}" stroke="#FFFFFF" stroke-width="2"/>')
        anchor = "end" if x > width * 0.75 else "start"
        offset = -12 if anchor == "end" else 12
        parts.append(text(x + offset, y - 12, mode, text_anchor=anchor, font_family="Arial", font_size=12, font_weight="bold", fill="#111827"))
    parts.append(text(left + plot_width / 2, height - 24, "Samples above high limit (%) — lower is better", text_anchor="middle", font_family="Arial", font_size=14, fill="#111827"))
    parts.append(f'<text x="25" y="{top + plot_height / 2:.1f}" transform="rotate(-90 25 {top + plot_height / 2:.1f})" text-anchor="middle" font-family="Arial" font-size="14" fill="#111827">DMA throughput (MiB/s)</text>')
    parts.append("</svg>")
    (ROOT / "tradeoff.svg").write_text("\n".join(parts), encoding="utf-8")


def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "raw.log"
    source_lines = source.read_text(encoding="utf-8").splitlines()
    start = source_lines.index("Final Adaptive DMA benchmark")
    lines = source_lines[start:]
    while lines and not lines[-1]:
        lines.pop()
    samples = tagged_rows(lines, "SAMPLE", SAMPLE_FIELDS)
    phase_reported = tagged_rows(lines, "PHASE_SUMMARY", PHASE_FIELDS)
    phase_dma = tagged_rows(lines, "PHASE_DMA", PHASE_DMA_FIELDS)
    summary_reported = tagged_rows(lines, "SUMMARY", SUMMARY_FIELDS)
    config_line = next(line for line in lines if line.startswith("CONFIG,"))
    config = {
        key: int(value)
        for key, value in
        (item.split("=") for item in config_line.split(",")[1:])
    }
    limits_line = next(line for line in lines if line.startswith("LIMITS,"))
    limits = {key: float(value) for key, value in (item.split("=") for item in limits_line.split(",")[1:])}
    high = limits["high"]

    reported_modes = [str(row["mode"]) for row in summary_reported]
    if reported_modes != MODE_ORDER:
        raise ValueError(
            f"Expected summary modes {MODE_ORDER}, got {reported_modes}"
        )
    mode_count = len(MODE_ORDER)
    expected_samples = (
        mode_count * config["repeats"] * config["phases"] *
        config["samples_per_phase"]
    )
    if len(samples) != expected_samples:
        raise ValueError(f"Expected {expected_samples} samples, got {len(samples)}")
    if len(phase_reported) != mode_count * config["phases"]:
        raise ValueError("Incomplete phase or overall summaries")
    if phase_dma and len(phase_dma) != mode_count * config["phases"]:
        raise ValueError("Incomplete phase DMA summaries")
    if not lines[-1].startswith("PASS: final adaptive benchmark complete, sink="):
        raise ValueError("Final PASS line is missing")

    expected_phase_load = {"OFF_A": 0, "ON_A": 1, "OFF_B": 0, "ON_B": 1}
    for mode in MODE_ORDER:
        mode_samples = [row for row in samples if row["mode"] == mode]
        expected_mode_samples = (
            config["repeats"] * config["phases"] *
            config["samples_per_phase"]
        )
        if len(mode_samples) != expected_mode_samples:
            raise ValueError(
                f"Expected {expected_mode_samples} samples for {mode}, "
                f"got {len(mode_samples)}"
            )
        for phase in PHASE_ORDER:
            phase_samples = [
                row for row in mode_samples if row["phase"] == phase
            ]
            expected_phase_samples = (
                config["repeats"] * config["samples_per_phase"]
            )
            if len(phase_samples) != expected_phase_samples:
                raise ValueError(
                    f"Expected {expected_phase_samples} samples for "
                    f"{mode} {phase}, got {len(phase_samples)}"
                )
            if any(
                int(row["load"]) != expected_phase_load[phase]
                for row in phase_samples
            ):
                raise ValueError(f"CPU1 load mismatch: {mode} {phase}")

    phase_groups: dict[tuple[str, str], list[float]] = defaultdict(list)
    mode_groups: dict[str, list[float]] = defaultdict(list)
    for row in samples:
        value = float(row["cpu_cycles"])
        phase_groups[(str(row["mode"]), str(row["phase"]))].append(value)
        mode_groups[str(row["mode"])].append(value)

    phase_rows: list[dict[str, object]] = []
    for reported in phase_reported:
        row = dict(reported)
        row.update(stats(phase_groups[(str(row["mode"]), str(row["phase"]))], high))
        phase_rows.append(row)

    summary_rows: list[dict[str, object]] = []
    for reported in summary_reported:
        row = dict(reported)
        row.update(stats(mode_groups[str(row["mode"])], high))
        row["violation_rate_percent"] = float(row["violations_calc"]) / int(row["samples"]) * 100.0
        if row["mode"] == "CPU_ONLY":
            row["throughput_vs_max_percent"] = 0.0
        else:
            max_bw = float(next(item for item in summary_reported if item["mode"] == "FIXED_MAX")["dma_MiB_per_s"])
            row["throughput_vs_max_percent"] = float(row["dma_MiB_per_s"]) / max_bw * 100.0
        summary_rows.append(row)

    for row in phase_rows:
        for field in ("min", "mean", "p95", "max", "violations"):
            calc = row[field + "_calc"] if field != "violations" else row["violations_calc"]
            if abs(float(row[field]) - float(calc)) > 0.035:
                raise ValueError(f"Phase summary mismatch: {row['mode']} {row['phase']} {field}")
    for row in summary_rows:
        for field in ("min", "mean", "p95", "p99", "max", "violations"):
            calc = row[field + "_calc"] if field != "violations" else row["violations_calc"]
            if abs(float(row[field]) - float(calc)) > 0.035:
                raise ValueError(f"Overall summary mismatch: {row['mode']} {field}")
        if row["mode"] != "CPU_ONLY":
            throughput = (
                8.0 * int(row["dma_commands"]) * 100_000_000.0 /
                int(row["dma_cycles"])
            )
            if abs(float(row["dma_MiB_per_s"]) - throughput) > 0.035:
                raise ValueError(f"Overall throughput mismatch: {row['mode']}")

    transition_results: dict[str, tuple[int, int, int]] = {}
    for adaptive_mode in ("BURST_ADAPT", "RBR_ADAPT"):
        adaptive = [row for row in samples if row["mode"] == adaptive_mode]
        transitions = [
            row for row in adaptive
            if row["level_before"] != row["level_after"]
        ]
        up = sum(
            int(row["level_after"]) > int(row["level_before"])
            for row in transitions
        )
        down = sum(
            int(row["level_after"]) < int(row["level_before"])
            for row in transitions
        )
        reported_transitions = int(
            next(
                row for row in summary_reported
                if row["mode"] == adaptive_mode
            )["transitions"]
        )
        if len(transitions) != reported_transitions or up == 0 or down == 0:
            raise ValueError(
                f"{adaptive_mode} transition count does not reconcile"
            )
        transition_results[adaptive_mode] = (len(transitions), up, down)

    if phase_dma:
        for row in phase_dma:
            if row["mode"] == "CPU_ONLY":
                continue
            throughput = (
                8.0 * int(row["commands"]) * 100_000_000.0 /
                int(row["dma_cycles"])
            )
            if abs(float(row["dma_MiB_per_s"]) - throughput) > 0.035:
                raise ValueError(
                    f"Phase throughput mismatch: {row['mode']} {row['phase']}"
                )
        rbr_modes = {"RBR_50", "RBR_67", "RBR_80", "RBR_ADAPT"}
        for summary_row in summary_reported:
            mode = str(summary_row["mode"])
            mode_phases = [row for row in phase_dma if row["mode"] == mode]
            fields = ["commands", "dma_cycles"]
            if mode in rbr_modes:
                fields += ["r_wait", "w_wait", "r_windows", "w_windows"]
            for field in fields:
                summary_field = "dma_commands" if field == "commands" else field
                total = sum(int(row[field]) for row in mode_phases)
                if total != int(summary_row[summary_field]):
                    raise ValueError(
                        f"Phase DMA total mismatch: {mode} {summary_field}"
                    )
            if mode not in rbr_modes:
                for field in ("r_wait", "w_wait", "r_windows", "w_windows"):
                    if int(summary_row[field]) != 0:
                        raise ValueError(
                            f"RBR bypass counter is nonzero: {mode} {field}"
                        )

    (ROOT / "raw.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_csv(ROOT / "summary.csv", summary_rows)
    trace_svg(samples, limits["low"], high, "RBR_ADAPT", "trace.svg")
    trace_svg(samples, limits["low"], high,
              "BURST_ADAPT", "burst_trace.svg")
    tradeoff_svg(summary_rows)
    print(
        f"PASS: {len(samples)} samples, {len(phase_rows)} phase summaries, "
        f"{len(summary_rows)} overall summaries"
    )
    for adaptive_mode, (count, up, down) in transition_results.items():
        print(f"PASS: {adaptive_mode} transitions={count} "
              f"(up={up}, down={down})")
    print("PASS: UART summaries reproduce from sample rows")


if __name__ == "__main__":
    main()
