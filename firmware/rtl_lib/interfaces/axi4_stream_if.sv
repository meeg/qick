///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: axi4_stream_if.sv
// Project: AXI4-Stream Interface
// Description:
// AXI4-Stream Interface implementation,
// including SystemVerilog assertions
//
// References:
// - AXI4-Stream protocol specification: https://developer.arm.com/documentation/ihi0051/a/
// - AXI4-Stream protocol assertions: https://developer.arm.com/documentation/dui0534/b/
//
// Change history: 12/22/25 - Created by @lharnaldi
//
///////////////////////////////////////////////////////////////////////////////
interface axi4_stream_if#(
  parameter integer unsigned  N_BYTES_TDATA   = 4,
  parameter integer unsigned  N_BITS_TUSER    = N_BYTES_TDATA,
  parameter integer unsigned  N_BITS_TID      = 8,
  parameter integer unsigned  N_BITS_TDEST    = 4,
  parameter bit               HAS_TSTRB       = 1'b0,
  parameter bit               HAS_TKEEP       = 1'b0,
  parameter bit               HAS_TID         = 1'b0,
  parameter bit               HAS_TDEST       = 1'b0,
  parameter bit               HAS_TUSER       = 1'b0,
  parameter integer unsigned  BYTE_SIZE       = 8
)(
  input logic i_clk,
  input logic i_rstn
);

  // ============================================================
  // STATIC CHECKS (SAFE EVERYWHERE)
  // ============================================================

  generate
    if (N_BYTES_TDATA == 0)
      initial $fatal(1, "N_BYTES_TDATA must be > 0");
  endgenerate

  generate
    if ((N_BITS_TID + N_BITS_TDEST) > 24)
      initial $fatal(1, "TID + TDEST width too large");
  endgenerate

  // ============================================================
  // AXI SIGNALS (ALWAYS PRESENT)
  // ============================================================

  logic tvalid;
  logic tready;
  logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] tdata;
  logic [N_BYTES_TDATA-1:0]             tstrb;
  logic [N_BYTES_TDATA-1:0]             tkeep;
  logic                                 tlast;
  logic [N_BITS_TID-1:0]                tid;
  logic [N_BITS_TDEST-1:0]              tdest;
  logic [N_BITS_TUSER-1:0]              tuser;

  // ============================================================
  // RTL MODPORTS (ALWAYS PRESENT)
  // ============================================================

  modport master (
    output tvalid,
    input  tready,
    output tdata,
    output tstrb,
    output tkeep,
    output tlast,
    output tid,
    output tdest,
    output tuser
  );

  modport slave (
    input  tvalid,
    output tready,
    input  tdata,
    input  tstrb,
    input  tkeep,
    input  tlast,
    input  tid,
    input  tdest,
    input  tuser
  );

  // ============================================================
  // SIMULATION-ONLY CODE
  // ============================================================
  `ifndef SYNTHESIS
    `ifndef VERILATOR

      // ------------------------------------------------------------
      // CLOCKING BLOCKS
      // ------------------------------------------------------------

      clocking m_cb @(posedge i_clk);
        default input #1step output #2;
        output tvalid, tdata, tstrb, tkeep, tlast, tid, tdest, tuser;
        input  tready;
      endclocking

      clocking s_cb @(posedge i_clk);
        default input #1step output #2;
        input  tvalid, tdata, tstrb, tkeep, tlast, tid, tdest, tuser;
        output tready;
      endclocking

      modport tb_master (
        clocking m_cb,
          import   tx,
          import   drive_beat,
          import   m_reset,
          import   burst_tx,
          import   sample_tlast
      );

      modport tb_slave  (
        clocking  s_cb,
          import    s_reset,
          import    rx,
          import    burst_rx,
          import    wait_for_beat,
          import    sample_tdata
      );

      // ============================================================
      // RESET TASKS
      // ============================================================

      task automatic m_reset(input int timeout_cycles = 1000);
        // Initialize all master signals
        m_cb.tvalid <= 1'b0;
        m_cb.tdata  <= '0;
        m_cb.tlast  <= 1'b0;
        m_cb.tstrb  <= '0;
        m_cb.tkeep  <= '0;
        m_cb.tid    <= '0;
        m_cb.tdest  <= '0;
        m_cb.tuser  <= '0;

        // Wait for reset to deassert
        fork
          begin
            wait(i_rstn === 1'b1);
          end
          begin
            repeat (timeout_cycles) @(m_cb);
            $fatal(1, "[AXIS] Master reset timeout");
          end
        join_any
        disable fork;

        repeat (3) @(m_cb);  // Extra settling time
      endtask

      task automatic s_reset();
        // Initialize slave ready
        s_cb.tready <= 1'b0;

        // Wait for reset to deassert
        wait(i_rstn === 1'b1);

        repeat (3) @(s_cb);  // Extra settling time

        // Assert ready
        s_cb.tready <= 1'b1;
      endtask

      // ------------------------------------------------------------
      // TX / RX TASKS 
      // ------------------------------------------------------------

      task automatic tx(
        input logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] data,
        input logic last = 1'b0,
        input int timeout = 1000
      );
        int cnt = 0;

        m_cb.tdata  <= data;
        m_cb.tlast  <= last;
        m_cb.tvalid <= 1'b1;

        @(m_cb);

        while (!m_cb.tready) begin
          @(m_cb);
          if (++cnt > timeout)
            $fatal(1, "AXIS TX timeout");
        end

        m_cb.tvalid <= 1'b0;
        m_cb.tlast  <= 1'b0;
      endtask

      task automatic rx(
        output logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] data,
        output logic last,
        input int timeout = 1000
      );
        int cnt = 0;

        s_cb.tready <= 1'b1;

        while (!s_cb.tvalid) begin
          @(s_cb);
          if (++cnt > timeout)
            $fatal(1, "AXIS RX timeout");
        end

        data = s_cb.tdata;
        last = s_cb.tlast;

        @(s_cb);
        s_cb.tready <= 1'b0;
      endtask

      task automatic drive_beat(
        input logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] data,
        input logic last = 0
      );
        // Use m_cb consistently (this is a MASTER task)
        @(m_cb);
        m_cb.tdata  <= data;
        m_cb.tvalid <= 1'b1;
        m_cb.tlast  <= last;

        // Wait for handshake
        do @(m_cb); while (!m_cb.tready);

        // Deassert after handshake
        @(m_cb);
        m_cb.tvalid <= 1'b0;
        m_cb.tlast  <= 1'b0;
      endtask

      // Slave side: wait for a valid beat
      task automatic wait_for_beat();
        // Use s_cb consistently (this is a SLAVE task)
        do @(s_cb); while (!s_cb.tvalid || !tready);
      endtask

      // Slave side: sample current data
      function automatic logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] sample_tdata();
        return tdata;  // Direct signal access (works from both sides)
      endfunction

      // Master side: sample tlast
      function automatic logic sample_tlast();
        return tlast;
      endfunction

      // Master side: go idle
      task automatic idle();
        m_cb.tvalid <= 0;
        m_cb.tlast  <= 0;
      endtask
      // ============================================================
      // AXIS TX TASK (master side)
      // ============================================================
      task automatic burst_tx(
        input logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] data_array[],
        input int unsigned n_beats,
        input int unsigned timeout = 1000
      );
        int unsigned wait_cycles;

        if (n_beats == 0)
          return;

        for (int i = 0; i < n_beats; i++) begin
          wait_cycles = 0;

          // Drive beat
          @(m_cb);
          m_cb.tdata  <= data_array[i];
          m_cb.tvalid <= 1'b1;
          m_cb.tlast  <= (i == n_beats-1);

          // Wait for handshake
          while (!m_cb.tready) begin
            @(m_cb);
            wait_cycles++;
            if (wait_cycles > timeout)
              $fatal(1, "AXIS TX timeout on beat %0d after %0d cycles", i, timeout);
          end
        end

        // Return to idle
        @(m_cb);
        m_cb.tvalid <= 1'b0;
        m_cb.tlast  <= 1'b0;
      endtask

      // ============================================================
      // AXIS RX TASK (slave side)
      // ============================================================
      task automatic burst_rx(
        output logic [(N_BYTES_TDATA*BYTE_SIZE)-1:0] data_array[$],
        input int unsigned timeout = 1000
      );
        int unsigned wait_cycles;
        logic done;

        data_array.delete();
        done = 0;
        wait_cycles = 0;

        // Assert ready
        s_cb.tready <= 1'b1;

        while (!done) begin
          @(s_cb);
          wait_cycles++;

          if (wait_cycles > timeout)
            $fatal(1, "AXIS RX timeout: no TLAST seen after %0d cycles", timeout);

          // Sample on valid handshake
          if (s_cb.tvalid && tready) begin
            data_array.push_back(s_cb.tdata);
            if (s_cb.tlast)
              done = 1;
          end
        end

        // Return to idle
        @(s_cb);
        s_cb.tready <= 1'b0;
      endtask
    `endif // VERILATOR
  `endif // SYNTHESIS

  // ============================================================
  // ASSERTIONS — SVUNIT ONLY
  // ============================================================
  `ifdef SVUNIT
    `ifndef SYNTHESIS
      `ifndef VERILATOR

        `include "svunit_assert_macros.svh"

        property AXIS_TVALID_STABLE;
          @(posedge i_clk)
          disable iff (!i_rstn)
          (tvalid && !tready) |=> tvalid;
        endproperty

        `ASSERT_CONCURRENT_LOG(
          AXIS_TVALID_STABLE,
          "AXIS: tvalid dropped while tready was low"
        )

        property VALID_RST;
          @(posedge i_clk) !i_rstn == 1'b1 |=> tvalid == 1'b0;
        endproperty
        `ASSERT_CONCURRENT_LOG( VALID_RST,
          "VALID_RST: tvalid must be LOW while reset is asserted");

        property AXI4STREAM_ERRM_TVALID_RESET;
          @(posedge i_clk) (i_rstn & $past(!i_rstn)) |-> tvalid == 1'b0; //Vivado < 2021.2 does not support $fell
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TVALID_RESET,
          "AXI4STREAM_ERRM_TVALID_RESET: tvalid was not low for the first cycle after reset went low");

        property AXI4STREAM_ERRM_TVALID_STABLE;
          @(posedge i_clk) disable iff (!i_rstn) (tvalid && !tready) |=> tvalid;
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TVALID_STABLE,
          "AXI4STREAM_ERRM_TVALID_STABLE: tvalid was deasserted even though the data was not consumed");

        property AXI4STREAM_ERRM_TDATA_STABLE;
          @(posedge i_clk) disable iff (!i_rstn) (tvalid && !tready) |=> $stable(tdata);
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TDATA_STABLE,
          "AXI4STREAM_ERRM_TDATA_STABLE: tdata was not stable when tvalid was asserted and tready was low");

        property AXI4STREAM_ERRM_TLAST_STABLE;
          @(posedge i_clk) disable iff (!i_rstn) (tvalid && !tready) |=> $stable(tlast);
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TLAST_STABLE,
          "AXI4STREAM_ERRM_TLAST_STABLE: tlast was not stable when tvalid was asserted and tready was low");

        property AXI4STREAM_ERRM_TDATA_X;
          @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tdata);
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TDATA_X,
          "AXI4STREAM_ERRM_TDATA_X: part (or all) of tdata was 1'bX while tvalid was high");

        property AXI4STREAM_ERRM_TLAST_X;
          @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tlast);
        endproperty
        `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TLAST_X,
          "AXI4STREAM_ERRM_TLAST_X: tlast was 1'bX while tvalid was high");

        generate
          if (HAS_TSTRB == 1'b1) begin : g_tstrb_assertions

            property AXI4STREAM_ERRM_TSTRB_STABLE;
              @(posedge i_clk) (i_rstn && tvalid && !tready) |=> $stable(tstrb);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TSTRB_STABLE,
              "AXI4STREAM_ERRM_TSTRB_STABLE: tstrb was not stable when tvalid was asserted and tready was low");

            property AXI4STREAM_ERRM_TSTRB_X;
              @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tstrb);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TSTRB_X,
              "AXI4STREAM_ERRM_TSTRB_X: part (or all) of tstrb was 1'bX while tvalid was high");

          end
          if (HAS_TKEEP == 1'b1) begin : g_tkeep_assertions

            property AXI4STREAM_ERRM_TKEEP_STABLE;
              @(posedge i_clk) (i_rstn && tvalid && !tready) |=> $stable(tkeep);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TKEEP_STABLE,
              "AXI4STREAM_ERRM_TKEEP_STABLE: tkeep changed while data was not consumed");

            property AXI4STREAM_ERRM_TKEEP_X;
              @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tkeep);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TKEEP_X,
              "AXI4STREAM_ERRM_TKEEP_X: part (or all) of tkeep was 1'bX while tvalid was high");

          end
          if (HAS_TID == 1'b1) begin : g_tid_assertions

            property AXI4STREAM_ERRM_TID_STABLE;
              @(posedge i_clk) (i_rstn && tvalid && !tready) |=> $stable(tid);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TID_STABLE,
              "AXI4STREAM_ERRM_TID_STABLE: tid was not stable when tvalid was asserted and tready was low");

            property AXI4STREAM_ERRM_TID_X;
              @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tid);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TID_X,
              "AXI4STREAM_ERRM_TID_X: part (or all) of tid was 1'bX while tvalid was high");

          end
          if (HAS_TDEST == 1'b1) begin : g_tdest_assertions

            property AXI4STREAM_ERRM_TDEST_STABLE;
              @(posedge i_clk) (!i_rst && tvalid && !tready) |=> $stable(tdest);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TDEST_STABLE,
              "AXI4STREAM_ERRM_TDEST_STABLE: tdest was not stable when tvalid was asserted and tready was low");

            property AXI4STREAM_ERRM_TDEST_X;
              @(posedge i_clk) (!i_rst && tvalid) |-> !$isunknown(tdest);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TDEST_X,
              "AXI4STREAM_ERRM_TDEST_X: part (or all) of tdest was 1'bX while tvalid was high");

          end
          if (HAS_TUSER == 1'b1) begin : g_tuser_assertions

            property AXI4STREAM_ERRM_TUSER_STABLE;
              @(posedge i_clk) (i_rstn && tvalid && !tready) |=> $stable(tuser);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TUSER_STABLE,
              "AXI4STREAM_ERRM_TUSER_STABLE: tuser was not stable when tvalid was asserted and tready was low");

            property AXI4STREAM_ERRM_TUSER_X;
              @(posedge i_clk) (i_rstn && tvalid) |-> !$isunknown(tuser);
            endproperty
            `ASSERT_CONCURRENT_LOG( AXI4STREAM_ERRM_TUSER_X,
              "AXI4STREAM_ERRM_TUSER_X: part (or all) of tuser was 1'bX while tvalid was high");

          end
        endgenerate
      `endif //VERILATOR
    `endif //SYNTHESIS
  `endif //SVUNIT

endinterface
