#!/usr/bin/env python3
"""
Package QICK RTL into a Vivado IP (component.xml + xgui/).
Automatically resolves all dependencies recursively from the .core file
and copies all RTL sources from rtl_lib/ to ip/<ip_name>/src/
Usage:
    python3 ip_packager.py --ip-name xcom
"""
import os
import sys
import glob
import argparse
import subprocess
import shutil
from typing import Optional
from pathlib import Path
from jinja2 import Environment, FileSystemLoader

def get_core_description(core_name, cores_root):
    """Read the description field from the IP's .core file."""
    core_file = find_core_file(core_name, cores_root)
    if not core_file:
        return None
    import yaml
    try:
        with open(core_file) as f:
            data = yaml.safe_load(f)
        return data.get('description', None)
    except Exception:
        return None
    
def find_firmware_root(start: Path) -> Path:
    """Walk up from start until we find the firmware/ directory."""
    p = start.resolve()
    while p != p.parent:
        if (p / "ip").is_dir() and (p / "common_ip_files").is_dir():
            return p
        p = p.parent
    raise RuntimeError("Could not find firmware root (directory with ip/ and common_ip_files/)")

def get_core_version(core_name, cores_root, default="1.0"):
    """Read version (major.minor) from the IP's .core 'name:' field.
    The .core name is like 'qick:ip:mr_buffer_et:1.2.0'; Vivado uses major.minor
    (e.g. 1.2) for the packaged VLNV, so we truncate to two components."""
    core_file = find_core_file(core_name, cores_root)
    if core_file is None:
        return default
    try:
        import yaml
        with open(core_file) as f:
            data = yaml.safe_load(f)
        full = data.get('name', '')
        parts = full.split(':')
        if len(parts) >= 4 and parts[3]:
            return '.'.join(parts[3].split('.')[:2])  # 1.2.0 -> 1.2
    except Exception:
        pass
    return default


def parse_core_name(core_name: str):
    """Parse core name like 'qick:ip:xcom' into (vendor, category, name)."""
    parts = core_name.split(':')
    if len(parts) >= 3:
        return parts[0], parts[1], parts[2]
    return None, None, None

def find_core_file(core_name: str, cores_root: Path) -> Optional[Path]:
    """
    Find the .core file for a given core name.
    Supports names like 'qick:ip:xcom', 'qick:axi:axil_slv', etc.
    """
    vendor, category, name = parse_core_name(core_name)
    if category == 'ip':
        core_path = cores_root / 'ip' / name
    elif category == 'common':
        core_path = cores_root / 'common' / name
    elif category == 'pkg':
        core_path = cores_root / 'pkg' / name
    elif category:
        core_path = cores_root / 'lib' / category / name
    else:
        return None
    core_file = core_path / f"{name}.core"
    if core_file.exists():
        return core_file
    # Search recursively as fallback
    for core_file in cores_root.rglob("*.core"):
        try:
            import yaml
            with open(core_file) as f:
                data = yaml.safe_load(f)
                if data.get('name') == core_name:
                    return core_file
        except:
            continue
    return None

def read_core_dependencies_recursive(core_name: str, cores_root: Path, visited: set = None) -> set:
    """
    Recursively read all dependencies from .core file (DFS).
    Returns a set of all dependency core names.
    """
    if visited is None:
        visited = set()
    if core_name in visited:
        return visited
    visited.add(core_name)
    core_file = find_core_file(core_name, cores_root)
    if not core_file:
        # Skip missing core files (like sim_base, lint, etc. - they don't have RTL)
        return visited
    import yaml
    try:
        with open(core_file) as f:
            core_data = yaml.safe_load(f)
    except Exception:
        return visited
    # Check for dependencies in filesets
    if 'filesets' in core_data:
        for fileset_name, fileset in core_data['filesets'].items():
            if isinstance(fileset, dict) and 'depend' in fileset:
                for dep in fileset['depend']:
                    if dep not in visited:
                        read_core_dependencies_recursive(dep, cores_root, visited)
    return visited

