/*

Copyright (c) 2016-2018 Alex Forencich

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
 * Generic IDDR module
 */
module iddr #
(
    // Width of register in bits
    parameter WIDTH = 1,
    parameter INSERT_BUFFERS = "FALSE"
)
(
    input  wire             clk,
    // Data input   
    input  wire [WIDTH-1:0] d,

    output wire [WIDTH-1:0] q1,
    output wire [WIDTH-1:0] q2
);

/*

Provides a consistent input DDR flip flop across multiple FPGA families
              _____       _____       _____       _____       ____
    clk  ____/     \_____/     \_____/     \_____/     \_____/
         _ _____ _____ _____ _____ _____ _____ _____ _____ _____ _
    d    _X_D0__X_D1__X_D2__X_D3__X_D4__X_D5__X_D6__X_D7__X_D8__X_
         _______ ___________ ___________ ___________ ___________ _
    q1   _______X___________X____D0_____X____D2_____X____D4_____X_
         _______ ___________ ___________ ___________ ___________ _
    q2   _______X___________X____D1_____X____D3_____X____D5_____X_

*/
wire [WIDTH-1:0] d_int;
wire [WIDTH-1:0] delayed_data_int;

genvar n;

generate

if (INSERT_BUFFERS == "TRUE") begin
    for (genvar i = 0; i < WIDTH; i=i+1) begin
        IBUF IBUF_inst (
        .I(d[i]),
        .O(d_int[i])
        );
    end
end else begin
    assign d_int = d;
end

for (n = 0; n < WIDTH; n = n + 1) begin : iddr
    // Use IDELAYE3 for Ultrascale and Ultrascale+ devices to adjust delay between clock and data
    // found delay count value by sweeping and checking the output
   IDELAYE3 #(
      .CASCADE("NONE"),          
      .DELAY_FORMAT("COUNT"),  // Units of the DELAY_VALUE (COUNT, TIME)  
      .DELAY_SRC("IDATAIN"),     
      .DELAY_TYPE("FIXED"),      
      .DELAY_VALUE(9'h19),           
      .IS_CLK_INVERTED(1'b0),    
      .IS_RST_INVERTED(1'b0),    
      .REFCLK_FREQUENCY(300.0),  
      .SIM_DEVICE("ULTRASCALE_PLUS"), 
      .UPDATE_MODE("ASYNC")      
   )
   IDELAYE3_inst (
      .CASC_OUT(),       
      .CNTVALUEOUT(cnt_value_out[(n*9)+8 : n*9 ]), 
      .DATAOUT(delayed_data_int[n]),         
      .CASC_IN(0),        
      .CASC_RETURN(0), 
      .CE(0),                  
      .CLK(clk),                
      .CNTVALUEIN(0),  
      .DATAIN(0),           
      .EN_VTC(0),          
      .IDATAIN(d_int[n]),        
      .INC(0),                
      .LOAD(0),              
      .RST(0)
   );

end
    reg [WIDTH-1:0] d_reg_1 = {WIDTH{1'b0}};
    reg [WIDTH-1:0] d_reg_2 = {WIDTH{1'b0}};

    reg [WIDTH-1:0] q_reg_1 = {WIDTH{1'b0}};
    reg [WIDTH-1:0] q_reg_2 = {WIDTH{1'b0}};

    always @(posedge clk) begin
        d_reg_1 <= delayed_data_int;
    end

    always @(negedge clk) begin
        d_reg_2 <= delayed_data_int;
    end

    always @(posedge clk) begin
        q_reg_1 <= d_reg_1;
        q_reg_2 <= d_reg_2;
    end

    assign q1 = q_reg_1;
    assign q2 = q_reg_2;

endgenerate

endmodule

`resetall
