#!/usr/bin/env python3
"""Generate a top-level block diagram (SVG) for an RTL module.

Elaborates the module with Verilator (real SystemVerilog support, so it
reads the actual ../rtl_lib sources directly -- the diagram can never drift
from the code) and extracts only the instance hierarchy: which submodules
a module instantiates, and what they're called. This is intentionally NOT
a gate-level or synthesized-netlist view (that's what TerosHDL's per-module
"block diagram" gives you, and why it's too deep for general docs) -- it's
the same hierarchy you'd read by eye at the top of the .sv file, rendered.

Two things keep it at "biggest component blocks" granularity instead of a
sprawling near-gate-level graph:

- --depth caps how many levels of instantiation to expand. depth=0 shows
  only the top module's direct children.
- Siblings of the same submodule instantiated from a `generate` loop (e.g.
  16 DDS lanes) are collapsed into one box labeled "name (xN)", since a
  fully elaborated netlist would otherwise show all 16 separately.

SystemVerilog `interface` instances (axi4_stream_if, bram_if, ...) are
dropped -- they're language-level port bundling, not a functional block.

Usage:
    gen_block_diagram.py TOP_MODULE OUTPUT.svg [--depth N] [--rtl-lib DIR]
                          [--stub-dir DIR]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict


def find_rtl_dirs(rtl_lib):
    """All immediate subdirectories of rtl_lib, plus rtl_lib itself -- used
    as verilator -y include paths so it can resolve any submodule by
    filename without the caller having to know where each one lives."""
    dirs = [rtl_lib]
    for name in sorted(os.listdir(rtl_lib)):
        path = os.path.join(rtl_lib, name)
        if os.path.isdir(path):
            dirs.append(path)
    return dirs


def find_top_file(rtl_lib, top_module):
    for root, _dirs, files in os.walk(rtl_lib):
        if f"{top_module}.sv" in files:
            return os.path.join(root, f"{top_module}.sv")
    raise SystemExit(f"error: no {top_module}.sv found under {rtl_lib}")


def run_verilator(top_module, top_file, rtl_dirs, stub_dir, workdir):
    stub_files = []
    if stub_dir and os.path.isdir(stub_dir):
        stub_files = [
            os.path.join(stub_dir, f)
            for f in sorted(os.listdir(stub_dir))
            if f.endswith(".sv")
        ]
    cmd = [
        "verilator", "--json-only", "--timing", "-Wno-fatal",
        "--top-module", top_module,
    ]
    for d in rtl_dirs:
        cmd += ["-y", d]
    cmd += stub_files + [top_file]
    result = subprocess.run(cmd, cwd=workdir, capture_output=True, text=True)
    json_path = os.path.join(workdir, "obj_dir", f"V{top_module}.tree.json")
    if not os.path.exists(json_path):
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(
            f"\nerror: verilator did not produce {json_path}.\n"
            "Likely a missing module (Xilinx primitive or similar) -- add a "
            "blackbox stub for it under --stub-dir. See the MODMISSING "
            "errors above for the module name."
        )
    return json_path


def extract_block_diagram(json_path, top_module, max_depth):
    data = json.load(open(json_path))
    addr_to_mod = {m["addr"]: m for m in data["modulesp"]}
    by_name = {}
    for m in data["modulesp"]:
        by_name.setdefault(m["origName"], m)

    def find_cells(node, out):
        if isinstance(node, dict):
            if node.get("type") == "CELL":
                out.append(node)
            for v in node.values():
                find_cells(v, out)
        elif isinstance(node, list):
            for v in node:
                find_cells(v, out)

    def children_of(mod_name):
        mod = by_name.get(mod_name)
        if mod is None:
            return []
        cells = []
        find_cells(mod.get("stmtsp"), cells)
        out = []
        for c in cells:
            child = addr_to_mod.get(c.get("modp"))
            if child is None:
                out.append(str(c.get("modp")))
            elif child.get("type") == "IFACE":
                continue  # SV interface instance, not a functional block
            else:
                out.append(child["origName"])
        return out

    edges = defaultdict(int)  # (parent, child) -> instance count

    def walk(mod_name, depth):
        counts = defaultdict(int)
        for child in children_of(mod_name):
            counts[child] += 1
        for child, n in counts.items():
            edges[(mod_name, child)] += n
            if depth < max_depth:
                walk(child, depth + 1)

    walk(top_module, 0)
    return edges


def render_dot(edges, top_module, out_svg):
    lines = [
        "digraph block {",
        '  rankdir=LR; node [shape=box, style=rounded, fontname="Helvetica"];',
        f'  "{top_module}" [style="rounded,bold"];',
    ]
    for (parent, child), n in edges.items():
        label = child if n == 1 else f"{child}  (×{n})"
        node_id = f'"{parent}__{child}"'
        lines.append(f'  "{parent}" -> {node_id} [arrowhead=none];')
        lines.append(f'  {node_id} [label="{label}"];')
    lines.append("}")
    dot_src = "\n".join(lines)

    result = subprocess.run(
        ["dot", "-Tsvg", "-o", out_svg],
        input=dot_src, capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit("error: graphviz 'dot' failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("top_module")
    ap.add_argument("output_svg")
    ap.add_argument("--depth", type=int, default=0,
                     help="levels of instantiation to expand below the top module (default: 0, direct children only)")
    ap.add_argument("--rtl-lib", default="../rtl_lib",
                     help="path to rtl_lib (default: ../rtl_lib, i.e. run from firmware/fusesoc/)")
    ap.add_argument("--stub-dir", default="scripts/block_diagram_stubs",
                     help="directory of blackbox .sv stubs for vendor primitives (default: scripts/block_diagram_stubs)")
    args = ap.parse_args()

    rtl_lib = os.path.abspath(args.rtl_lib)
    top_file = find_top_file(rtl_lib, args.top_module)
    rtl_dirs = find_rtl_dirs(rtl_lib)

    with tempfile.TemporaryDirectory() as workdir:
        json_path = run_verilator(args.top_module, top_file, rtl_dirs,
                                   os.path.abspath(args.stub_dir) if args.stub_dir else None,
                                   workdir)
        edges = extract_block_diagram(json_path, args.top_module, args.depth)

    os.makedirs(os.path.dirname(os.path.abspath(args.output_svg)) or ".", exist_ok=True)
    render_dot(edges, args.top_module, args.output_svg)
    print(f"wrote {args.output_svg} ({len(edges)} blocks, depth={args.depth})")


if __name__ == "__main__":
    main()
