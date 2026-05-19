#!/usr/bin/env python3
"""
Package QICK RTL into a Vivado IP (component.xml + xgui/).
Can be called standalone or via FuseSoC generator interface.

Supports:
    - Automatic collection of RTL from dependencies
    - Flattened source tree in ip/<ip_name>/src/
    - Library resolution from fusesoc/cores/lib/

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


def find_fusesoc_cores_root(firmware_root: Path) -> Path:
    """Find the fusesoc/cores directory."""
    return firmware_root / "fusesoc" / "cores"


def collect_dependencies(core_name: str, cores_root: Path, collected: set = None) -> set:
    """
    Recursively collect all dependency cores for a given core.
    Returns a set of core names (e.g., 'qick:axi:axil_slv').
    """
    if collected is None:
        collected = set()
    
    core_file = find_core_file(core_name, cores_root)
    if not core_file:
        return collected
    
    # Parse core file to find dependencies
    import yaml
    with open(core_file) as f:
        core_data = yaml.safe_load(f)
    
    # Check for dependencies in CAPI2 format
    if 'depend' in core_data:
        for dep in core_data['depend']:
            if dep not in collected:
                collected.add(dep)
                collect_dependencies(dep, cores_root, collected)
    
    return collected


def find_core_file(core_name: str, cores_root: Path) -> Path | None:
    """
    Find the .core file for a given core name.
    Supports names like 'qick:ip:xcom', 'qick:axi:axil_slv', etc.
    """
    # Convert namespace to path: qick:ip:xcom -> ip/xcom
    parts = core_name.split(':')
    if len(parts) >= 3:
        # qick:ip:xcom -> ip/xcom
        # qick:axi:axil_slv -> lib/axi/axil_slv
        if parts[1] == 'ip':
            core_path = cores_root / 'ip' / parts[2]
        else:
            core_path = cores_root / 'lib' / parts[1] / parts[2]
    else:
        # Fallback: search
        core_path = cores_root / core_name.replace(':', '_')
    
    core_file = core_path / f"{core_path.name}.core"
    if core_file.exists():
        return core_file
    
    # Search recursively
    for core_file in cores_root.rglob(f"*.core"):
        try:
            import yaml
            with open(core_file) as f:
                data = yaml.safe_load(f)
                if data.get('name') == core_name:
                    return core_file
        except:
            continue
    
    return None


def get_rtl_sources_from_core(core_name: str, cores_root: Path) -> list:
    """
    Get all RTL source files from a core and its dependencies.
    Returns list of (source_path, destination_filename) tuples.
    """
    sources = []
    
    # Find the core directory
    parts = core_name.split(':')
    if len(parts) >= 3:
        if parts[1] == 'ip':
            core_dir = cores_root / 'ip' / parts[2]
        else:
            core_dir = cores_root / 'lib' / parts[1] / parts[2]
    else:
        core_dir = cores_root / core_name.replace(':', '_')
    
    # Look for hdl symlink or directory
    hdl_dir = core_dir / 'hdl'
    if not hdl_dir.exists():
        hdl_dir = core_dir / 'src'
    
    if hdl_dir.exists():
        # Collect all RTL files
        for ext in ['.sv', '.v', '.vhd', '.vhdl']:
            for f in hdl_dir.glob(f"*{ext}"):
                if not f.name.startswith('tb_') and 'test' not in str(f):
                    # Use filename as destination (flatten)
                    sources.append((f, f.name))
    
    return sources


def resolve_dependencies(core_name: str, cores_root: Path) -> dict:
    """
    Resolve all dependencies for a core and return collected RTL sources.
    Returns dict mapping source_path -> destination_filename.
    """
    all_sources = {}
    
    # Get the main core's sources
    main_sources = get_rtl_sources_from_core(core_name, cores_root)
    for src, dst in main_sources:
        all_sources[str(src)] = dst
    
    # Get dependencies
    deps = collect_dependencies(core_name, cores_root)
    for dep in deps:
        dep_sources = get_rtl_sources_from_core(dep, cores_root)
        for src, dst in dep_sources:
            if dst not in all_sources.values():
                all_sources[str(src)] = dst
    
    return all_sources


def collect_hdl_files(src_dir: Path) -> list:
    """Auto-discover RTL files, excluding testbenches and non-synthesizable content."""
    extensions = {".sv", ".v", ".vhd", ".vhdl"}

    exclude_dirs   = {"tb", "sim", "testbench", "tests"}
    exclude_prefix = ("tb_", "glbl")
    exclude_suffix = ("_tb.sv", "_tb.v", "_tb.vhd")
    exclude_exact  = {"glbl.v"}

    files = []
    for p in src_dir.rglob("*"):
        if not p.is_file():
            continue

        # exclude directories
        rel_path = p.relative_to(src_dir)
        if any(part in exclude_dirs for part in rel_path.parts):
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
        files.append(str(rel_path))

    return files


def collect_xci_files(src_dir: Path) -> list:
    """Find Xilinx sub-IP .xci files, excluding testbench directories."""
    exclude_dirs = {"tb", "sim", "testbench", "tests"}
    xci = []
    for p in src_dir.rglob("*.xci"):
        parts = p.relative_to(src_dir).parts
        if not any(part in exclude_dirs for part in parts[:-1]):
            xci.append(str(p.relative_to(src_dir)))
    return xci


def collect_ooc_xdc(src_dir: Path) -> list:
    """Find out-of-context XDC files."""
    return [p.name for p in src_dir.glob("*_ooc.xdc")]


def copy_dependency_sources(ip_dir: Path, sources: dict):
    """
    Copy all resolved dependency sources to ip/<ip_name>/src/
    Returns list of copied filenames (relative to src_dir).
    """
    src_dir = ip_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    
    copied_files = []
    for src_path, dst_name in sources.items():
        src_path = Path(src_path)
        dst_path = src_dir / dst_name
        
        # Copy file, skip if already exists and identical
        if dst_path.exists():
            with open(src_path, 'rb') as f1, open(dst_path, 'rb') as f2:
                if f1.read() == f2.read():
                    copied_files.append(dst_name)
                    continue
        
        shutil.copy2(src_path, dst_path)
        copied_files.append(dst_name)
        print(f"  Copied: {src_path.name} -> {dst_path}")
    
    return copied_files


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
    for pattern in ("vivado*.log", "vivado*.jou", ".Xil", ".*_pid*"):
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
    print(f"  1. Commit: git add {cfg['ip_dir']}/")
    print(f"  2. Recreate project: cd .. && ./Hog/Do CREATE <project>\n")


def run_standalone(args):
    script_dir   = Path(__file__).parent
    firmware_dir = find_firmware_root(script_dir)
    cores_root   = find_fusesoc_cores_root(firmware_dir)
    ip_name      = args.ip_name
    src_dir      = firmware_dir / "ip" / ip_name / "src"
    ip_dir       = firmware_dir / "ip" / ip_name

    # Resolve dependencies and copy sources
    if args.resolve_deps:
        print(f"Resolving dependencies for {ip_name}...")
        core_name = f"qick:ip:{ip_name}"
        sources = resolve_dependencies(core_name, cores_root)
        
        if sources:
            print(f"Found {len(sources)} source files from dependencies:")
            copied = copy_dependency_sources(ip_dir, sources)
            print(f"Copied {len(copied)} files to {src_dir}")
    
    # Collect all RTL files from src_dir (including copied dependencies)
    if not src_dir.is_dir():
        print(f"ERROR: Source directory not found: {src_dir}", file=sys.stderr)
        sys.exit(1)

    hdl_files    = args.hdl_files or collect_hdl_files(src_dir)
    xci_files    = args.xci_files or collect_xci_files(src_dir)
    ooc_xdc      = args.ooc_xdc   or collect_ooc_xdc(src_dir)

    if not hdl_files:
        print(f"ERROR: No RTL files found in {src_dir}", file=sys.stderr)
        sys.exit(1)

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
    
    top = args.module_name or ip_name
    top_file_candidates = [f for f in hdl_files if Path(f).stem == top]
    if not top_file_candidates:
        print(f"WARNING: No HDL file matches top module '{top}'")
        print(f"  Available files: {[Path(f).stem for f in hdl_files]}")

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
    parser.add_argument("--resolve-deps", action="store_true",
                        help="Resolve and copy dependencies from fusesoc/cores/")
    parser.add_argument("--dry-run",      action="store_true",
                        help="Generate TCL but do not run Vivado")

    args = parser.parse_args()
    run_standalone(args)


# ── FuseSoC Generator interface ──────────────────────────────
try:
    from fusesoc.capi2.generator import Generator

    class IPPackagerGenerator(Generator):
        def run(self):
            script_dir = Path(__file__).parent
            firmware_dir = find_firmware_root(script_dir)
            cores_root = find_fusesoc_cores_root(firmware_dir)
            
            cfg = self.config
            files_root = Path(self.files_root)
            core_name = cfg.get("name", files_root.name)
            
            # Resolve dependencies and copy sources
            if cfg.get("resolve_deps", True):
                sources = resolve_dependencies(core_name, cores_root)
                ip_dir = firmware_dir / "ip" / files_root.name
                copy_dependency_sources(ip_dir, sources)
            
            # Use the core's hdl directory as source
            src_dir = files_root / "hdl"
            ip_dir = firmware_dir / "ip" / files_root.name
            
            render_cfg = {
                "module_name":   cfg.get("module_name",  files_root.name),
                "version":       cfg.get("version",      "1.0"),
                "vendor":        cfg.get("vendor",       "qick"),
                "library":       cfg.get("library",      "ip"),
                "display_name":  cfg.get("display_name", cfg.get("module_name", files_root.name)),
                "description":   cfg.get("description",  ""),
                "part":          cfg.get("part",         "xczu49dr-ffvf1760-2-e"),
                "ip_dir":        str(ip_dir.resolve()),
                "src_dir":       str(src_dir.resolve()),
                "hdl_files":     cfg.get("hdl_files",    []),
                "xci_files":     cfg.get("xci_files",    []),
                "ooc_xdc_files": cfg.get("ooc_xdc_files", []),
                "clock_domains": cfg.get("clock_domains", {}),
            }
            
            # Auto-discover hdl_files if not specified
            if not render_cfg["hdl_files"] and src_dir.exists():
                render_cfg["hdl_files"] = collect_hdl_files(src_dir)
            
            render_and_run(render_cfg, script_dir)
            self.add_files([])

except ImportError:
    pass


if __name__ == "__main__":
    main()
