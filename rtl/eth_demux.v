/*

Copyright (c) 2018 Alex Forencich

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
 * Ethernet demultiplexer
 */
module eth_demux #
(
    parameter M_COUNT = 4,
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * Ethernet frame input
     */
    input  wire                          s_eth_hdr_valid,
    output wire                          s_eth_hdr_ready,
    input  wire [47:0]                   s_eth_dest_mac,
    input  wire [47:0]                   s_eth_src_mac,
    input  wire [15:0]                   s_eth_type,
    input  wire [DATA_WIDTH-1:0]         s_eth_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]         s_eth_payload_axis_tkeep,
    input  wire                          s_eth_payload_axis_tvalid,
    output wire                          s_eth_payload_axis_tready,
    input  wire                          s_eth_payload_axis_tlast,
    input  wire [ID_WIDTH-1:0]           s_eth_payload_axis_tid,
    input  wire [DEST_WIDTH-1:0]         s_eth_payload_axis_tdest,
    input  wire [USER_WIDTH-1:0]         s_eth_payload_axis_tuser,

    /*
     * Ethernet frame outputs
     */
    output wire [M_COUNT-1:0]            m_eth_hdr_valid,
    input  wire [M_COUNT-1:0]            m_eth_hdr_ready,
    output wire [M_COUNT*48-1:0]         m_eth_dest_mac,
    output wire [M_COUNT*48-1:0]         m_eth_src_mac,
    output wire [M_COUNT*16-1:0]         m_eth_type,
    output wire [M_COUNT*DATA_WIDTH-1:0] m_eth_payload_axis_tdata,
    output wire [M_COUNT*KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep,
    output wire [M_COUNT-1:0]            m_eth_payload_axis_tvalid,
    input  wire [M_COUNT-1:0]            m_eth_payload_axis_tready,
    output wire [M_COUNT-1:0]            m_eth_payload_axis_tlast,
    output wire [M_COUNT*ID_WIDTH-1:0]   m_eth_payload_axis_tid,
    output wire [M_COUNT*DEST_WIDTH-1:0] m_eth_payload_axis_tdest,
    output wire [M_COUNT*USER_WIDTH-1:0] m_eth_payload_axis_tuser,

    /*
     * Control
     */
    input  wire                          enable,
    input  wire                          drop,
    input  wire [$clog2(M_COUNT)-1:0]    select
);

localparam CL_M_COUNT = $clog2(M_COUNT);

