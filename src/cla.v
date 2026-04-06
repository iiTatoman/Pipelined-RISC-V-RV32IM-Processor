`timescale 1ns / 1ps

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
   assign g = a & b;
   assign p = a | b;
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits internally would generate a carry-out (independent of cin)
 * @param pout whether these 4 bits internally would propagate an incoming carry from cin
 * @param cout the carry outs for the low-order 3 bits
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout);

    wire [3:0] c;
    assign c[0] = cin;
    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : c_gen_4
            assign c[i+1] = gin[i] | (pin[i] & c[i]);
            assign cout[i] = c[i+1];
        end
    endgenerate

    assign pout = &pin;
    assign gout = gin[3] |
                  (pin[3] & gin[2]) |
                  (pin[3] & pin[2] & gin[1]) |
                  (pin[3] & pin[2] & pin[1] & gin[0]);

endmodule

/** Same as gp4 but for an 8-bit window instead */
module gp8(input wire [7:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [6:0] cout);

    wire [7:0] c;
    assign c[0] = cin;
    genvar i;
    generate
        for (i = 0; i < 7; i = i + 1) begin : c_gen_8
            assign c[i+1] = gin[i] | (pin[i] & c[i]);
            assign cout[i] = c[i+1];
        end
    endgenerate

    assign pout = &pin;
    // G[3:0]
    wire g_low = gin[3] | (pin[3] & gin[2]) | (pin[3] & pin[2] & gin[1]) | (pin[3] & pin[2] & pin[1] & gin[0]);
    // P[3:0]
    wire p_low = &pin[3:0];
    // G[7:4]
    wire g_high = gin[7] | (pin[7] & gin[6]) | (pin[7] & pin[6] & gin[5]) | (pin[7] & pin[6] & pin[5] & gin[4]);
    // P[7:4]
    wire p_high = &pin[7:4];
    assign gout = g_high | (p_high & g_low);

endmodule

module cla
  (input wire [31:0]  a, b,
   input wire         cin,
   output wire [31:0] sum);

    wire [31:0] g, p;
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gp1_gen
            gp1 u_gp1 ( .a(a[i]), .b(b[i]), .g(g[i]), .p(p[i]) );
        end
    endgenerate

    wire [7:0] g4, p4;
    wire [7:0] c_in_4;
    wire [23:0] c_out_4;

    wire [6:0] c_from_gp8;
    gp8 u_gp8_main (
        .gin(g4),
        .pin(p4),
        .cin(cin),
        .gout(),
        .pout(),
        .cout(c_from_gp8)
    );

    assign c_in_4[0] = cin;
    assign c_in_4[7:1] = c_from_gp8;

    generate
        for (i = 0; i < 8; i = i + 1) begin : gp4_gen
            gp4 u_gp4 (
                .gin(g[4*i+3 : 4*i]),
                .pin(p[4*i+3 : 4*i]),
                .cin(c_in_4[i]),
                .gout(g4[i]),
                .pout(p4[i]),
                .cout(c_out_4[3*i+2 : 3*i])
            );
        end
    endgenerate

    wire [31:0] c;
    assign c[0] = cin;

    generate
        for (i = 0; i < 8; i = i + 1) begin : carry_assign_gen
            assign c[4*i+1] = c_out_4[3*i];
            assign c[4*i+2] = c_out_4[3*i+1];
            assign c[4*i+3] = c_out_4[3*i+2];
            
            if (i < 7) begin
                assign c[4*i+4] = c_in_4[i+1];
            end
        end
    endgenerate
    
    assign sum = (a ^ b) ^ c;

endmodule
