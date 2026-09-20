from __future__ import annotations

import csv
import html
import math
import statistics
from collections import OrderedDict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
RAW_PATH = ROOT / "raw.log"
SAMPLES_PATH = ROOT / "samples.csv"
SUMMARY_PATH = ROOT / "summary.csv"
TRADEOFF_PATH = ROOT / "tradeoff.svg"

THEORETICAL_MIB_S = 8.0 * 100_000_000.0 / (1024.0 * 1024.0)
LIMIT_PERCENT = 50.0
THROUGHPUT_TOLERANCE = 0.10
CPU_CYCLE_TOLERANCE = 0.05


def parse_number(value: str) -> int | float:
    if "." in value:
        return float(value)
    return int(value)


def read_tagged_csv(lines: list[str], tag: str) -> list[dict[str, object]]:
    header_line = next(line for line in lines if line.startswith(f"{tag}_HEADER,"))
    header = next(csv.reader([header_line]))[1:]
    records: list[dict[str, object]] = []

    for line in lines:
        if not line.startswith(f"{tag},"):
            continue
        values = next(csv.reader([line]))[1:]
        record: dict[str, object] = {}
        for key, value in zip(header, values):
            record[key] = value if key == "name" else parse_number(value)
        records.append(record)

    return records


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    index = math.ceil(percentile * len(ordered)) - 1
    return ordered[index]


def classify(name: str) -> str:
    if name.startswith("RAW_"):
        return "Burst/Outstanding"
    if name in {"RBR50_T512", "RBR50_T1536"}:
        return "Threshold"
    if name.endswith("_ONLY"):
        return "Channel"
    return "RBR ratio"


