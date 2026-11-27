"""Summarize end-to-end Luanti worker mailbox delays and their phases."""
import re
import statistics
import sys
from pathlib import Path


def records(log, pattern, cast=int):
    return [tuple(map(cast, row)) for row in re.findall(pattern, log)]


def duration_summary(label, micros):
    if not micros:
        print(f"{label}: no matching samples")
        return
    median = statistics.median(micros)
    p90 = statistics.quantiles(micros, n=10, method="inclusive")[8] if len(micros) > 1 else median
    print(f"{label}: n={len(micros)}, median={median/1000:.1f}, "
          f"p90={p90/1000:.1f}, max={max(micros)/1000:.1f} ms")


def report(log):
    days = records(log, r"DAY_CORE (\d+) began=(\d+) ended=(\d+)")
    phases = records(log, r"TILE_PHASE (\d+) us=\d+ landscape=(\d+) tick=(\d+)")
    saves = records(log, r"SAVE_PHASE (\d+) begin=(\d+) encode=(\d+) packed=(\d+) finish=(\d+)")
    views = records(log, r"PROBE_VIEW \d+ kind=\w+ send=(\d+) sample=(\d+) receive=(\d+)")
    if not days or not views or not phases:
        raise SystemExit("No completed live stock campaign profile; check the fixture and configuration.")

    duration_summary("Simulation day wall time", [end - start for _, start, end in days])
    fraction = statistics.median(landscape / (landscape + tick) for _, landscape, tick in phases)
    print(f"Median tile-loop share of landscape + after-tick time: {fraction:.1%}")
    for day, start, encode, packed, end in saves:
        print(f"Save at day {day}: encode={(encode-start)/1000:.1f}, "
              f"compress={(packed-encode)/1000:.1f}, write={(end-packed)/1000:.1f} ms")

    def during(send, windows):
        return any(start <= send < end for start, end in windows)

    daylight = [(start, end) for _, start, end in days]
    saving = [(start, end) for _, start, _, _, end in saves]
    for label, include in (
        ("All requests", lambda _: True),
        ("Sent during simulation", lambda sent: during(sent, daylight)),
        ("Sent during save", lambda sent: during(sent, saving)),
        ("Sent outside both phases", lambda sent: not during(sent, daylight + saving)),
    ):
        subset = [(send, sample, receive) for send, sample, receive in views if include(send)]
        duration_summary(f"{label}, worker sample", [sample - send for send, sample, _ in subset])
        duration_summary(f"{label}, host receipt", [receive - send for send, _, receive in subset])


if __name__ == "__main__":
    report(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"))