def resolve_rtl_from_dependency(dep_name: str, rtl_lib_root: Path) -> Optional[Path]:
    """
    Resolve RTL file path for a dependency from rtl_lib/.
    Example: qick:axi:xcom_axil_slv -> rtl_lib/axi/xcom_axil_slv.sv
    """
    vendor, category, name = parse_core_name(dep_name)
    if not category:
        return None
    # Skip common and pkg categories (they don't have RTL)
    if category in ['common', 'pkg']:
        return None
    # Look for the RTL file in rtl_lib/<category>/<name>.sv
    rtl_file = rtl_lib_root / category / f"{name}.sv"
    if rtl_file.exists():
        return rtl_file
    # Also try with .v extension
    rtl_file = rtl_lib_root / category / f"{name}.v"
    if rtl_file.exists():
        return rtl_file
    return None

def collect_all_rtl_sources(ip_core_name: str, cores_root: Path, rtl_lib_root: Path) -> dict:
    """
    Collect all RTL sources for an IP core and its recursive dependencies.
    Returns dict mapping source_path -> destination_filename.
    """
    all_sources = {}
    xci_sources = {}
    # 1. Get all dependencies recursively
    print(f"\n  Resolving dependencies recursively...")
    deps = read_core_dependencies_recursive(ip_core_name, cores_root)
    # Remove the IP itself from dependencies
    deps.discard(ip_core_name)
    # Filter out common/pkg dependencies (they don't have RTL)
    rtl_deps = [d for d in deps
                if not d.startswith('qick:common:')
                and not d.startswith('qick:pkg:')
                and not d.endswith('_model')                    # ← behavioral sim models
                and ':dds_compiler_model' not in d]             # (defensive, if name get version)
    print(f"  Found {len(rtl_deps)} RTL dependency(ies):")
    for dep in sorted(rtl_deps):
        print(f"    - {dep}")
    # 2. Resolve RTL for each dependency
    print(f"\n  Resolving RTL files from rtl_lib/...")
    for dep in rtl_deps:
        vendor, category, name = parse_core_name(dep)
        # If a Xilinx .xci exists for this name, it's a Xilinx IP:
        # use the .xci for synthesis, skip the .sv sim model.
        xci = rtl_lib_root / 'xci' / name / f"{name}.xci"
        if xci.exists():
            xci_sources[str(xci)] = f"{name}/{name}.xci"
            print(f"    {dep} -> {name}/{name}.xci (Xilinx IP, sim model skipped)")
            continue
        rtl_file = resolve_rtl_from_dependency(dep, rtl_lib_root)
        if rtl_file and rtl_file.exists():
            if rtl_file.name not in all_sources.values():
                all_sources[str(rtl_file)] = rtl_file.name
                print(f"    {dep} -> {rtl_file.name}")
        else:
            print(f"    !  RTL not found for: {dep}")
    # 3. Get the main IP RTL
    vendor, category, name = parse_core_name(ip_core_name)
    # Look for main IP RTL in various locations
    possible_locations = [
        rtl_lib_root / 'ip' / f"{name}.sv",           # rtl_lib/ip/xcom.sv
        rtl_lib_root / 'ip' / name / f"{name}.sv",    # rtl_lib/ip/xcom/xcom.sv
        rtl_lib_root / f"{name}.sv",                   # rtl_lib/xcom.sv
    ]
    
    print(f"\n  Looking for main IP RTL...")
    main_rtl = None
    for loc in possible_locations:
        if loc.exists():
            main_rtl = loc
            print(f"    Found: {loc}")
            break
    if main_rtl:
        if main_rtl.name not in all_sources.values():
            all_sources[str(main_rtl)] = main_rtl.name
    else:
        print(f"    ! Main IP RTL not found in any expected location")
        print(f"    Expected: {rtl_lib_root}/ip/{name}.sv")
    
    # 4. Collect the IP's XDC constraints from rtl_lib/ip/.
    print(f"\n  Looking for IP constraints (.xdc)...")
    for xdc in sorted((rtl_lib_root / 'constraints').glob(f"{name}*.xdc")):
        if xdc.name not in all_sources.values():
            all_sources[str(xdc)] = xdc.name
            print(f"    Found: {xdc.name}")

    return all_sources, xci_sources

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
        files.append(str(rel_path))
    return sorted(files)