reg [CL_M_COUNT-1:0] select_reg = {CL_M_COUNT{1'b0}}, select_ctl, select_next;
reg drop_reg = 1'b0, drop_ctl, drop_next;
reg frame_reg = 1'b0, frame_ctl, frame_next;

reg s_eth_hdr_ready_reg = 1'b0, s_eth_hdr_ready_next;

reg s_eth_payload_axis_tready_reg = 1'b0, s_eth_payload_axis_tready_next;

reg [M_COUNT-1:0] m_eth_hdr_valid_reg = 0, m_eth_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0, m_eth_dest_mac_next;
reg [47:0] m_eth_src_mac_reg = 48'd0, m_eth_src_mac_next;
reg [15:0] m_eth_type_reg = 16'd0, m_eth_type_next;

// internal datapath
reg  [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_int;
reg  [M_COUNT-1:0]    m_eth_payload_axis_tvalid_int;
reg                   m_eth_payload_axis_tready_int_reg = 1'b0;
reg                   m_eth_payload_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_eth_payload_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_eth_payload_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_eth_payload_axis_tuser_int;
wire                  m_eth_payload_axis_tready_int_early;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg && enable;

assign s_eth_payload_axis_tready = s_eth_payload_axis_tready_reg && enable;

assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
assign m_eth_dest_mac = {M_COUNT{m_eth_dest_mac_reg}};
assign m_eth_src_mac = {M_COUNT{m_eth_src_mac_reg}};
assign m_eth_type = {M_COUNT{m_eth_type_reg}};

integer i;

always @* begin
    select_next = select_reg;
    select_ctl = select_reg;
    drop_next = drop_reg;
    drop_ctl = drop_reg;
    frame_next = frame_reg;
    frame_ctl = frame_reg;

    s_eth_hdr_ready_next = 1'b0;

    s_eth_payload_axis_tready_next = 1'b0;

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg & ~m_eth_hdr_ready;
    m_eth_dest_mac_next = m_eth_dest_mac_reg;
    m_eth_src_mac_next = m_eth_src_mac_reg;
    m_eth_type_next = m_eth_type_reg;

    if (s_eth_payload_axis_tvalid && s_eth_payload_axis_tready) begin
        // end of frame detection
        if (s_eth_payload_axis_tlast) begin
            frame_next = 1'b0;
            drop_next = 1'b0;
        end
    end

    if (!frame_reg && s_eth_hdr_valid && s_eth_hdr_ready) begin
        // start of frame, grab select value
        select_ctl = select;
        drop_ctl = drop;
        frame_ctl = 1'b1;

        select_next = select_ctl;
        drop_next = drop_ctl;
        frame_next = frame_ctl;

        s_eth_hdr_ready_next = 1'b0;

        m_eth_hdr_valid_next = (!drop_ctl) << select_ctl;
        m_eth_dest_mac_next = s_eth_dest_mac;
        m_eth_src_mac_next = s_eth_src_mac;
        m_eth_type_next = s_eth_type;
    end

    s_eth_hdr_ready_next = !frame_next && !m_eth_hdr_valid_next;

    s_eth_payload_axis_tready_next = (m_eth_payload_axis_tready_int_early || drop_ctl) && frame_ctl;

    m_eth_payload_axis_tdata_int  = s_eth_payload_axis_tdata;
    m_eth_payload_axis_tkeep_int  = s_eth_payload_axis_tkeep;
    m_eth_payload_axis_tvalid_int = (s_eth_payload_axis_tvalid && s_eth_payload_axis_tready && !drop_ctl) << select_ctl;
    m_eth_payload_axis_tlast_int  = s_eth_payload_axis_tlast;
    m_eth_payload_axis_tid_int    = s_eth_payload_axis_tid;
    m_eth_payload_axis_tdest_int  = s_eth_payload_axis_tdest;
    m_eth_payload_axis_tuser_int  = s_eth_payload_axis_tuser; 
end

always @(posedge clk) begin
    if (rst) begin
        select_reg <= 2'd0;
        drop_reg <= 1'b0;
        frame_reg <= 1'b0;
        s_eth_hdr_ready_reg <= 1'b0;
        s_eth_payload_axis_tready_reg <= 1'b0;
        m_eth_hdr_valid_reg <= 0;
    end else begin
        select_reg <= select_next;
        drop_reg <= drop_next;
        frame_reg <= frame_next;
        s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;
        s_eth_payload_axis_tready_reg <= s_eth_payload_axis_tready_next;
        m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;
    end

    m_eth_dest_mac_reg <= m_eth_dest_mac_next;
    m_eth_src_mac_reg <= m_eth_src_mac_next;
    m_eth_type_reg <= m_eth_type_next;
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg [M_COUNT-1:0]    m_eth_payload_axis_tvalid_reg = {M_COUNT{1'b0}}, m_eth_payload_axis_tvalid_next;
reg                  m_eth_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_eth_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_eth_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_eth_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_eth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_eth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg [M_COUNT-1:0]    temp_m_eth_payload_axis_tvalid_reg = {M_COUNT{1'b0}}, temp_m_eth_payload_axis_tvalid_next;
reg                  temp_m_eth_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_eth_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_eth_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_eth_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_eth_payload_axis_temp_to_output;

assign m_eth_payload_axis_tdata  = {M_COUNT{m_eth_payload_axis_tdata_reg}};
assign m_eth_payload_axis_tkeep  = KEEP_ENABLE ? {M_COUNT{m_eth_payload_axis_tkeep_reg}} : {M_COUNT*KEEP_WIDTH{1'b1}};
assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
assign m_eth_payload_axis_tlast  = {M_COUNT{m_eth_payload_axis_tlast_reg}};
assign m_eth_payload_axis_tid    = ID_ENABLE   ? {M_COUNT{m_eth_payload_axis_tid_reg}}   : {M_COUNT*ID_WIDTH{1'b0}};
assign m_eth_payload_axis_tdest  = DEST_ENABLE ? {M_COUNT{m_eth_payload_axis_tdest_reg}} : {M_COUNT*DEST_WIDTH{1'b0}};
assign m_eth_payload_axis_tuser  = USER_ENABLE ? {M_COUNT{m_eth_payload_axis_tuser_reg}} : {M_COUNT*USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_eth_payload_axis_tready_int_early = (m_eth_payload_axis_tready & m_eth_payload_axis_tvalid) || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
        // input is ready
        if ((m_eth_payload_axis_tready & m_eth_payload_axis_tvalid) || !m_eth_payload_axis_tvalid) begin
            // output is ready or currently not valid, transfer data to output
            m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_eth_payload_axis_tready & m_eth_payload_axis_tvalid) begin
        // input is not ready, but output is ready
        m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
        temp_m_eth_payload_axis_tvalid_next = 1'b0;
        store_eth_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        m_eth_payload_axis_tid_reg   <= m_eth_payload_axis_tid_int;
        m_eth_payload_axis_tdest_reg <= m_eth_payload_axis_tdest_int;
        m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
        m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
        m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
        m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
        m_eth_payload_axis_tid_reg   <= temp_m_eth_payload_axis_tid_reg;
        m_eth_payload_axis_tdest_reg <= temp_m_eth_payload_axis_tdest_reg;
        m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        temp_m_eth_payload_axis_tid_reg   <= m_eth_payload_axis_tid_int;
        temp_m_eth_payload_axis_tdest_reg <= m_eth_payload_axis_tdest_int;
        temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
        m_eth_payload_axis_tvalid_reg <= {M_COUNT{1'b0}};
        m_eth_payload_axis_tready_int_reg <= 1'b0;
        temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
