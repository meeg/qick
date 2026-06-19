#!/usr/bin/env python3

from systemrdl import RDLCompiler, RDLCompileError
from peakrdl_regblock import RegblockExporter
from peakrdl_regblock.udps import ALL_UDPS
from peakrdl_regblock.cpuif.axi4lite import AXI4Lite_Cpuif
from peakrdl_python import PythonExporter
import os
import sys
import shutil

# Import opcional para HTML
try:
    from peakrdl_html import HTMLExporter
    HAS_HTML = True
except ImportError:
    HAS_HTML = False

# Import opcional para headers C
try:
    from ralbot.headergen import headerGenExporter
    HAS_RALBOT = True
except ImportError:
    HAS_RALBOT = False
    # Intentar alternativa
    try:
        from peakrdl_cheader import CHeaderExporter
        HAS_CHEADER = True
    except ImportError:
        HAS_CHEADER = False


def hdl_gen(output_dir, input_files):
    """Generate SystemVerilog AXI4-Lite slave from RDL."""
    rdlc = RDLCompiler()
    for udp in ALL_UDPS:
        rdlc.register_udp(udp)
    try:
        for input_file in input_files:
            rdlc.compile_file(input_file)
        root = rdlc.elaborate()
    except RDLCompileError:
        sys.exit(1)

    exporter = RegblockExporter()
    exporter.export(
        root, output_dir,
        cpuif_cls=AXI4Lite_Cpuif
    )
    print(f"  ✓ SystemVerilog generated in {output_dir}")


def html_gen(output_dir, input_files):
    """Generate HTML documentation from RDL."""
    if not HAS_HTML:
        print("  ⚠ peakrdl-html not installed, skipping HTML generation")
        return
        
    rdlc = RDLCompiler()
    try:
        for input_file in input_files:
            rdlc.compile_file(input_file)
        root = rdlc.elaborate()
    except RDLCompileError:
        sys.exit(1)

    exporter = HTMLExporter()
    exporter.export(root, output_dir)
    print(f"  ✓ HTML documentation generated in {output_dir}")


def c_header_gen(output_dir, input_files, top_level):
    """Generate C header from RDL."""
    if HAS_RALBOT:
        rdlc = RDLCompiler()
        try:
            for input_file in input_files:
                rdlc.compile_file(input_file)
                filename = os.path.basename(input_file)
                filename = os.path.splitext(filename)[0]
                filename = output_dir + "/" + filename
                root = rdlc.elaborate()
                exporter = headerGenExporter(languages='c')
                exporter.export(root, filename, top_level)
            print(f"  ✓ C header generated")
        except RDLCompileError:
            sys.exit(1)
    elif HAS_CHEADER:
        print("  ⚠ Using peakrdl-cheader instead of ralbot")
        # Implementar con peakrdl-cheader si es necesario
    else:
        print("  ⚠ No C header generator available (ralbot/peakrdl-cheader not installed)")


def verilog_header_gen(output_dir, input_files, top_level):
    """Generate Verilog header from RDL."""
    if HAS_RALBOT:
        rdlc = RDLCompiler()
        try:
            for input_file in input_files:
                rdlc.compile_file(input_file)
                filename = os.path.basename(input_file)
                filename = os.path.splitext(filename)[0]
                filename = output_dir + "/" + filename
                root = rdlc.elaborate()
                exporter = headerGenExporter(languages='verilog')
                exporter.export(root, filename, top_level)
            print(f"  ✓ Verilog header generated")
        except RDLCompileError:
            sys.exit(1)
    else:
        print("  ⚠ No Verilog header generator available (ralbot not installed)")


