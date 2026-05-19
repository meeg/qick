#!/usr/bin/env python3
"""
Package QICK RTL into a Vivado IP (component.xml + xgui/).
Can be called standalone or via FuseSoC generator interface.

Usage:
    python3 ip_packager.py --ip-name <name> [options]
    python3 ip_packager.py --core-file <path/to/ip.core>
"""
import os
import sys
import glob
import argparse
import subprocess
import shutil
from pathlib import Path
from jinja2 import Environment, FileSystemLoader


def find_firmware_root(start: Path) -> Path:
    """Walk up from start until we find the firmware/ directory."""
    p = start.resolve()
    while p != p.parent:
        if (p / "ip").is_dir() and (p / "Hog").is_dir():
            return p
        p = p.parent
    raise RuntimeError("Could not find firmware root (directory with ip/ and Hog/)")


def collect_hdl_files(src_dir: Path) -> list:
    """Auto-discover RTL files, excluding testbenches and non-synthesizable content."""
    extensions = {".sv", ".v", ".vhd", ".vhdl"}

    exclude_dirs   = {"tb", "sim", "testbench"}
    exclude_prefix = ("tb_", "glbl")
    exclude_suffix = ("_tb.sv", "_tb.v", "_tb.vhd")
    exclude_exact  = {"glbl.v"}

    files = []
    for p in src_dir.rglob("*"):
        if not p.is_file():
            continue

        # exclude directories
        if any(part in exclude_dirs for part in p.relative_to(src_dir).parts):
            continue

        if p.suffix not in extensions:
            continue
        if p.name in exclude_exact:
            continue
        if any(p.name.startswith(x) for x in exclude_prefix):
            continue
        if any(p.name.endswith(x) for x in exclude_suffix):
            continue

        # use relative path
        files.append(str(p.relative_to(src_dir)))

    return files

def collect_xci_files(src_dir: Path) -> list:
    """Find Xilinx sub-IP .xci files, excluding testbench directories."""
    exclude_dirs = {"tb", "sim", "testbench"}
    xci = []
    for p in src_dir.rglob("*.xci"):
        # Skip if any parent directory is in exclude_dirs
        parts = p.relative_to(src_dir).parts
        if not any(part in exclude_dirs for part in parts[:-1]):
            xci.append(str(p.relative_to(src_dir)))
    return xci


def collect_ooc_xdc(src_dir: Path) -> list:
    """Find out-of-context XDC files."""
    return [p.name for p in src_dir.glob("*_ooc.xdc")]


def render_and_run(cfg: dict, script_dir: Path, dry_run: bool = False):
    """Render the TCL template and run Vivado in batch mode."""
    env = Environment(
        loader=FileSystemLoader(str(script_dir)),
        trim_blocks=True,
        lstrip_blocks=True,
    )
    template = env.get_template("package_ip.tcl.j2")
    tcl_script = Path("package_ip_run.tcl")
    template.stream(**cfg).dump(str(tcl_script))

    print(f"\n{'='*60}")
    print(f"  Packaging IP: {cfg['module_name']} v{cfg['version']}")
    print(f"  Source:       {cfg['src_dir']}")
    print(f"  Output:       {cfg['ip_dir']}/component.xml")
    print(f"{'='*60}\n")

    if dry_run:
        print(f"[dry-run] Would execute: vivado -mode batch -source {tcl_script}")
        print(f"[dry-run] TCL script written to: {tcl_script}")
        return

    rc = subprocess.call(["vivado", "-mode", "batch", "-source", str(tcl_script)])

    # Cleanup Vivado logs
    for pattern in ("vivado*.log", "vivado*.jou", ".Xil"):
        for f in glob.glob(pattern):
            try:
                if os.path.isdir(f):
                    shutil.rmtree(f)
                else:
                    os.remove(f)
            except Exception:
                pass

    tcl_script.unlink(missing_ok=True)

    if rc != 0:
        print(f"\nERROR: Vivado failed (exit code {rc})", file=sys.stderr)
        sys.exit(rc)

    print(f"\n✓ IP packaged successfully")
    print(f"  {cfg['ip_dir']}/component.xml")
    print(f"  {cfg['ip_dir']}/xgui/\n")
    print(f"Next steps:")
    print(f"  1. Commit: git add ../ip/{cfg['module_name']}/")
    print(f"  2. Recreate project: cd .. && ./Hog/Do CREATE <project>\n")


