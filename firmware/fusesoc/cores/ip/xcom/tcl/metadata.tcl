set design "xcom"
set top "${design}"
set proj_dir "./ip_proj"

set ip_properties [ list \
    vendor "fnal" \
    library "qick" \
    name ${design} \
    version "0.1.0" \
    taxonomy "/AXIS_Application" \
    display_name "tproc peripheral interface" \
    description "Executes an operation over AXI4-Stream" \
    vendor_display_name "fnal" \
    company_url "http://fnal.gov" \
    ]

set family_lifecycle { \
  artix7 Production \
  artix7l Production \
  kintex7 Production \
  kintex7l Production \
  kintexu Production \
  kintexuplus Production \
  virtex7 Production \
  virtexuplus Production \
  zynq Production \
  zynquplus Production \
  aartix7 Production \
  azynq Production \
  qartix7 Production \
  qkintex7 Production \
  qkintex7l Production \
  qvirtex7 Production \
  qzynq Production \
}
