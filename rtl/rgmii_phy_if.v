/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * RGMII PHY interface
 */
module rgmii_phy_if #
(
    // target ("SIM", "GENERIC", "XILINX", "ALTERA")
    parameter TARGET = "GENERIC",
    // IODDR style ("IODDR", "IODDR2")
    // Use IODDR for Virtex-4, Virtex-5, Virtex-6, 7 Series, Ultrascale
    // Use IODDR2 for Spartan-6
    parameter IODDR_STYLE = "IODDR2",
    // Clock input style ("BUFG", "BUFR", "BUFIO", "BUFIO2")
    // Use BUFR for Virtex-6, 7-series
    // Use BUFG for Virtex-5, Spartan-6, Ultrascale
    parameter CLOCK_INPUT_STYLE = "BUFG",
    // Use 90 degree clock for RGMII transmit ("TRUE", "FALSE")
    parameter USE_CLK90 = "TRUE",
    parameter INSERT_BUFFERS = "TRUE"
)
(
    // Reset, synchronous to gmii_gtx_clk
    input  wire        rst,

    /*
     * GMII interface to MAC
     */
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME gmii, CAN_DEBUG false" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii RX_CLK" *)  output wire        gmii_rx_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii RXD" *)     output wire [7:0]  gmii_rxd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii RX_DV" *)   output wire        gmii_rx_dv,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii RX_ER" *)   output wire        gmii_rx_er,

    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii GTX_CLK" *) input wire         gmii_gtx_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii TXD" *)     input  wire [7:0]  gmii_txd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii TX_EN" *)   input  wire        gmii_tx_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 gmii TX_ER" *)   input  wire        gmii_tx_er,
    // These are non-standard gmii signals to control the MAC
    input  wire        gmii_gtx_clk_90,
    output wire        gmii_rx_rst,
    output wire        gmii_tx_rst,
    output wire        gmii_tx_clk_en,

    /*
     * RGMII interface to PHY
     */
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rgmii, CAN_DEBUG false" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RXC" *)    input  wire        rgmii_rxc,
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RD" *)     input  wire [3:0]  rgmii_rd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RX_CTL" *) input  wire        rgmii_rx_ctl,
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TXC" *)    output wire        rgmii_txc,
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TD" *)     output wire [3:0]  rgmii_td,
    (* X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TX_CTL" *) output wire        rgmii_tx_ctl,

    /*
     * Control
     */
     // 2'b10: 1G
     // 2'b01: 100M
     // 2'b00: 10M
    input  wire [1:0]  speed
);

wire clk;

// receive

wire rgmii_rx_ctl_1;
wire rgmii_rx_ctl_2;

ssio_ddr_in #
(
    .TARGET(TARGET),
    .CLOCK_INPUT_STYLE(CLOCK_INPUT_STYLE),
    .IODDR_STYLE(IODDR_STYLE),
    .WIDTH(5),
    .INSERT_BUFFERS(INSERT_BUFFERS)
)
rx_ssio_ddr_inst (
    .input_clk(rgmii_rxc),
    .input_d({rgmii_rd, rgmii_rx_ctl}),
    .output_clk(gmii_rx_clk),
    .output_q1({gmii_rxd[3:0], rgmii_rx_ctl_1}),
    .output_q2({gmii_rxd[7:4], rgmii_rx_ctl_2})
);

assign gmii_rx_dv = rgmii_rx_ctl_1;
assign gmii_rx_er = rgmii_rx_ctl_1 ^ rgmii_rx_ctl_2;

// transmit

reg rgmii_tx_clk_1 = 1'b1;
reg rgmii_tx_clk_2 = 1'b0;
reg rgmii_tx_clk_en = 1'b1;

reg [5:0] count_reg = 6'd0;

