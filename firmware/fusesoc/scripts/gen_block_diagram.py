#!/usr/bin/env python3
"""Generate a top-level block/schematic diagram (SVG) for an RTL module.

Elaborates the module with Verilator (real SystemVerilog support, so it
reads the actual ../rtl_lib sources directly -- the diagram can never drift
from the code) and extracts, for the top module and its direct-child
instances:

- each block's ports (name + direction), drawn on its left/right side like
  a real functional block diagram (inputs left, outputs right);
- the actual wiring between them: which output pin drives which input
  pin(s), including the top module's own boundary ports.

This is deliberately NOT a gate-level or synthesized-netlist view (that's
what TerosHDL's per-module "block diagram" gives you, and why it's too deep
for general docs) -- it stays at "one box per submodule instance" and just
adds the real port list and real wires to that box, instead of a bare
containment tree.

Two things keep the wiring itself from ballooning into a rat's nest:

- Only the top module's direct-child instances become boxes (deeper
  instances aren't expanded -- there's no --depth here, unlike a pure
  hierarchy-tree view, because full port-level wiring gets dense fast).
- Siblings of the same submodule instantiated from a `generate` loop (e.g.
  16 DDS lanes) are collapsed into one box labeled "name (xN)"; the wiring
  drawn is that of the first instance in the group, as a representative.

SystemVerilog `interface` instances (axi4_stream_if, bram_if, ...) are
dropped -- they're language-level port bundling, not a functional block.

Usage:
    gen_block_diagram.py TOP_MODULE OUTPUT.svg [--rtl-lib DIR] [--stub-dir DIR]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict


def find_rtl_dirs(rtl_lib):
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


# ---------------------------------------------------------------------------
# JSON AST helpers
# ---------------------------------------------------------------------------

def find_all(node, pred, out):
    if isinstance(node, dict):
        if pred(node):
            out.append(node)
        for v in node.values():
            find_all(v, pred, out)
    elif isinstance(node, list):
        for v in node:
            find_all(v, pred, out)


def collect_varrefs(node, out):
    """All signal names a pin expression actually touches (handles plain
    refs, bit-selects, concatenations, ...)."""
    find_all(node, lambda n: n.get("type") == "VARREF", out)


def sanitize(s):
    return re.sub(r"[^A-Za-z0-9_]", "_", s)


class Design:
    def __init__(self, json_path):
        data = json.load(open(json_path))
        self.by_addr = {}          # addr -> node, for every VAR/MODULE we see
        self.modules_by_name = {}  # origName -> module node (first wins)
        for m in data["modulesp"]:
            self.by_addr[m["addr"]] = m
            self.modules_by_name.setdefault(m["origName"], m)
        allvars = []
        find_all(data, lambda n: n.get("type") == "VAR", allvars)
        for v in allvars:
            self.by_addr[v["addr"]] = v

    def ports_of(self, mod_name):
        """[(name, direction)] in declaration order for a module's own I/O."""
        mod = self.modules_by_name.get(mod_name)
        if mod is None:
            return []
        vs = []
        find_all(mod.get("stmtsp"), lambda n: n.get("type") == "VAR", vs)
        return [(v["name"], v.get("direction", "NONE"))
                for v in vs if v.get("varType") == "PORT"]

    def cells_of(self, mod_name):
        mod = self.modules_by_name.get(mod_name)
        if mod is None:
            return []
        cells = []
        find_all(mod.get("stmtsp"), lambda n: n.get("type") == "CELL", cells)
        return cells

    def child_module_name(self, cell):
        child = self.by_addr.get(cell.get("modp"))
        return child["origName"] if child else str(cell.get("modp"))

    def child_module_type(self, cell):
        child = self.by_addr.get(cell.get("modp"))
        return child.get("type") if child else "MODULE"

    def pin_direction(self, pin):
        var = self.by_addr.get(pin.get("modVarp"))
        return var.get("direction", "NONE") if var else "NONE"


# ---------------------------------------------------------------------------
# Diagram model: blocks with ports, and wires between specific pins
# ---------------------------------------------------------------------------

class Block:
    def __init__(self, block_id, label, inputs, outputs):
        self.id = block_id          # unique graphviz node id
        self.label = label          # display name (may include "(xN)")
        self.inputs = inputs        # [(port_name, pin_id)]
        self.outputs = outputs      # [(port_name, pin_id)]


