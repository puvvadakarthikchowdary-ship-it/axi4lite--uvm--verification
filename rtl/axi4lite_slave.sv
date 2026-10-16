// Code your design here
`timescale 1ns/1ns

module axi4lite_slave (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] awaddr,
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wvalid,
  output logic        wready,
  output logic [1:0]  bresp,
  output logic        bvalid,
  input  logic        bready,
  input  logic [31:0] araddr,
  input  logic        arvalid,
  output logic        arready,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic        rvalid,
  input  logic        rready
);

  logic [31:0] mem [0:63];  // 256 bytes
  logic        aw_hs, w_hs;
  logic [31:0] wr_addr;
  logic [31:0] wr_data;
  logic [3:0]  wr_strb;

  // Write address handshake
  assign awready = !bvalid;
  assign wready  = !bvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_hs <= 0;
      w_hs  <= 0;
    end else begin
      if (awvalid && awready) begin
        aw_hs <= 1;
        wr_addr <= awaddr;
      end
      if (wvalid && wready) begin
        w_hs <= 1;
        wr_data <= wdata;
        wr_strb <= wstrb;
      end
      if (bvalid && bready) begin
        aw_hs <= 0;
        w_hs  <= 0;
      end
    end
  end

  // Write response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bvalid <= 0;
      bresp  <= 2'b00;
    end else begin
      if (aw_hs && w_hs && !bvalid) begin
        // DECERR for out-of-range
        if (wr_addr >= 256) begin
          bresp <= 2'b11;
        end else begin
          for (int i = 0; i < 4; i++) begin
            if (wr_strb[i])
              mem[wr_addr[7:2]][i*8 +: 8] <= wr_data[i*8 +: 8];
          end
          bresp <= 2'b00;
        end
        bvalid <= 1;
      end else if (bvalid && bready) begin
        bvalid <= 0;
      end
    end
  end

  // Read
  assign arready = !rvalid;
  assign rdata   = (araddr < 256) ? mem[araddr[7:2]] : 32'h0;
  assign rresp   = (araddr < 256) ? 2'b00 : 2'b11;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rvalid <= 0;
    else if (arvalid && arready && !rvalid) rvalid <= 1;
    else if (rvalid && rready) rvalid <= 0;
  end

endmodule