always @(posedge clk) begin
    rgmii_tx_clk_1 <= rgmii_tx_clk_2;

    if (speed == 2'b00) begin
        // 10M
        count_reg <= count_reg + 1;
        rgmii_tx_clk_en <= 1'b0;
        if (count_reg == 24) begin
            rgmii_tx_clk_1 <= 1'b1;
            rgmii_tx_clk_2 <= 1'b1;
        end else if (count_reg >= 49) begin
            rgmii_tx_clk_2 <= 1'b0;
            rgmii_tx_clk_en <= 1'b1;
            count_reg <= 0;
        end
    end else if (speed == 2'b01) begin
        // 100M
        count_reg <= count_reg + 1;
        rgmii_tx_clk_en <= 1'b0;
        if (count_reg == 2) begin
            rgmii_tx_clk_1 <= 1'b1;
            rgmii_tx_clk_2 <= 1'b1;
        end else if (count_reg >= 4) begin
            rgmii_tx_clk_2 <= 1'b0;
            rgmii_tx_clk_en <= 1'b1;
            count_reg <= 0;
        end
    end else begin
        // 1000M
        rgmii_tx_clk_1 <= 1'b1;
        rgmii_tx_clk_2 <= 1'b0;
        rgmii_tx_clk_en <= 1'b1;
    end

    if (rst) begin
        rgmii_tx_clk_1 <= 1'b1;
        rgmii_tx_clk_2 <= 1'b0;
        rgmii_tx_clk_en <= 1'b1;
        count_reg <= 0;
    end
end

reg [3:0] rgmii_txd_1 = 0;
reg [3:0] rgmii_txd_2 = 0;
reg rgmii_tx_ctl_1 = 1'b0;
reg rgmii_tx_ctl_2 = 1'b0;

reg gmii_clk_en = 1'b1;

always @* begin
    if (speed == 2'b00) begin
        // 10M
        rgmii_txd_1 = gmii_txd[3:0];
        rgmii_txd_2 = gmii_txd[3:0];
        if (rgmii_tx_clk_1) begin
            rgmii_tx_ctl_1 = gmii_tx_en ^ gmii_tx_er;
            rgmii_tx_ctl_2 = gmii_tx_en ^ gmii_tx_er;
        end else begin
            rgmii_tx_ctl_1 = gmii_tx_en;
            rgmii_tx_ctl_2 = gmii_tx_en;
        end
        gmii_clk_en = rgmii_tx_clk_en;
    end else if (speed == 2'b01) begin
        // 100M
        rgmii_txd_1 = gmii_txd[3:0];
        rgmii_txd_2 = gmii_txd[3:0];
        if (rgmii_tx_clk_1) begin
            rgmii_tx_ctl_1 = gmii_tx_en ^ gmii_tx_er;
            rgmii_tx_ctl_2 = gmii_tx_en ^ gmii_tx_er;
        end else begin
            rgmii_tx_ctl_1 = gmii_tx_en;
            rgmii_tx_ctl_2 = gmii_tx_en;
        end
        gmii_clk_en = rgmii_tx_clk_en;
    end else begin
        // 1000M
        rgmii_txd_1 = gmii_txd[3:0];
        rgmii_txd_2 = gmii_txd[7:4];
        rgmii_tx_ctl_1 = gmii_tx_en;
        rgmii_tx_ctl_2 = gmii_tx_en ^ gmii_tx_er;
        gmii_clk_en = 1;
    end
end

oddr #(
    .TARGET(TARGET),
    .IODDR_STYLE(IODDR_STYLE),
    .WIDTH(1),
    .INSERT_BUFFERS(INSERT_BUFFERS)
)
clk_oddr_inst (
    .clk(USE_CLK90 == "TRUE" ? gmii_gtx_clk_90 : clk),
    .d1(rgmii_tx_clk_1),
    .d2(rgmii_tx_clk_2),
    .q(rgmii_txc)
);

oddr #(
    .TARGET(TARGET),
    .IODDR_STYLE(IODDR_STYLE),
    .WIDTH(5),
    .INSERT_BUFFERS(INSERT_BUFFERS)
)
data_oddr_inst (
    .clk(clk),
    .d1({rgmii_txd_1, rgmii_tx_ctl_1}),
    .d2({rgmii_txd_2, rgmii_tx_ctl_2}),
    .q({rgmii_td, rgmii_tx_ctl})
);

assign clk = gmii_gtx_clk;

assign gmii_tx_clk_en = gmii_clk_en;

// reset sync
reg [3:0] tx_rst_reg = 4'hf;
assign gmii_tx_rst = tx_rst_reg[0];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_rst_reg <= 4'hf;
    end else begin
        tx_rst_reg <= {1'b0, tx_rst_reg[3:1]};
    end
end

reg [3:0] rx_rst_reg = 4'hf;
assign gmii_rx_rst = rx_rst_reg[0];

always @(posedge gmii_rx_clk or posedge rst) begin
    if (rst) begin
        rx_rst_reg <= 4'hf;
    end else begin
        rx_rst_reg <= {1'b0, rx_rst_reg[3:1]};
    end
end

endmodule

`resetall
