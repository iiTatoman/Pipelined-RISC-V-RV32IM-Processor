`timescale 1ns / 1ns

// quotient = dividend / divisor

module DividerUnsignedPipelined (
    input             clk, rst, stall,
    input      [31:0] i_dividend,
    input      [31:0] i_divisor,
    output reg [31:0] o_remainder,
    output reg [31:0] o_quotient
);

  // TODO: your code here
  reg [31:0] rem_reg[1:8];
  reg [31:0] quot_reg[1:8];
  reg [31:0] divd_reg[1:8];
  reg [31:0] divs_reg[1:8];

  wire [31:0] rem_next_wire[1:8];
  wire [31:0] quot_next_wire[1:8];
  wire [31:0] divd_next_wire[1:8];
  wire [31:0] divs_next_wire[1:8];

  genvar k;
  generate
    for (k = 1; k <= 8; k = k + 1) begin : stage
      wire [31:0] rem_in = (k == 1) ? 32'd0 : rem_reg[k-1];
      wire [31:0] quot_in = (k == 1) ? 32'd0 : quot_reg[k-1];
      wire [31:0] divd_in = (k == 1) ? i_dividend : divd_reg[k-1];
      wire [31:0] divs_in = (k == 1) ? i_divisor : divs_reg[k-1];

      wire [31:0] rem_out[0:4];
      wire [31:0] quot_out[0:4];
      wire [31:0] divd_out[0:4];

      assign rem_out[0] = rem_in;
      assign quot_out[0] = quot_in;
      assign divd_out[0] = divd_in;

      genvar m;
      for (m = 1; m <= 4; m = m + 1) begin : iter
        divu_1iter u (
          .i_divisor(divs_in),
          .i_remainder(rem_out[m-1]),
          .i_quotient(quot_out[m-1]),
          .i_dividend(divd_out[m-1]),
          .o_remainder(rem_out[m]),
          .o_quotient(quot_out[m]),
          .o_dividend(divd_out[m])
        );
      end

      assign rem_next_wire[k] = rem_out[4];
      assign quot_next_wire[k] = quot_out[4];
      assign divd_next_wire[k] = divd_out[4];
      assign divs_next_wire[k] = divs_in;
    end
  endgenerate

  integer j;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      o_remainder <= 32'd0;
      o_quotient <= 32'd0;
      for (j = 1; j <= 8; j = j + 1) begin
        rem_reg[j] <= 32'd0;
        quot_reg[j] <= 32'd0;
        divd_reg[j] <= 32'd0;
        divs_reg[j] <= 32'd0;
      end
    end else begin
      for (j = 1; j <= 8; j = j + 1) begin
        rem_reg[j] <= rem_next_wire[j];
        quot_reg[j] <= quot_next_wire[j];
        divd_reg[j] <= divd_next_wire[j];
        divs_reg[j] <= divs_next_wire[j];
      end
      o_remainder <= rem_next_wire[8];
      o_quotient <= quot_next_wire[8];
    end
  end

endmodule


module divu_1iter (
    input      [31:0] i_dividend,
    input      [31:0] i_divisor,
    input      [31:0] i_remainder,
    input      [31:0] i_quotient,
    output reg [31:0] o_dividend,
    output reg [31:0] o_remainder,
    output reg [31:0] o_quotient
);

  // TODO: copy your code from homework #1 here
  wire [31:0] remainder_temp;
  wire ge;
  wire [31:0] neg_divisor;

  assign remainder_temp = {i_remainder[30:0], i_dividend[31]};
  assign ge = (remainder_temp >= i_divisor) ? 1'b1 : 1'b0;
  assign neg_divisor = ~i_divisor + 1'b1;

  always @(*) begin
    o_remainder = ge ? (remainder_temp + neg_divisor) : remainder_temp;
    o_quotient = {i_quotient[30:0], ge};
    o_dividend = {i_dividend[30:0], 1'b0};
  end

endmodule
