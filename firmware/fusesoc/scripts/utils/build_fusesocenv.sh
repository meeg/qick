#!/bin/bash
set -e
source venv/bin/activate
fusesoc library add \
    --location .fusesoc_libraries/svunit_lib \
    svunit_lib \
    https://github.com/ivanvig/svunit.git