def collect_xci_files(src_dir: Path) -> list:
    """Find Xilinx sub-IP .xci files, excluding testbench directories."""
    exclude_dirs = {"tb", "sim", "testbench", "tests"}
    xci = []
    for p in src_dir.rglob("*.xci"):
        parts = p.relative_to(src_dir).parts
        if not any(part in exclude_dirs for part in parts[:-1]):
            xci.append(str(p.relative_to(src_dir)))
    return xci

def collect_xdc(src_dir: Path) -> list:
    """Find functional (scoped) XDC files, excluding OOC and testbench dirs."""
    exclude_dirs = {"tb", "sim", "testbench", "tests"}
    xdc = []
    for p in src_dir.glob("*.xdc"):
        if p.name.endswith("_ooc.xdc"):
            continue   # OOC handled separately
        xdc.append(p.name)
    return sorted(xdc)

def collect_ooc_xdc(src_dir: Path) -> list:
    """Find out-of-context XDC files."""
    return [p.name for p in src_dir.glob("*_ooc.xdc")]

def find_logo_file(firmware_dir: Path) -> Optional[Path]:
    """
    Find the logo file in common_ip_files/ip_logos/
    Returns None if not found.
    """
    logo_path = firmware_dir / "common_ip_files" / "ip_logos" / "logoQICK_128x128.png"
    if logo_path.exists():
        return logo_path
    return None

def copy_rtl_sources(ip_dir, sources, xci_sources=None):
    """
    Copy all resolved RTL sources to ip/<ip_name>/src/
    """
    src_dir = ip_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    # Regular RTL files.
    for src_path, dst_name in sources.items():
        src_path = Path(src_path)
        if not src_path.exists():
            print(f"    !  Source not found: {src_path}")
            continue
        shutil.copy2(src_path, src_dir / dst_name)
        copied.append(dst_name)
        print(f"    Copied: {src_path.name}")
    # XCI sub-IPs (into their own subdirectory).
    if xci_sources:
        for src_path, dst_rel in xci_sources.items():
            dst_path = src_dir / dst_rel
            dst_path.parent.mkdir(parents=True, exist_ok=True)   # crea src/<name>/
            shutil.copy2(src_path, dst_path)
            copied.append(dst_rel)
            print(f"    Copied XCI: {dst_rel}")
    return copied

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
    try:
        rc = subprocess.call(["vivado", "-mode", "batch", "-source", str(tcl_script)])
    except FileNotFoundError:
        print("\n Vivado not found in PATH. Make sure Vivado is installed and sourced.")
        print("   source /path/to/Xilinx/Vivado/2023.1/settings64.sh")
        sys.exit(1)
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
        print(f"\n Vivado failed with exit code {rc}", file=sys.stderr)
        sys.exit(rc)
    print(f"\n IP packaged successfully")
    print(f"  {cfg['ip_dir']}/component.xml")
    print(f"  {cfg['ip_dir']}/xgui/\n")
    print(f"Next steps:")
    print(f"  1. Commit: git add {cfg['ip_dir']}/")
    print(f"  2. Recreate project: cd .. && ./Hog/Do CREATE <project>\n")

