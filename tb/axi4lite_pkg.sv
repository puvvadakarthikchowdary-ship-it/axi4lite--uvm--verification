`timescale 1ns/1ns

// ============================================================
// 1. INTERFACE (must come before package, since package uses it)
// ============================================================
interface axi4lite_if (input logic clk, input logic rst_n);
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  clocking cb @(posedge clk);
    default input #1ns output #1ns;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready;
    output araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid;
    input  arready, rdata, rresp, rvalid;
  endclocking

  modport DUT (
    input  clk, rst_n,
    input  awaddr, awvalid, wdata, wstrb, wvalid, bready,
    input  araddr, arvalid, rready,
    output awready, wready, bresp, bvalid,
    output arready, rdata, rresp, rvalid
  );

  modport TB (
    clocking cb,
    input clk, rst_n
  );

  // SVA assertions bound here
  `include "axi4lite_sva.sv"

endinterface


// ============================================================
// 2. UVM PACKAGE (all UVM classes inside one package)
// ============================================================
package axi4lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------- 2.1 Sequence Item ----------
  class axi4lite_seq_item extends uvm_sequence_item;
    rand bit        is_write;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  strb;
    bit [1:0]       resp;
    bit             oob;  // out-of-bounds flag for DECERR

    `uvm_object_utils_begin(axi4lite_seq_item)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(strb, UVM_ALL_ON)
      `uvm_field_int(resp, UVM_ALL_ON)
      `uvm_field_int(oob, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_addr {
      addr inside {[0:255]};
      if (oob) addr inside {[256:512]};
    }

    constraint c_strb {
      strb inside {4'h1, 4'h3, 4'hF};
    }

    function new(string name = "axi4lite_seq_item");
      super.new(name);
    endfunction
  endclass

  // ---------- 2.2 Sequences ----------
  class axi4lite_base_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(axi4lite_base_seq)

    function new(string name = "axi4lite_base_seq");
      super.new(name);
    endfunction
  endclass

  class axi4lite_sanity_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_sanity_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (10) begin
        txn = axi4lite_seq_item::type_id::create("wr_txn");
        start_item(txn);
        txn.is_write = 1;
        txn.addr = $urandom_range(0, 63) * 4;
        txn.data = $urandom;
        txn.strb = 4'hF;
        finish_item(txn);

        txn = axi4lite_seq_item::type_id::create("rd_txn");
        start_item(txn);
        txn.is_write = 0;
        txn.addr = txn.addr;
        finish_item(txn);
      end
    endtask
  endclass

  class axi4lite_random_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_random_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (40) begin
        txn = axi4lite_seq_item::type_id::create("rand_txn");
        start_item(txn);
        if (!txn.randomize()) `uvm_error("SEQ", "Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  class axi4lite_error_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_error_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (10) begin
        txn = axi4lite_seq_item::type_id::create("err_txn");
        start_item(txn);
        txn.oob = 1;
        txn.addr = $urandom_range(256, 512);
        txn.data = $urandom;
        if (!txn.randomize()) `uvm_error("SEQ", "Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  // ---------- 2.3 Driver ----------
  class axi4lite_driver extends uvm_driver #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_driver)
    virtual axi4lite_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_seq_item txn;
      vif.cb.awvalid <= 0; vif.cb.wvalid <= 0; vif.cb.bready <= 0;
      vif.cb.arvalid <= 0; vif.cb.rready <= 0;

      forever begin
        seq_item_port.get_next_item(txn);
        if (txn.is_write) drive_write(txn);
        else              drive_read(txn);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi4lite_seq_item txn);
      @(vif.cb);
      vif.cb.awaddr  <= txn.addr;
      vif.cb.awvalid <= 1;
      vif.cb.wdata   <= txn.data;
      vif.cb.wstrb   <= txn.strb;
      vif.cb.wvalid  <= 1;
      vif.cb.bready  <= 1;

      do @(vif.cb); while (!(vif.cb.awready && vif.cb.wready));
      vif.cb.awvalid <= 0;
      vif.cb.wvalid  <= 0;

      do @(vif.cb); while (!vif.cb.bvalid);
      txn.resp = vif.cb.bresp;
      vif.cb.bready <= 0;
      @(vif.cb);
      `uvm_info("DRV", $sformatf("WRITE addr=0x%0h data=0x%0h strb=0x%0h",
               txn.addr, txn.data, txn.strb), UVM_MEDIUM)
    endtask

    task drive_read(axi4lite_seq_item txn);
      @(vif.cb);
      vif.cb.araddr  <= txn.addr;
      vif.cb.arvalid <= 1;
      vif.cb.rready  <= 1;

      do @(vif.cb); while (!vif.cb.arready);
      vif.cb.arvalid <= 0;

      do @(vif.cb); while (!vif.cb.rvalid);
      txn.data = vif.cb.rdata;
      txn.resp = vif.cb.rresp;
      vif.cb.rready <= 0;
      @(vif.cb);
      `uvm_info("DRV", $sformatf("READ addr=0x%0h data=0x%0h resp=0x%0h",
               txn.addr, txn.data, txn.resp), UVM_MEDIUM)
    endtask
  endclass

  // ---------- 2.4 Monitor ----------
  class axi4lite_monitor extends uvm_component;
    `uvm_component_utils(axi4lite_monitor)
    virtual axi4lite_if vif;
    uvm_analysis_port #(axi4lite_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
      fork
        monitor_write();
        monitor_read();
      join
    endtask

    task monitor_write();
      axi4lite_seq_item txn;
      forever begin
        @(vif.cb);
        if (vif.cb.awvalid && vif.cb.awready && vif.cb.wvalid && vif.cb.wready) begin
          txn = axi4lite_seq_item::type_id::create("mon_wr");
          txn.is_write = 1;
          txn.addr = vif.cb.awaddr;
          txn.data = vif.cb.wdata;
          txn.strb = vif.cb.wstrb;
          @(vif.cb);
          while (!vif.cb.bvalid) @(vif.cb);
          txn.resp = vif.cb.bresp;
          ap.write(txn);
        end
      end
    endtask

    task monitor_read();
      axi4lite_seq_item txn;
      forever begin
        @(vif.cb);
        if (vif.cb.arvalid && vif.cb.arready) begin
          txn = axi4lite_seq_item::type_id::create("mon_rd");
          txn.is_write = 0;
          txn.addr = vif.cb.araddr;
          @(vif.cb);
          while (!vif.cb.rvalid) @(vif.cb);
          txn.data = vif.cb.rdata;
          txn.resp = vif.cb.rresp;
          ap.write(txn);
        end
      end
    endtask
  endclass

  // ---------- 2.5 Scoreboard (reference model) ----------
  class axi4lite_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi4lite_scoreboard)
    uvm_analysis_imp #(axi4lite_seq_item, axi4lite_scoreboard) ap_imp;
    bit [31:0] ref_mem [0:63];  // 256 bytes = 64 words
    int writes, reads, match, mismatch, resp_mismatch;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    function void write(axi4lite_seq_item txn);
      if (txn.is_write) begin
        writes++;
        if (txn.addr < 256) begin
          // Apply byte strobes to reference memory
          for (int i = 0; i < 4; i++) begin
            if (txn.strb[i])
              ref_mem[txn.addr[7:2]][i*8 +: 8] = txn.data[i*8 +: 8];
          end
        end
      end else begin
        reads++;
        if (txn.addr >= 256) begin
          // Out-of-range should return DECERR
          if (txn.resp == 2'b11) match++;
          else begin
            mismatch++;
            `uvm_error("SCB", $sformatf("Expected DECERR for addr=0x%0h, got resp=0x%0h",
                       txn.addr, txn.resp))
          end
        end else begin
          if (ref_mem.exists(txn.addr[7:2]) &&
              ref_mem[txn.addr[7:2]] == txn.data) begin
            match++;
            `uvm_info("SCB", $sformatf("READ MATCH addr=0x%0h data=0x%0h",
                     txn.addr, txn.data), UVM_HIGH)
          end else begin
            mismatch++;
            `uvm_error("SCB", $sformatf("READ MISMATCH addr=0x%0h exp=0x%0h got=0x%0h",
                       txn.addr, ref_mem[txn.addr[7:2]], txn.data))
          end
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", "============ SCOREBOARD SUMMARY ============", UVM_LOW)
      `uvm_info("SCB", $sformatf("writes=%0d reads=%0d MATCH=%0d MISMATCH=%0d",
               writes, reads, match, mismatch), UVM_LOW)
      if (mismatch == 0)
        `uvm_info("SCB", "RESULT: PASS", UVM_LOW)
      else
        `uvm_info("SCB", "RESULT: FAIL", UVM_LOW)
    endfunction
  endclass

  // ---------- 2.6 Coverage ----------
  class axi4lite_coverage extends uvm_subscriber #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_coverage)
    axi4lite_seq_item txn;

    covergroup cg_axi;
      cp_op: coverpoint txn.is_write {
        bins read  = {0};
        bins write = {1};
      }
      cp_addr: coverpoint txn.addr[7:0] {
        bins low  = {[0:63]};
        bins mid  = {[64:127]};
        bins high = {[128:255]};
      }
      cp_strb: coverpoint txn.strb {
        bins full   = {4'hF};
        bins single = {4'h1};
        bins other  = default;
      }
      cp_resp: coverpoint txn.resp {
        bins okay   = {2'b00};
        bins decerr = {2'b11};
      }
      cross cp_op, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_axi = new();
    endfunction

    function void write(axi4lite_seq_item t);
      txn = t;
      cg_axi.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("Functional coverage = %.2f%%",
               cg_axi.get_coverage()), UVM_LOW)
    endfunction
  endclass

  // ---------- 2.7 Agent ----------
  class axi4lite_agent extends uvm_agent;
    `uvm_component_utils(axi4lite_agent)
    axi4lite_driver    drv;
    axi4lite_monitor   mon;
    uvm_sequencer #(axi4lite_seq_item) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = axi4lite_driver::type_id::create("drv", this);
      mon = axi4lite_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(axi4lite_seq_item)::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ---------- 2.8 Environment ----------
  class axi4lite_env extends uvm_env;
    `uvm_component_utils(axi4lite_env)
    axi4lite_agent    agent;
    axi4lite_scoreboard scb;
    axi4lite_coverage  cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi4lite_agent::type_id::create("agent", this);
      scb   = axi4lite_scoreboard::type_id::create("scb", this);
      cov   = axi4lite_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap.connect(scb.ap_imp);
      agent.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  // ---------- 2.9 Tests ----------
  class axi4lite_sanity_test extends uvm_test;
    `uvm_component_utils(axi4lite_sanity_test)
    axi4lite_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi4lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_sanity_seq seq;
      phase.raise_objection(this);
      seq = axi4lite_sanity_seq::type_id::create("seq");
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  class axi4lite_regression_test extends uvm_test;
    `uvm_component_utils(axi4lite_regression_test)
    axi4lite_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi4lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_sanity_seq  sanity;
      axi4lite_random_seq  rand_seq;
      axi4lite_error_seq   err_seq;

      phase.raise_objection(this);

      sanity = axi4lite_sanity_seq::type_id::create("sanity");
      sanity.start(env.agent.sqr);

      rand_seq = axi4lite_random_seq::type_id::create("rand_seq");
      rand_seq.start(env.agent.sqr);

      err_seq = axi4lite_error_seq::type_id::create("err_seq");
      err_seq.start(env.agent.sqr);

      phase.drop_objection(this);
    endtask
  endclass

endpackage


// ============================================================
// 3. TOP MODULE
// ============================================================
module tb_top;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  end

  axi4lite_if axi_if (.clk(clk), .rst_n(rst_n));

  axi4lite_slave dut (
    .clk(clk), .rst_n(rst_n),
    .awaddr(axi_if.awaddr), .awvalid(axi_if.awvalid), .awready(axi_if.awready),
    .wdata(axi_if.wdata), .wstrb(axi_if.wstrb), .wvalid(axi_if.wvalid), .wready(axi_if.wready),
    .bresp(axi_if.bresp), .bvalid(axi_if.bvalid), .bready(axi_if.bready),
    .araddr(axi_if.araddr), .arvalid(axi_if.arvalid), .arready(axi_if.arready),
    .rdata(axi_if.rdata), .rresp(axi_if.rresp), .rvalid(axi_if.rvalid), .rready(axi_if.rready)
  );

  initial begin
    uvm_config_db#(virtual axi4lite_if)::set(null, "*", "vif", axi_if);
    run_test();
  end
endmodule// Code your testbench here
// or browse Examples
`timescale 1ns/1ns

// ============================================================
// 1. INTERFACE (must come before package, since package uses it)
// ============================================================
interface axi4lite_if (input logic clk, input logic rst_n);
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  clocking cb @(posedge clk);
    default input #1ns output #1ns;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready;
    output araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid;
    input  arready, rdata, rresp, rvalid;
  endclocking

  modport DUT (
    input  clk, rst_n,
    input  awaddr, awvalid, wdata, wstrb, wvalid, bready,
    input  araddr, arvalid, rready,
    output awready, wready, bresp, bvalid,
    output arready, rdata, rresp, rvalid
  );

  modport TB (
    clocking cb,
    input clk, rst_n
  );

  // SVA assertions bound here
  `include "axi4lite_sva.sv"

endinterface


// ============================================================
// 2. UVM PACKAGE (all UVM classes inside one package)
// ============================================================
package axi4lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------- 2.1 Sequence Item ----------
  class axi4lite_seq_item extends uvm_sequence_item;
    rand bit        is_write;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  strb;
    bit [1:0]       resp;
    bit             oob;  // out-of-bounds flag for DECERR

    `uvm_object_utils_begin(axi4lite_seq_item)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(strb, UVM_ALL_ON)
      `uvm_field_int(resp, UVM_ALL_ON)
      `uvm_field_int(oob, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_addr {
      addr inside {[0:255]};
      if (oob) addr inside {[256:512]};
    }

    constraint c_strb {
      strb inside {4'h1, 4'h3, 4'hF};
    }

    function new(string name = "axi4lite_seq_item");
      super.new(name);
    endfunction
  endclass

  // ---------- 2.2 Sequences ----------
  class axi4lite_base_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(axi4lite_base_seq)

    function new(string name = "axi4lite_base_seq");
      super.new(name);
    endfunction
  endclass

  class axi4lite_sanity_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_sanity_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (10) begin
        txn = axi4lite_seq_item::type_id::create("wr_txn");
        start_item(txn);
        txn.is_write = 1;
        txn.addr = $urandom_range(0, 63) * 4;
        txn.data = $urandom;
        txn.strb = 4'hF;
        finish_item(txn);

        txn = axi4lite_seq_item::type_id::create("rd_txn");
        start_item(txn);
        txn.is_write = 0;
        txn.addr = txn.addr;
        finish_item(txn);
      end
    endtask
  endclass

  class axi4lite_random_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_random_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (40) begin
        txn = axi4lite_seq_item::type_id::create("rand_txn");
        start_item(txn);
        if (!txn.randomize()) `uvm_error("SEQ", "Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  class axi4lite_error_seq extends axi4lite_base_seq;
    `uvm_object_utils(axi4lite_error_seq)

    task body();
      axi4lite_seq_item txn;
      repeat (10) begin
        txn = axi4lite_seq_item::type_id::create("err_txn");
        start_item(txn);
        txn.oob = 1;
        txn.addr = $urandom_range(256, 512);
        txn.data = $urandom;
        if (!txn.randomize()) `uvm_error("SEQ", "Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  // ---------- 2.3 Driver ----------
  class axi4lite_driver extends uvm_driver #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_driver)
    virtual axi4lite_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_seq_item txn;
      vif.cb.awvalid <= 0; vif.cb.wvalid <= 0; vif.cb.bready <= 0;
      vif.cb.arvalid <= 0; vif.cb.rready <= 0;

      forever begin
        seq_item_port.get_next_item(txn);
        if (txn.is_write) drive_write(txn);
        else              drive_read(txn);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi4lite_seq_item txn);
      @(vif.cb);
      vif.cb.awaddr  <= txn.addr;
      vif.cb.awvalid <= 1;
      vif.cb.wdata   <= txn.data;
      vif.cb.wstrb   <= txn.strb;
      vif.cb.wvalid  <= 1;
      vif.cb.bready  <= 1;

      do @(vif.cb); while (!(vif.cb.awready && vif.cb.wready));
      vif.cb.awvalid <= 0;
      vif.cb.wvalid  <= 0;

      do @(vif.cb); while (!vif.cb.bvalid);
      txn.resp = vif.cb.bresp;
      vif.cb.bready <= 0;
      @(vif.cb);
      `uvm_info("DRV", $sformatf("WRITE addr=0x%0h data=0x%0h strb=0x%0h",
               txn.addr, txn.data, txn.strb), UVM_MEDIUM)
    endtask

    task drive_read(axi4lite_seq_item txn);
      @(vif.cb);
      vif.cb.araddr  <= txn.addr;
      vif.cb.arvalid <= 1;
      vif.cb.rready  <= 1;

      do @(vif.cb); while (!vif.cb.arready);
      vif.cb.arvalid <= 0;

      do @(vif.cb); while (!vif.cb.rvalid);
      txn.data = vif.cb.rdata;
      txn.resp = vif.cb.rresp;
      vif.cb.rready <= 0;
      @(vif.cb);
      `uvm_info("DRV", $sformatf("READ addr=0x%0h data=0x%0h resp=0x%0h",
               txn.addr, txn.data, txn.resp), UVM_MEDIUM)
    endtask
  endclass

  // ---------- 2.4 Monitor ----------
  class axi4lite_monitor extends uvm_component;
    `uvm_component_utils(axi4lite_monitor)
    virtual axi4lite_if vif;
    uvm_analysis_port #(axi4lite_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
      fork
        monitor_write();
        monitor_read();
      join
    endtask

    task monitor_write();
      axi4lite_seq_item txn;
      forever begin
        @(vif.cb);
        if (vif.cb.awvalid && vif.cb.awready && vif.cb.wvalid && vif.cb.wready) begin
          txn = axi4lite_seq_item::type_id::create("mon_wr");
          txn.is_write = 1;
          txn.addr = vif.cb.awaddr;
          txn.data = vif.cb.wdata;
          txn.strb = vif.cb.wstrb;
          @(vif.cb);
          while (!vif.cb.bvalid) @(vif.cb);
          txn.resp = vif.cb.bresp;
          ap.write(txn);
        end
      end
    endtask

    task monitor_read();
      axi4lite_seq_item txn;
      forever begin
        @(vif.cb);
        if (vif.cb.arvalid && vif.cb.arready) begin
          txn = axi4lite_seq_item::type_id::create("mon_rd");
          txn.is_write = 0;
          txn.addr = vif.cb.araddr;
          @(vif.cb);
          while (!vif.cb.rvalid) @(vif.cb);
          txn.data = vif.cb.rdata;
          txn.resp = vif.cb.rresp;
          ap.write(txn);
        end
      end
    endtask
  endclass

  // ---------- 2.5 Scoreboard (reference model) ----------
  class axi4lite_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi4lite_scoreboard)
    uvm_analysis_imp #(axi4lite_seq_item, axi4lite_scoreboard) ap_imp;
    bit [31:0] ref_mem [0:63];  // 256 bytes = 64 words
    int writes, reads, match, mismatch, resp_mismatch;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    function void write(axi4lite_seq_item txn);
      if (txn.is_write) begin
        writes++;
        if (txn.addr < 256) begin
          // Apply byte strobes to reference memory
          for (int i = 0; i < 4; i++) begin
            if (txn.strb[i])
              ref_mem[txn.addr[7:2]][i*8 +: 8] = txn.data[i*8 +: 8];
          end
        end
      end else begin
        reads++;
        if (txn.addr >= 256) begin
          // Out-of-range should return DECERR
          if (txn.resp == 2'b11) match++;
          else begin
            mismatch++;
            `uvm_error("SCB", $sformatf("Expected DECERR for addr=0x%0h, got resp=0x%0h",
                       txn.addr, txn.resp))
          end
        end else begin
          if (ref_mem.exists(txn.addr[7:2]) &&
              ref_mem[txn.addr[7:2]] == txn.data) begin
            match++;
            `uvm_info("SCB", $sformatf("READ MATCH addr=0x%0h data=0x%0h",
                     txn.addr, txn.data), UVM_HIGH)
          end else begin
            mismatch++;
            `uvm_error("SCB", $sformatf("READ MISMATCH addr=0x%0h exp=0x%0h got=0x%0h",
                       txn.addr, ref_mem[txn.addr[7:2]], txn.data))
          end
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", "============ SCOREBOARD SUMMARY ============", UVM_LOW)
      `uvm_info("SCB", $sformatf("writes=%0d reads=%0d MATCH=%0d MISMATCH=%0d",
               writes, reads, match, mismatch), UVM_LOW)
      if (mismatch == 0)
        `uvm_info("SCB", "RESULT: PASS", UVM_LOW)
      else
        `uvm_info("SCB", "RESULT: FAIL", UVM_LOW)
    endfunction
  endclass

  // ---------- 2.6 Coverage ----------
  class axi4lite_coverage extends uvm_subscriber #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_coverage)
    axi4lite_seq_item txn;

    covergroup cg_axi;
      cp_op: coverpoint txn.is_write {
        bins read  = {0};
        bins write = {1};
      }
      cp_addr: coverpoint txn.addr[7:0] {
        bins low  = {[0:63]};
        bins mid  = {[64:127]};
        bins high = {[128:255]};
      }
      cp_strb: coverpoint txn.strb {
        bins full   = {4'hF};
        bins single = {4'h1};
        bins other  = default;
      }
      cp_resp: coverpoint txn.resp {
        bins okay   = {2'b00};
        bins decerr = {2'b11};
      }
      cross cp_op, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_axi = new();
    endfunction

    function void write(axi4lite_seq_item t);
      txn = t;
      cg_axi.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("Functional coverage = %.2f%%",
               cg_axi.get_coverage()), UVM_LOW)
    endfunction
  endclass

  // ---------- 2.7 Agent ----------
  class axi4lite_agent extends uvm_agent;
    `uvm_component_utils(axi4lite_agent)
    axi4lite_driver    drv;
    axi4lite_monitor   mon;
    uvm_sequencer #(axi4lite_seq_item) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = axi4lite_driver::type_id::create("drv", this);
      mon = axi4lite_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(axi4lite_seq_item)::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ---------- 2.8 Environment ----------
  class axi4lite_env extends uvm_env;
    `uvm_component_utils(axi4lite_env)
    axi4lite_agent    agent;
    axi4lite_scoreboard scb;
    axi4lite_coverage  cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi4lite_agent::type_id::create("agent", this);
      scb   = axi4lite_scoreboard::type_id::create("scb", this);
      cov   = axi4lite_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap.connect(scb.ap_imp);
      agent.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  // ---------- 2.9 Tests ----------
  class axi4lite_sanity_test extends uvm_test;
    `uvm_component_utils(axi4lite_sanity_test)
    axi4lite_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi4lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_sanity_seq seq;
      phase.raise_objection(this);
      seq = axi4lite_sanity_seq::type_id::create("seq");
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  class axi4lite_regression_test extends uvm_test;
    `uvm_component_utils(axi4lite_regression_test)
    axi4lite_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi4lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      axi4lite_sanity_seq  sanity;
      axi4lite_random_seq  rand_seq;
      axi4lite_error_seq   err_seq;

      phase.raise_objection(this);

      sanity = axi4lite_sanity_seq::type_id::create("sanity");
      sanity.start(env.agent.sqr);

      rand_seq = axi4lite_random_seq::type_id::create("rand_seq");
      rand_seq.start(env.agent.sqr);

      err_seq = axi4lite_error_seq::type_id::create("err_seq");
      err_seq.start(env.agent.sqr);

      phase.drop_objection(this);
    endtask
  endclass

endpackage


// ============================================================
// 3. TOP MODULE
// ============================================================
module tb_top;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  end

  axi4lite_if axi_if (.clk(clk), .rst_n(rst_n));

  axi4lite_slave dut (
    .clk(clk), .rst_n(rst_n),
    .awaddr(axi_if.awaddr), .awvalid(axi_if.awvalid), .awready(axi_if.awready),
    .wdata(axi_if.wdata), .wstrb(axi_if.wstrb), .wvalid(axi_if.wvalid), .wready(axi_if.wready),
    .bresp(axi_if.bresp), .bvalid(axi_if.bvalid), .bready(axi_if.bready),
    .araddr(axi_if.araddr), .arvalid(axi_if.arvalid), .arready(axi_if.arready),
    .rdata(axi_if.rdata), .rresp(axi_if.rresp), .rvalid(axi_if.rvalid), .rready(axi_if.rready)
  );

  initial begin
    uvm_config_db#(virtual axi4lite_if)::set(null, "*", "vif", axi_if);
    run_test();
  end
endmodule
