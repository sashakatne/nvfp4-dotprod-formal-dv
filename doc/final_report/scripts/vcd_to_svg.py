#!/usr/bin/env python3
"""Render a compact SVG timing diagram from a small VCD file."""

from __future__ import annotations

import argparse
import html
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Signal:
    name: str
    code: str
    width: int
    changes: list[tuple[int, str]]


def parse_vcd(path: Path, wanted: list[str]) -> tuple[int, list[Signal]]:
    wanted_set = set(wanted)
    signals_by_code: dict[str, Signal] = {}
    current_time = 0
    max_time = 0
    in_header = True

    with path.open("r", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            if in_header:
                if line.startswith("$var "):
                    parts = line.split()
                    if len(parts) >= 5:
                        width = int(parts[2])
                        code = parts[3]
                        name = parts[4]
                        if len(parts) >= 6 and parts[5].startswith("["):
                            name = f"{name}{parts[5]}"
                        base = name.split("[", 1)[0]
                        if base in wanted_set:
                            signals_by_code[code] = Signal(base, code, width, [])
                elif line == "$enddefinitions $end":
                    in_header = False
                continue

            if line.startswith("#"):
                current_time = int(line[1:])
                max_time = max(max_time, current_time)
                continue

            if line[0] in "01xXzZ":
                value = line[0].lower()
                code = line[1:]
            elif line[0] in "bB":
                bits, code = line[1:].split(None, 1)
                value = bits.lower()
            else:
                continue

            sig = signals_by_code.get(code)
            if sig is not None:
                if not sig.changes or sig.changes[-1][1] != value:
                    sig.changes.append((current_time, value))

    ordered = [signals_by_code[s.code] for s in signals_by_code.values()]
    ordered.sort(key=lambda sig: wanted.index(sig.name))
    return max_time or 1, ordered


def fmt_value(sig: Signal, value: str) -> str:
    if sig.width == 1:
        return value
    clean = value.replace("x", "0").replace("z", "0")
    try:
      intval = int(clean, 2)
      if sig.width > 16:
          return f"0x{intval:08X}"
      return f"0x{intval:X}"
    except ValueError:
      return value[:12]


def draw_svg(title: str, max_time: int, signals: list[Signal]) -> str:
    left = 180
    right = 40
    top = 54
    row_h = 42
    lane_h = 22
    width = 1100
    height = top + row_h * len(signals) + 45
    scale = (width - left - right) / max_time

    def x_at(t: int) -> float:
        return left + t * scale

    out: list[str] = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">')
    out.append('<rect width="100%" height="100%" fill="#ffffff"/>')
    out.append(f'<text x="{left}" y="28" font-family="Arial, sans-serif" font-size="20" font-weight="700" fill="#172033">{html.escape(title)}</text>')
    out.append(f'<line x1="{left}" y1="{top-14}" x2="{width-right}" y2="{top-14}" stroke="#c8d1df" stroke-width="1"/>')

    for idx, sig in enumerate(signals):
        y_mid = top + idx * row_h + 16
        y_hi = y_mid - lane_h / 2
        y_lo = y_mid + lane_h / 2
        out.append(f'<text x="24" y="{y_mid+5}" font-family="Menlo, Consolas, monospace" font-size="13" fill="#273449">{html.escape(sig.name)}</text>')
        out.append(f'<line x1="{left}" y1="{y_mid}" x2="{width-right}" y2="{y_mid}" stroke="#e6ebf2" stroke-width="1"/>')

        changes = sig.changes or [(0, "x")]
        if changes[0][0] != 0:
            changes = [(0, changes[0][1])] + changes
        if changes[-1][0] < max_time:
            changes = changes + [(max_time, changes[-1][1])]

        for (t0, v0), (t1, _) in zip(changes, changes[1:]):
            x0 = x_at(t0)
            x1 = x_at(t1)
            if sig.width == 1:
                y = y_hi if v0 == "1" else y_lo
                color = "#1f6feb" if v0 in ("0", "1") else "#8a93a5"
                out.append(f'<line x1="{x0:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{y:.1f}" stroke="{color}" stroke-width="2.2"/>')
                out.append(f'<line x1="{x0:.1f}" y1="{y_hi:.1f}" x2="{x0:.1f}" y2="{y_lo:.1f}" stroke="{color}" stroke-width="1"/>')
            else:
                out.append(f'<rect x="{x0:.1f}" y="{y_hi:.1f}" width="{max(1, x1-x0):.1f}" height="{lane_h:.1f}" rx="3" fill="#edf4ff" stroke="#7aa7e8"/>')
                label = html.escape(fmt_value(sig, v0))
                out.append(f'<text x="{x0+5:.1f}" y="{y_mid+5:.1f}" font-family="Menlo, Consolas, monospace" font-size="11" fill="#173b67">{label}</text>')

    for frac in [0, 0.25, 0.5, 0.75, 1.0]:
        t = int(max_time * frac)
        x = x_at(t)
        out.append(f'<line x1="{x:.1f}" y1="{top-18}" x2="{x:.1f}" y2="{height-28}" stroke="#f0f3f8" stroke-width="1"/>')
        out.append(f'<text x="{x:.1f}" y="{height-10}" font-family="Arial, sans-serif" font-size="11" fill="#667085" text-anchor="middle">{t}</text>')

    out.append("</svg>")
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vcd")
    parser.add_argument("svg")
    parser.add_argument("--title", required=True)
    parser.add_argument("--signals", nargs="+", required=True)
    args = parser.parse_args()

    max_time, signals = parse_vcd(Path(args.vcd), args.signals)
    if not signals:
        raise SystemExit("no requested signals found in VCD")
    Path(args.svg).parent.mkdir(parents=True, exist_ok=True)
    Path(args.svg).write_text(draw_svg(args.title, max_time, signals), encoding="utf-8")


if __name__ == "__main__":
    main()