def build_diagram(design, top_module):
    blocks = {}          # block_id -> Block
    endpoints = defaultdict(list)  # net_name -> [(block_id, pin_id, direction)]

    top_id = "TOP"
    top_ports = design.ports_of(top_module)
    top_inputs = [(n, f"{top_id}_{sanitize(n)}") for n, d in top_ports if d == "INPUT"]
    top_outputs = [(n, f"{top_id}_{sanitize(n)}") for n, d in top_ports if d == "OUTPUT"]
    blocks[top_id] = Block(top_id, top_module, top_inputs, top_outputs)
    for n, pin_id in top_inputs:
        endpoints[n].append((top_id, pin_id, "OUTPUT"))  # a top input *drives* the inside
    for n, pin_id in top_outputs:
        endpoints[n].append((top_id, pin_id, "INPUT"))   # a top output is *driven* from inside

    # Group sibling instances of the same child module together (generate
    # loops); keep the first instance of each group as the wiring example.
    cells = [c for c in design.cells_of(top_module)
             if design.child_module_type(c) != "IFACE"]
    groups = defaultdict(list)
    for c in cells:
        groups[design.child_module_name(c)].append(c)

    for child_mod_name, group in groups.items():
        n = len(group)
        rep = group[0]
        block_id = f"inst_{sanitize(rep['name'])}"
        label = child_mod_name if n == 1 else f"{child_mod_name}  (×{n})"

        pins = []
        find_all(rep.get("pinsp") or [], lambda x: x.get("type") == "PIN", pins)
        ins, outs = [], []
        for pin in pins:
            pin_name = pin["name"]
            direction = design.pin_direction(pin)
            pin_id = f"{block_id}_{sanitize(pin_name)}"
            varrefs = []
            collect_varrefs(pin.get("exprp") or [], varrefs)
            net_names = {v["name"] for v in varrefs} or {f"{block_id}_{pin_name}_unconnected"}
            if direction == "OUTPUT":
                outs.append((pin_name, pin_id))
                for net in net_names:
                    endpoints[net].append((block_id, pin_id, "OUTPUT"))
            else:  # INPUT or INOUT: treat as a load
                ins.append((pin_name, pin_id))
                for net in net_names:
                    endpoints[net].append((block_id, pin_id, "INPUT"))
        blocks[block_id] = Block(block_id, label, ins, outs)

    # Turn shared nets into wires: each OUTPUT endpoint drives every INPUT
    # endpoint on the same net.
    wires = []  # (from_block, from_pin, to_block, to_pin)
    for _net, eps in endpoints.items():
        drivers = [e for e in eps if e[2] == "OUTPUT"]
        loads = [e for e in eps if e[2] == "INPUT"]
        for d in drivers:
            for l in loads:
                if d[0] == l[0]:
                    continue
                wires.append((d[0], d[1], l[0], l[1]))

    return blocks, wires


def render_dot(blocks, wires, top_module, out_svg):
    lines = [
        "digraph block {",
        '  rankdir=LR; splines=ortho; nodesep=0.4; ranksep=0.6;',
        '  node [shape=record, fontname="Helvetica", fontsize=10];',
        '  edge [fontname="Helvetica", fontsize=8, arrowsize=0.7];',
    ]

    def port_cell(name, _pin_id):
        return f"<{_pin_id}> " + name.replace("{", "(").replace("}", ")").replace("|", "/").replace("<", "").replace(">", "")

    for b in blocks.values():
        if b.id == "TOP":
            continue
        left = " | ".join(port_cell(n, p) for n, p in b.inputs) or " "
        right = " | ".join(port_cell(n, p) for n, p in b.outputs) or " "
        label = f"{{ {{{left}}} | {b.label} | {{{right}}} }}"
        lines.append(f'  {b.id} [label="{label}"];')

    top = blocks.get("TOP")
    if top and top.inputs:
        left = " | ".join(port_cell(n, p) for n, p in top.inputs)
        lines.append(f'  TOP_in [shape=record, style=bold, label="{{ {top_module} in | {{{left}}} }}"];')
    if top and top.outputs:
        right = " | ".join(port_cell(n, p) for n, p in top.outputs)
        lines.append(f'  TOP_out [shape=record, style=bold, label="{{ {{{right}}} | {top_module} out }}"];')

    top_input_pins = {p for _n, p in (top.inputs if top else [])}

    def resolve(block_id, pin_id):
        if block_id == "TOP":
            return f"TOP_in:{pin_id}" if pin_id in top_input_pins else f"TOP_out:{pin_id}"
        return f"{block_id}:{pin_id}"

    seen = set()
    for fb, fp, tb, tp in wires:
        edge = (resolve(fb, fp), resolve(tb, tp))
        if edge in seen:
            continue
        seen.add(edge)
        lines.append(f'  {edge[0]} -> {edge[1]};')

    lines.append("}")
    dot_src = "\n".join(lines)

    result = subprocess.run(
        ["dot", "-Tsvg", "-o", out_svg],
        input=dot_src, capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(dot_src)
        sys.stderr.write(result.stderr)
        raise SystemExit("error: graphviz 'dot' failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("top_module")
    ap.add_argument("output_svg")
    ap.add_argument("--rtl-lib", default="../rtl_lib",
                     help="path to rtl_lib (default: ../rtl_lib, i.e. run from firmware/fusesoc/)")
    ap.add_argument("--stub-dir", default="scripts/block_diagram_stubs",
                     help="directory of blackbox .sv stubs for vendor primitives")
    args = ap.parse_args()

    rtl_lib = os.path.abspath(args.rtl_lib)
    top_file = find_top_file(rtl_lib, args.top_module)
    rtl_dirs = find_rtl_dirs(rtl_lib)

    with tempfile.TemporaryDirectory() as workdir:
        json_path = run_verilator(args.top_module, top_file, rtl_dirs,
                                   os.path.abspath(args.stub_dir) if args.stub_dir else None,
                                   workdir)
        design = Design(json_path)
        blocks, wires = build_diagram(design, args.top_module)

    os.makedirs(os.path.dirname(os.path.abspath(args.output_svg)) or ".", exist_ok=True)
    render_dot(blocks, wires, args.top_module, args.output_svg)
    print(f"wrote {args.output_svg} ({len(blocks) - 1} blocks, {len(wires)} wires)")


if __name__ == "__main__":
    main()