def python_header_gen(output_dir, input_files, top_level):
    """
    Generate Python register package from SystemRDL files.
    Output goes to output_dir/<basename>_pkg/ (clean directory name).
    """
    rdlc = RDLCompiler()
    try:
        for input_file in input_files:
            rdlc.compile_file(input_file)
            filename = os.path.basename(input_file)
            basename = os.path.splitext(filename)[0]
            
            # Usar un nombre de directorio limpio
            pkg_dir = os.path.join(output_dir, basename + "_pkg")
            
            # Limpiar directorio anterior si existe
            if os.path.exists(pkg_dir):
                shutil.rmtree(pkg_dir)
            
            # Crear directorio temporal para la generación
            tmp_dir = os.path.join(output_dir, basename + "_tmp")
            if os.path.exists(tmp_dir):
                shutil.rmtree(tmp_dir)
            
            root = rdlc.elaborate()
            
            # Generar en directorio temporal
            exporter = PythonExporter()
            exporter.export(node=root, path=tmp_dir)
            
            # Crear el directorio de salida limpio
            os.makedirs(pkg_dir, exist_ok=True)
            
            # Mover el contenido generado al directorio limpio
            # El exportador puede crear estructura: tmp_dir/$root/... o tmp_dir/...
            for item in os.listdir(tmp_dir):
                item_path = os.path.join(tmp_dir, item)
                if os.path.isdir(item_path):
                    # Si es un directorio, copiar su contenido
                    for sub_item in os.listdir(item_path):
                        sub_path = os.path.join(item_path, sub_item)
                        dst_path = os.path.join(pkg_dir, sub_item)
                        if os.path.isdir(sub_path):
                            if not os.path.exists(dst_path):
                                shutil.copytree(sub_path, dst_path)
                            else:
                                # Merge directorios
                                for f in os.listdir(sub_path):
                                    src_f = os.path.join(sub_path, f)
                                    dst_f = os.path.join(dst_path, f)
                                    if os.path.isdir(src_f):
                                        if not os.path.exists(dst_f):
                                            shutil.copytree(src_f, dst_f)
                                    else:
                                        shutil.copy2(src_f, dst_f)
                        else:
                            shutil.copy2(sub_path, dst_path)
                else:
                    shutil.copy2(item_path, os.path.join(pkg_dir, item))
            
            # Asegurar __init__.py
            init_file = os.path.join(pkg_dir, "__init__.py")
            if not os.path.exists(init_file):
                with open(init_file, 'w') as f:
                    f.write("# PeakRDL generated package\n")
            
            # Limpiar directorio temporal
            shutil.rmtree(tmp_dir)
            
            print(f"  ✓ Python package generated in: {pkg_dir}")
            
    except RDLCompileError as e:
        print(f"  ✗ Error compiling SystemRDL: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"  ✗ Error generating Python: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate code from SystemRDL files')
    parser.add_argument("files", nargs='+', help="list of .rdl files")
    parser.add_argument("--output", "-o", help="output directory", default=".")
    parser.add_argument("--toplevel", action="store_true", help="indicates if is top rdl or not")
    parser.add_argument("--hdl", action="store_true", help="generate SystemVerilog HDL")
    parser.add_argument("--html", action="store_true", help="generate HTML documentation")
    parser.add_argument("--c-header", action="store_true", help="generate C header")
    parser.add_argument("--vlog-header", action="store_true", help="generate Verilog header")
    parser.add_argument("--python", action="store_true", help="generate Python package")
    parser.add_argument("--all", action="store_true", help="generate all outputs")
    args = parser.parse_args()

    print(f"Processing: {args.files}")
    
    if args.all or args.hdl:
        print("Generating SystemVerilog...")
        hdl_gen(args.output, args.files)
    
    if args.all or args.html:
        print("Generating HTML documentation...")
        html_gen(args.output, args.files)
    
    if args.all or args.c_header:
        print("Generating C header...")
        c_header_gen(args.output, args.files, args.toplevel)
    
    if args.all or args.vlog_header:
        print("Generating Verilog header...")
        verilog_header_gen(args.output, args.files, args.toplevel)
    
    if args.all or args.python:
        print("Generating Python package...")
        python_header_gen(args.output, args.files, args.toplevel)
    
    print("Done!")
