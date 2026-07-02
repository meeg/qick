`include "svunit_defines.svh"

module tpv2_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "tpv2_ut";
    svunit_testcase svunit_ut;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    `SVUNIT_TESTS_BEGIN

    `SVTEST(test_reset)
        `FAIL_IF(0);
    `SVTEST_END

    `SVUNIT_TESTS_END
endmodule