def run_standalone(args):
    script_dir   = Path(__file__).parent
    firmware_dir = find_firmware_root(script_dir)
    ip_name      = args.ip_name
    src_dir      = firmware_dir / "ip" / ip_name / "src"
    ip_dir       = firmware_dir / "ip" / ip_name

    if not src_dir.is_dir():
        print(f"ERROR: Source directory not found: {src_dir}", file=sys.stderr)
        sys.exit(1)

    hdl_files    = args.hdl_files or collect_hdl_files(src_dir)
    xci_files    = args.xci_files or collect_xci_files(src_dir)
    ooc_xdc      = args.ooc_xdc   or collect_ooc_xdc(src_dir)

    cfg = {
        "module_name":   args.module_name or ip_name,
        "version":       args.version,
        "vendor":        args.vendor,
        "library":       args.library,
        "display_name":  args.display_name or ip_name,
        "description":   args.description,
        "part":          args.part,
        "ip_dir":        str(ip_dir.resolve()),
        "src_dir":       str(src_dir.resolve()),
        "hdl_files":     hdl_files,
        "xci_files":     xci_files,
        "ooc_xdc_files": ooc_xdc,
        "clock_domains": {},
    }
    
    if args.module_name:
      top = args.module_name
    else:
      top = ip_name

    # useful validatio
    top_file_candidates = [f for f in hdl_files if Path(f).stem == top]
    if not top_file_candidates:
      print(f"WARNING: No HDL file matches top module '{top}'")

    render_and_run(cfg, script_dir, dry_run=args.dry_run)


def main():
    parser = argparse.ArgumentParser(
        description="Package QICK RTL into a Vivado IP (component.xml + xgui/)"
    )
    parser.add_argument("--ip-name",      required=True,
                        help="IP directory name under ip/ (e.g. qick_processor)")
    parser.add_argument("--module-name",  default=None,
                        help="Top-level module name if different from ip-name")
    parser.add_argument("--version",      default="1.0",
                        help="IP version string (default: 1.0)")
    parser.add_argument("--vendor",       default="qick")
    parser.add_argument("--library",      default="ip")
    parser.add_argument("--display-name", default=None,
                        help="Human-readable name in Vivado catalog")
    parser.add_argument("--description",  default="")
    parser.add_argument("--part",         default="xczu49dr-ffvf1760-2-e",
                        help="Target FPGA part for IP inference")
    parser.add_argument("--hdl-files",    nargs="*", default=None,
                        help="RTL files to include (auto-discovered if omitted)")
    parser.add_argument("--xci-files",    nargs="*", default=None,
                        help="Xilinx sub-IP .xci files (auto-discovered if omitted)")
    parser.add_argument("--ooc-xdc",      nargs="*", default=None,
                        help="Out-of-context XDC files (auto-discovered if omitted)")
    parser.add_argument("--dry-run",      action="store_true",
                        help="Generate TCL but do not run Vivado")

    args = parser.parse_args()
    run_standalone(args)


# ── FuseSoC Generator interface (kept for future compatibility) ──────────────
try:
    from fusesoc.capi2.generator import Generator

    class IPPackagerGenerator(Generator):
        def run(self):
            script_dir = Path(__file__).parent
            cfg = self.config
            files_root = Path(self.files_root)
            src_dir    = files_root / "hdl"
            ip_dir     = src_dir.parent

            render_cfg = {
                "module_name":   cfg.get("module_name",  "my_ip"),
                "version":       cfg.get("version",       "1.0"),
                "vendor":        cfg.get("vendor",        "qick"),
                "library":       cfg.get("library",       "ip"),
                "display_name":  cfg.get("display_name",  cfg.get("module_name", "my_ip")),
                "description":   cfg.get("description",   ""),
                "part":          cfg.get("part",          "xczu49dr-ffvf1760-2-e"),
                "ip_dir":        str(ip_dir.resolve()),
                "src_dir":       str(src_dir.resolve()),
                "hdl_files":     cfg.get("hdl_files",     []),
                "xci_files":     cfg.get("xci_files",     []),
                "ooc_xdc_files": cfg.get("ooc_xdc_files", []),
                "clock_domains": cfg.get("clock_domains", {}),
            }
            render_and_run(render_cfg, script_dir)
            self.add_files([])

except ImportError:
    pass


if __name__ == "__main__":
    main()
