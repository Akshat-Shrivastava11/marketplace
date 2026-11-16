#!/usr/bin/env python3
"""Per-job payload: for each local NanoAOD file, read the first N events and count
(a) events with HLT_PFHT900 fired and (b) events with >= 2 jets with pT > 500 GeV.
Writes a small JSON file with per-file and total counts."""
import argparse
import json
import os
import time

import awkward as ak
import uproot

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True, help="output JSON path")
ap.add_argument("--job", required=True, help="job label")
ap.add_argument("--nevents", type=int, default=20000)
ap.add_argument("inputs", nargs="+", help="local ROOT files")
args = ap.parse_args()

t0 = time.time()
per_file = []
for path in args.inputs:
    with uproot.open(path) as f:
        tree = f["Events"]
        n_read = min(args.nevents, int(tree.num_entries))
        arrs = tree.arrays(["HLT_PFHT900", "Jet_pt"], entry_stop=n_read, library="ak")
    n_hlt = int(ak.sum(arrs["HLT_PFHT900"]))
    n_2jets = int(ak.sum(ak.sum(arrs["Jet_pt"] > 500, axis=1) >= 2))
    per_file.append({
        "file": os.path.basename(path),
        "events_read": n_read,
        "n_HLT_PFHT900": n_hlt,
        "n_ge2jets_pt_gt_500": n_2jets,
    })

result = {
    "job": args.job,
    "nevents_per_file_requested": args.nevents,
    "files": per_file,
    "events_read_total": sum(x["events_read"] for x in per_file),
    "n_HLT_PFHT900_total": sum(x["n_HLT_PFHT900"] for x in per_file),
    "n_ge2jets_pt_gt_500_total": sum(x["n_ge2jets_pt_gt_500"] for x in per_file),
    "payload_wall_s": round(time.time() - t0, 2),
}
with open(args.out, "w") as fh:
    json.dump(result, fh, indent=2)
print(json.dumps(result, indent=2))