def get_relative_logo_path(ip_dir: Path, firmware_dir: Path) -> str:
    """Calculate relative path from IP directory to common logo"""
    logo_abs = firmware_dir / "common_ip_files" / "ip_logos" / "logoQICK_128x128.png"
    if not logo_abs.exists():
        return None
    # Calculate relative path
    rel_path = os.path.relpath(logo_abs, ip_dir)
    return rel_path

def add_logo_to_component_xml(ip_dir: Path, firmware_dir: Path) -> bool:
    """
    Add logo reference to component.xml after IP packaging.
    This completely bypasses Vivado's restrictions.
    """
    import xml.etree.ElementTree as ET
    import re

    component_xml = ip_dir / "component.xml"
    if not component_xml.exists():
        print(f"  WARNING: component.xml not found")
        return False

    # Logo path relative to IP directory
    logo_rel_path = "../../common_ip_files/ip_logos/logoQICK_128x128.png"
    logo_abs = firmware_dir / "common_ip_files" / "ip_logos" / "logoQICK_128x128.png"

    if not logo_abs.exists():
        print(f"  WARNING: Logo file not found at {logo_abs}")
        return False

    try:
        # Read the file
        with open(component_xml, 'r') as f:
            content = f.read()

        # Check if logo already exists
        if 'xilinx_utilityxitfiles_view_fileset' in content and 'LOGO' in content:
            print(f"  Logo already present in component.xml")
            return True

        # Find the closing </spirit:fileSets> tag
        file_sets_close = '</spirit:fileSets>'
        if file_sets_close not in content:
            # Try without namespace
            file_sets_close = '</fileSets>'

        # Create the logo fileSet XML
        logo_xml = '''    <spirit:fileSet>
      <spirit:name>xilinx_utilityxitfiles_view_fileset</spirit:name>
      <spirit:file>
        <spirit:name>''' + logo_rel_path + '''</spirit:name>
        <spirit:userFileType>LOGO</spirit:userFileType>
      </spirit:file>
    </spirit:fileSet>
  </spirit:fileSets>'''

        # Replace the closing tag with the new content
        new_content = content.replace(file_sets_close, logo_xml)

        # Write back
        with open(component_xml, 'w') as f:
            f.write(new_content)

        print(f"  Logo added to component.xml: {logo_rel_path}")
        return True

    except Exception as e:
        print(f"  ERROR: {e}")
        return False

