#!/usr/bin/env python3
"""Check the lxplus-condor run against the lpc-condor reference.

Same 8 input files and selection on both sites, so per-job and total counts
must agree exactly. Exits non-zero on any mismatch.

    python3 validation/lxplus-condor/check_results.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEYS = ("n_events", "n_HLT_PFHT900", "n_2jets_pt500")


def load(path):
    jobs = json.loads(path.read_text())["per_job"]
    return {
        tuple(sorted(j["files"])): {k: j[k] for k in KEYS} for j in jobs
    }


def main():
    lx = load(HERE / "run2" / "summary.json")
    lpc = load(HERE.parent / "lpc-condor" / "run2" / "summary.json")
    bad = 0
    if set(lx) != set(lpc):
        print("FAIL: the two runs used different file groupings")
        bad += 1
    for files, counts in sorted(lx.items()):
        ref = lpc.get(files)
        status = "OK" if counts == ref else "MISMATCH"
        bad += status != "OK"
        print(f"{status:8s} {files[0][:8]}+{files[1][:8]}  lxplus={counts}  lpc={ref}")
    tot = {k: sum(c[k] for c in lx.values()) for k in KEYS}
    ref_tot = {k: sum(c[k] for c in lpc.values()) for k in KEYS}
    print(f"totals lxplus={tot}\ntotals lpc   ={ref_tot}")
    print("PASS" if bad == 0 and tot == ref_tot else "FAIL")
    return 0 if bad == 0 and tot == ref_tot else 1


if __name__ == "__main__":
    sys.exit(main())
