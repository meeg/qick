# QICK\_FUSED Environment Setup

## Dependencies
Pip and virtualenv are necessary in Python.

On Ubuntu:

# apt install python3-venv python3-pip

On Arch:

# pacman -S python-pip python-virtualenv

PyXSI requires [fmt](https://github.com/fmtlib/fmt)

On Ubuntu:

# apt install libfmt-dev

On Arch:

# pacman -S fmt

GTKWave must be installed for simulation visualization:

On Ubuntu:

# apt install gtkwave

On Arch:

# pacman -S gtkwave


## Environment Variables
Vivado tools need to be in the $PATH (PyXSI to xelab, for example). To do this, you can run:

$ source [VIVADO_INSTALLATION_PATH]/settings64.sh

Additionally, PyXSI uses the Vivado dynamic library:

$ export LD_LIBRARY_PATH=[VIVADO_INSTALLATION_PATH]/lib/lnx64.o

To keep these variables permanently, both lines can be added to the .bashrc file (generally found in the terminal's default directory).
Note: New terminals automatically read .bashrc and incorporate environment variables, but if we want the change to apply to an already open terminal, we must execute:

$ source .bashrc

## Python Packages

Create a virtual environment:

$ python3 -m venv venv

Access it:

$ source venv/bin/activate

Update pip and install dependencies:

$ pip install --upgrade pip && pip install -r requirements.txt

## Execution
Unit tests, co-simulation with Python, and synthesis are run 
using FuseSoC targets.

Information about the targets each block has, such as the sources 
that compose it and dependencies on other blocks, is contained 
in a .core file. A set of .core files is called a library.

FuseSoC needs to know where to look for libraries. To do this, 
use the fusesoc\_setup.sh script:

$ source fusesoc\_setup.sh

Or manually with the fusesoc library add command, for example:

$ fusesoc library add --location $PWD/.fusesoc\_libraries/svunit-lib svunit-lib https://github.com/ivanvig/svunit.git

Example
The DDS has a sim target that runs a co-simulation in Python, 
generating stimuli and reading port outputs to generate some plots.

To run this target, the command is:

$ fusesoc --cores-root . run --build --target sim fnal:qick:dds

For more information, documentation for FuseSoC and Edalize is available.