def run_standalone(args):
    script_dir = Path(__file__).parent
    firmware_dir = find_firmware_root(script_dir)
    cores_root = firmware_dir / "fusesoc" / "cores"
    rtl_lib_root = firmware_dir / "rtl_lib"
    ip_name = args.ip_name
    ip_dir = firmware_dir / "ip" / ip_name
    src_dir = ip_dir / "src"

    # Core name for resolution
    core_name = f"qick:ip:{ip_name}"
    print(f"   Packaging IP: {core_name}")
    print(f"   Firmware: {firmware_dir}")
    print(f"   RTL lib:  {rtl_lib_root}")
    print(f"   Cores:    {cores_root}")
    # ALWAYS resolve dependencies recursively
    print(f"\n Resolving dependencies from .core file...")
    sources, xci_sources = collect_all_rtl_sources(core_name, cores_root, rtl_lib_root)
    if sources:
        print(f"\n  Total RTL files found: {len(sources)}")
        copied = copy_rtl_sources(ip_dir, sources, xci_sources)
        print(f"\n  Copied {len(copied)} file(s) to {src_dir}")
    else:
        print(f"  !  No RTL sources found for {core_name}")
    # Verify source directory exists
    if not src_dir.is_dir():
        print(f" Source directory not found: {src_dir}", file=sys.stderr)
        sys.exit(1)
    # Collect RTL files from src_dir
    hdl_files = args.hdl_files or collect_hdl_files(src_dir)
    xci_files = args.xci_files or collect_xci_files(src_dir)
    ooc_xdc = args.ooc_xdc or collect_ooc_xdc(src_dir)
    xdc_files = collect_xdc(src_dir)
    if not hdl_files:
        print(f" No RTL files found in {src_dir}", file=sys.stderr)
        sys.exit(1)
    print(f"\n Found {len(hdl_files)} RTL file(s) to package:")
    for f in hdl_files[:5]:
        print(f"     - {f}")
    if len(hdl_files) > 5:
        print(f"     ... and {len(hdl_files) - 5} more")
    logo_path = None
    if not args.no_logo:
        logo_path = find_logo_file(firmware_dir)
        if logo_path:
            print(f"\n  Logo found: {logo_path}")
        else:
            print(f"\n  ! Logo not found: firmware/common_ip_files/ip_logos/logoQICK_128x128.png")
            if not args.no_logo_warning:
                print("    Use --no-logo to suppress this warning")

    #logo_rel_path = get_relative_logo_path(ip_dir, firmware_dir)
    logo_rel_path = "../../common_ip_files/ip_logos/logoQICK_128x128.png" if logo_path else None

    # Description: CLI arg > .core description > generic default.
    description = args.description
    if not description:
       description = get_core_description(core_name, cores_root)
    if not description:
       description = f"{ip_name} IP core"
        
    # Prepare configuration for template
    cfg = {
        "module_name": args.module_name or ip_name,
        "version": (args.version or get_core_version(f"{args.vendor}:{args.library}:{args.ip_name}", cores_root)),
        "vendor": args.vendor,
        "library": args.library,
        "display_name": args.display_name or ip_name,
        "description": description,
        "part": args.part,
        "ip_dir": str(ip_dir.resolve()),
        "src_dir": str(src_dir.resolve()),
        "hdl_files": hdl_files,
        "xci_files": xci_files,
        "xdc_files": xdc_files,
        "ooc_xdc_files": ooc_xdc,
        "clock_domains": {},
        "logo_relative_path": logo_rel_path,
        "has_logo": logo_rel_path is not None,
    }
    render_and_run(cfg, script_dir, dry_run=args.dry_run)
    # After packaging, add logo to component.xml (if needed)
    if not args.no_logo:
        add_logo_to_component_xml(ip_dir, firmware_dir)

def main():
    parser = argparse.ArgumentParser(
        description="Package QICK RTL into a Vivado IP (component.xml + xgui/)"
    )
    parser.add_argument("--ip-name", required=True,
                        help="IP directory name under ip/ (e.g., xcom)")
    parser.add_argument("--module-name", default=None,
                        help="Top-level module name if different from ip-name")
    parser.add_argument("--version", default=None,
                        help="IP version override; if omitted, taken from the .core (major.minor)")
    parser.add_argument("--vendor", default="qick",
                        help="Vendor name (default: qick)")
    parser.add_argument("--library", default="ip",
                        help="Library name (default: ip)")
    parser.add_argument("--display-name", default=None,
                        help="Human-readable name in Vivado catalog")
    parser.add_argument("--description", default=None,
                        help="IP description (fallback: read from .core or default to '<ip-name> IP core')")
    parser.add_argument("--part", default="xczu49dr-ffvf1760-2-e",
                        help="Target FPGA part for IP inference")
    parser.add_argument("--hdl-files", nargs="*", default=None,
                        help="RTL files to include (auto-discovered if omitted)")
    parser.add_argument("--xci-files", nargs="*", default=None,
                        help="Xilinx sub-IP .xci files (auto-discovered if omitted)")
    parser.add_argument("--ooc-xdc", nargs="*", default=None,
                        help="Out-of-context XDC files (auto-discovered if omitted)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Generate TCL but do not run Vivado")
    parser.add_argument("--no-logo", action="store_true",
                        help="Skip adding logo to component.xml")
    parser.add_argument("--no-logo-warning", action="store_true",
                        help="Suppress warning when logo not found")
    args = parser.parse_args()
    run_standalone(args)

if __name__ == "__main__":
    main()
