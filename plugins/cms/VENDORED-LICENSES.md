# Vendored Content Licenses

## IRIS-HEP Marketplace

The following skill was adapted from the
[IRIS-HEP marketplace](https://github.com/iris-hep/marketplace) (upstream
commit `ca69e49`, 2026-09-27):

- `skills/awkward-array/`, from `iris-hep/skills/awkward-array/`

**Original authors:** Gordon Watts, Ben Galewsky

**What was kept:** the skill name, the five-step workflow (build records →
filter early → combinatorics → add fields → repeat), the topic coverage
(records, filtering/aggregation, sorting, combinatorics, argmin/argmax,
flattening, NumPy interop, pitfalls, file I/O), and the `argmax(...,
keepdims=True)` example.

**What changed:**

- Rewritten for CMS: NanoAOD examples (uproot `Events` tree, `Muon_*`/`Jet_*`
  branches, index branches such as `Jet_muonIdx1`, `genWeight`), GeV units, and
  CMSSW vs pip environments. Added a runnable worked example
  (`assets/nanoaod_dimuon.py`).
- Ten reference notes merged into `references/operations.md` and
  `references/io-and-environments.md`.
- Every example re-tested on cmslpc with awkward 2.6.3 (CMSSW_15_0_21) and
  2.8.12 (pip). Upstream statements found incorrect and corrected here:
  - "There is no `ak.max` or `ak.min`": both exist.
  - `ak.fill_like`: does not exist (use `ak.full_like` / `ak.zeros_like`).
  - `ak.count` "counts non-empty elements": it counts non-`None` values.
  - `ak.from_json("data.json")`: parses the string as JSON; a file needs
    `pathlib.Path`.
  - "Avoid `axis=None`": valid and useful for `ak.sum` / `ak.flatten`; the
    skill asks for a deliberate choice of axis instead.

**License:** BSD 3-Clause License

```text
BSD 3-Clause License

Copyright (c) 2025, IRIS-HEP

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
