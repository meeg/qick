`include "svunit_defines.svh"

module qick_processor_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "qick_processor_ut";
  svunit_testcase svunit_ut;

  // --- clk & reset ---
  logic clk  = 0;
  logic rstn = 1;
  always #2 clk = ~clk;   // 250 MHz

  function void build();
    svunit_ut = new(name);
  endfunction

  task setup();
    svunit_ut.setup();
    rstn = 0;
    repeat(4) @(posedge clk);
    rstn = 1;
    repeat(4) @(posedge clk);
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask

  `SVUNIT_TESTS_BEGIN

  `SVTEST(test00_reset)
    // placeholder — agregar instancia y asserts reales
    repeat(10) @(posedge clk);
    `ASSERT_EQUAL(1, 1)
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