def calculate(samples: list[dict[str, object]],
              reported: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: OrderedDict[str, list[dict[str, object]]] = OrderedDict()
    for row in samples:
        grouped.setdefault(str(row["name"]), []).append(row)

    reported_by_name = {str(row["name"]): row for row in reported}
    result: list[dict[str, object]] = []

    for name, rows in grouped.items():
        base = [float(row["base_cpu"]) for row in rows]
        load = [float(row["load_cpu"]) for row in rows]
        dma = [float(row["dma_cycles"]) for row in rows]
        base_mean = statistics.fmean(base)
        cpu_mean = statistics.fmean(load)
        dma_mean = statistics.fmean(dma)
        target = base_mean * (1.0 + LIMIT_PERCENT / 100.0)
        violations = sum(value > target for value in load)

        row = dict(reported_by_name[name])
        row.update(
            {
                "base_mean_calc": base_mean,
                "cpu_mean_calc": cpu_mean,
                "cpu_sd": statistics.stdev(load),
                "p95_calc": nearest_rank(load, 0.95),
                "p99_calc": nearest_rank(load, 0.99),
                "target_calc": target,
                "slowdown_calc": (cpu_mean / base_mean - 1.0) * 100.0,
                "violations_calc": violations,
                "violation_percent_calc": violations / len(rows) * 100.0,
                "dma_cycles_calc": dma_mean,
                "throughput_calc": 8.0 * 100_000_000.0 / dma_mean,
                "all_overlap": int(all(int(item["overlap"]) == 1 for item in rows)),
                "all_checks_ok": int(all(int(item["checks_ok"]) == 1 for item in rows)),
                "group": classify(name),
            }
        )
        result.append(row)

    max_row = next(row for row in result if row["name"] == "RAW_B16_O4")
    max_throughput = float(max_row["throughput_calc"])
    max_excess = float(max_row["cpu_mean_calc"]) - float(max_row["base_mean_calc"])

    for row in result:
        throughput = float(row["throughput_calc"])
        excess = float(row["cpu_mean_calc"]) - float(row["base_mean_calc"])
        row["throughput_percent_of_max"] = throughput / max_throughput * 100.0
        row["theoretical_utilization_percent"] = throughput / THEORETICAL_MIB_S * 100.0
        row["excess_latency_reduction_percent"] = (1.0 - excess / max_excess) * 100.0
        row["p99_margin_to_target"] = float(row["target_calc"]) - float(row["p99_calc"])
        row["target_met"] = int(float(row["violation_percent_calc"]) == 0.0)

    for row in result:
        dominated = any(
            float(other["throughput_calc"])
            >= float(row["throughput_calc"]) - THROUGHPUT_TOLERANCE
            and float(other["cpu_mean_calc"])
            <= float(row["cpu_mean_calc"]) + CPU_CYCLE_TOLERANCE
            and (
                float(other["throughput_calc"])
                > float(row["throughput_calc"]) + THROUGHPUT_TOLERANCE
                or float(other["cpu_mean_calc"])
                < float(row["cpu_mean_calc"]) - CPU_CYCLE_TOLERANCE
            )
            for other in result
        )
        row["pareto_mean"] = int(not dominated)

    return result


def validate(samples: list[dict[str, object]],
             summary: list[dict[str, object]]) -> None:
    if len(samples) != 2500:
        raise ValueError(f"Expected 2500 samples, got {len(samples)}")
    if len(summary) != 25:
        raise ValueError(f"Expected 25 summaries, got {len(summary)}")

    counts: dict[str, int] = {}
    for row in samples:
        name = str(row["name"])
        counts[name] = counts.get(name, 0) + 1
    if any(count != 100 for count in counts.values()):
        raise ValueError("Every configuration must have exactly 100 samples")
    if any(int(row["all_overlap"]) != 1 for row in summary):
        raise ValueError("At least one timed CPU interval did not fully overlap DMA")
    if any(int(row["all_checks_ok"]) != 1 for row in summary):
        raise ValueError("At least one sample failed its correctness checks")
    if any(int(row["errors"]) != 0 for row in summary):
        raise ValueError("At least one configuration summary reports an error")

    checks = {
        "base_mean": ("base_mean_calc", 0.03),
        "cpu_mean": ("cpu_mean_calc", 0.03),
        "p95": ("p95_calc", 0.03),
        "p99": ("p99_calc", 0.03),
        "dma_cycles": ("dma_cycles_calc", 2.0),
        "dma_MiB_per_s": ("throughput_calc", 0.03),
    }
    for reported, (calculated, tolerance) in checks.items():
        maximum = max(
            abs(float(row[reported]) - float(row[calculated]))
            for row in summary
        )
        if maximum > tolerance:
            raise ValueError(
                f"Reported {reported} does not reconcile: max difference={maximum}"
            )


def write_csv(path: Path, records: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(records[0].keys()), lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def svg_text(x: float, y: float, text: str, **attributes: object) -> str:
    attrs = " ".join(
        f'{key.replace("_", "-")}="{value}"' for key, value in attributes.items()
    )
    return f'<text x="{x:.1f}" y="{y:.1f}" {attrs}>{html.escape(text)}</text>'


def plot_tradeoff(summary: list[dict[str, object]]) -> None:
    width, height = 1200, 760
    left, right, top, bottom = 105, 50, 70, 90
    plot_width = width - left - right
    plot_height = height - top - bottom
    x_max, y_max = 105.0, 800.0
    colors = {
        "Burst/Outstanding": "#2563EB",
        "RBR ratio": "#DC2626",
        "Threshold": "#7C3AED",
        "Channel": "#059669",
    }
    candidates = {"RAW_B2_O4", "RBR50_W_ONLY", "RBR80_T256", "RAW_B16_O4"}

    def sx(value: float) -> float:
        return left + value / x_max * plot_width

    def sy(value: float) -> float:
        return top + plot_height - value / y_max * plot_height

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#FFFFFF"/>',
        svg_text(width / 2, 34, "CPU latency–DMA throughput trade-off (Arty Z7-20 board)",
                 text_anchor="middle", font_family="Arial", font_size=22,
                 font_weight="bold", fill="#111827"),
    ]

    for value in range(0, 101, 10):
        x = sx(float(value))
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{top + plot_height}" stroke="#E5E7EB"/>')
        parts.append(svg_text(x, top + plot_height + 27, str(value), text_anchor="middle", font_family="Arial", font_size=12, fill="#374151"))
    for value in range(0, 801, 100):
        y = sy(float(value))
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#E5E7EB"/>')
        parts.append(svg_text(left - 14, y + 4, str(value), text_anchor="end", font_family="Arial", font_size=12, fill="#374151"))

    limit_x = sx(LIMIT_PERCENT)
    parts.append(f'<line x1="{limit_x:.1f}" y1="{top}" x2="{limit_x:.1f}" y2="{top + plot_height}" stroke="#6B7280" stroke-width="2" stroke-dasharray="7 6"/>')
    parts.append(svg_text(limit_x + 8, top + 22, "+50% latency limit", font_family="Arial", font_size=12, fill="#4B5563"))

    pareto = sorted(
        (row for row in summary if int(row["pareto_mean"]) == 1),
        key=lambda row: float(row["slowdown_calc"]),
    )
    points = " ".join(
        f'{sx(float(row["slowdown_calc"])):.1f},{sy(float(row["throughput_calc"])):.1f}'
        for row in pareto
    )
    parts.append(f'<polyline points="{points}" fill="none" stroke="#111827" stroke-width="2" opacity="0.65"/>')

    for row in summary:
        x = sx(float(row["slowdown_calc"]))
        y = sy(float(row["throughput_calc"]))
        color = colors[str(row["group"])]
        radius = 8 if str(row["name"]) in candidates else 5
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{radius}" fill="{color}" opacity="0.88" stroke="#FFFFFF" stroke-width="1.5"/>')
        if str(row["name"]) in candidates:
            parts.append(svg_text(x + 9, y - 9, str(row["name"]), font_family="Arial", font_size=12, font_weight="bold", fill="#111827"))

    legend_x = left + 18
    for index, (label, color) in enumerate(colors.items()):
        y = top + 24 + index * 25
        parts.append(f'<circle cx="{legend_x}" cy="{y - 4}" r="5" fill="{color}"/>')
        parts.append(svg_text(legend_x + 12, y, label, font_family="Arial", font_size=12, fill="#374151"))

    parts.append(svg_text(left + plot_width / 2, height - 26, "CPU mean slowdown versus paired CPU-only baseline (%)", text_anchor="middle", font_family="Arial", font_size=15, fill="#111827"))
    parts.append(f'<text x="27" y="{top + plot_height / 2:.1f}" transform="rotate(-90 27 {top + plot_height / 2:.1f})" text-anchor="middle" font-family="Arial" font-size="15" fill="#111827">DMA useful throughput (MiB/s)</text>')
    parts.append("</svg>")
    TRADEOFF_PATH.write_text("\n".join(parts), encoding="utf-8")


def main() -> None:
    lines = RAW_PATH.read_text(encoding="utf-8").splitlines()
    samples = read_tagged_csv(lines, "SAMPLE")
    reported = read_tagged_csv(lines, "SUMMARY")
    summary = calculate(samples, reported)
    validate(samples, summary)
    write_csv(SAMPLES_PATH, samples)
    write_csv(SUMMARY_PATH, summary)
    plot_tradeoff(summary)

    pareto = [str(row["name"]) for row in summary if int(row["pareto_mean"]) == 1]
    print(f"PASS: samples={len(samples)}, configs={len(summary)}, errors=0")
    print("Pareto:", ", ".join(pareto))


if __name__ == "__main__":
    main()
