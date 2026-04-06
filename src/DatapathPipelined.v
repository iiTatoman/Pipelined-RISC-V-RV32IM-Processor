`timescale 1ns / 1ns

// registers are 32 bits in RV32
`define REG_SIZE 31

// inst. are 32 bits in RV32IM
`define INST_SIZE 31

// RV opcodes are 7 bits
`define OPCODE_SIZE 6

`define DIVIDER_STAGES 8

// Don't forget your old codes
`include "cla.v"
`include "DividerUnsignedPipelined.v"

module RegFile (
  input      [        4:0] rd,
  input      [`REG_SIZE:0] rd_data,
  input      [        4:0] rs1,
  output reg [`REG_SIZE:0] rs1_data,
  input      [        4:0] rs2,
  output reg [`REG_SIZE:0] rs2_data,
  input                    clk,
  input                    we,
  input                    rst
);
  localparam NumRegs = 32;
  reg [`REG_SIZE:0] regs[0:31];

  integer i;

  // Write Logic (Synchronous)
  // Writes occur on the rising edge, similar to the PC update logic in the datapath.
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NumRegs; i = i + 1) begin
        regs[i] <= 32'd0;
      end
    end else if (we && (rd != 5'd0)) begin
      // Only write if Write Enable is high and destination is not x0
      regs[rd] <= rd_data;
    end
  end

  // Read Logic (Combinational)
  // Includes WD Bypass: Forward data if reading the register currently being written.
  always @(*) begin
    // Read port 1 (rs1)
    if (rs1 == 5'd0) begin
      rs1_data = 32'd0;
    end else if (we && (rs1 == rd)) begin
      rs1_data = rd_data;
    end else begin
      rs1_data = regs[rs1];
    end

    // Read port 2 (rs2)
    if (rs2 == 5'd0) begin
      rs2_data = 32'd0;
    end else if (we && (rs2 == rd)) begin
      rs2_data = rd_data;
    end else begin
      rs2_data = regs[rs2];
    end
  end

endmodule

module DatapathPipelined (
  input                     clk,
  input                     rst,
  output     [ `REG_SIZE:0] pc_to_imem,
  input      [`INST_SIZE:0] inst_from_imem,
  // dmem is read/write
  output reg [ `REG_SIZE:0] addr_to_dmem,
  input      [ `REG_SIZE:0] load_data_from_dmem,
  output reg [ `REG_SIZE:0] store_data_to_dmem,
  output reg [         3:0] store_we_to_dmem,
  output reg                halt,
  // The PC of the inst currently in Writeback. 0 if not a valid inst.
  output reg [ `REG_SIZE:0] trace_writeback_pc,
  // The bits of the inst currently in Writeback. 0 if not a valid inst.
  output reg [`INST_SIZE:0] trace_writeback_inst
);

  // opcodes - see section 19 of RiscV spec
  localparam [`OPCODE_SIZE:0] OpcodeLoad    = 7'b00_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeStore   = 7'b01_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeBranch  = 7'b11_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeJalr    = 7'b11_001_11;
  localparam [`OPCODE_SIZE:0] OpcodeMiscMem = 7'b00_011_11;
  localparam [`OPCODE_SIZE:0] OpcodeJal     = 7'b11_011_11;

  localparam [`OPCODE_SIZE:0] OpcodeRegImm  = 7'b00_100_11;
  localparam [`OPCODE_SIZE:0] OpcodeRegReg  = 7'b01_100_11;
  localparam [`OPCODE_SIZE:0] OpcodeEnviron = 7'b11_100_11;

  localparam [`OPCODE_SIZE:0] OpcodeAuipc   = 7'b00_101_11;
  localparam [`OPCODE_SIZE:0] OpcodeLui     = 7'b01_101_11;

  // cycle counter, not really part of any stage but useful for orienting within GtkWave
  // do not rename this as the testbench uses this value
  reg [`REG_SIZE:0] cycles_current;
  always @(posedge clk) begin
    if (rst) begin
      cycles_current <= 0;
    end else begin
      cycles_current <= cycles_current + 1;
    end
  end

  /***************/
  /* FETCH STAGE */
  /***************/

  reg  [`REG_SIZE:0] f_pc_current;
  wire [`REG_SIZE:0] f_inst;

  // program counter
  always @(posedge clk) begin
    if (rst) begin
      f_pc_current <= 32'd0;
    end else begin
      f_pc_current <= f_pc_current + 4;
    end
  end
  // send PC to imem
  assign pc_to_imem = f_pc_current;
  assign f_inst = inst_from_imem;

  /****************/
  /* DECODE STAGE */
  /****************/

  // TODO: your code here, though you will also need to modify some of the code above

  // Pipeline Registers F->D
  reg [`REG_SIZE:0] d_pc;
  reg [`INST_SIZE:0] d_inst;

  always @(posedge clk) begin
    if (rst || execute_redirect) begin
      // Flush Decode on reset or branch taken
      d_pc <= 0;
      d_inst <= 0; // Insert Bubble (NOP)
    end else if (!stall_pipeline) begin
      d_pc <= f_pc_current;
      d_inst <= f_inst;
    end
    // If stalled, keep current Decode registers
  end

  // Decode Logic
  wire [6:0] d_opcode = d_inst[6:0];
  wire [4:0] d_rd     = d_inst[11:7];
  wire [2:0] d_funct3 = d_inst[14:12];
  wire [4:0] d_rs1    = d_inst[19:15];
  wire [4:0] d_rs2    = d_inst[24:20];
  wire [6:0] d_funct7 = d_inst[31:25];

  // Immediate Generation
  wire [`REG_SIZE:0] d_imm_i = {{20{d_inst[31]}}, d_inst[31:20]};
  wire [`REG_SIZE:0] d_imm_s = {{20{d_inst[31]}}, d_inst[31:25], d_inst[11:7]};
  wire [`REG_SIZE:0] d_imm_b = {{20{d_inst[31]}}, d_inst[7], d_inst[30:25], d_inst[11:8], 1'b0};
  wire [`REG_SIZE:0] d_imm_u = {d_inst[31:12], 12'b0};
  wire [`REG_SIZE:0] d_imm_j = {{12{d_inst[31]}}, d_inst[19:12], d_inst[20], d_inst[30:21], 1'b0};

  // Register File
  wire [`REG_SIZE:0] d_rs1_data_raw;
  wire [`REG_SIZE:0] d_rs2_data_raw;

  RegFile rf (
    .rd(w_rd),
    .rd_data(w_rd_data),
    .rs1(d_rs1),
    .rs1_data(d_rs1_data_raw),
    .rs2(d_rs2),
    .rs2_data(d_rs2_data_raw),
    .clk(clk),
    .we(w_reg_we),
    .rst(rst)
  );

  // Control Signals (Decode)
  wire d_is_load   = (d_opcode == OpcodeLoad);
  wire d_is_store  = (d_opcode == OpcodeStore);
  wire d_is_branch = (d_opcode == OpcodeBranch);
  wire d_is_jal    = (d_opcode == OpcodeJal);
  wire d_is_jalr   = (d_opcode == OpcodeJalr);
  wire d_is_lui    = (d_opcode == OpcodeLui);
  wire d_is_auipc  = (d_opcode == OpcodeAuipc);
  wire d_is_system = (d_opcode == OpcodeEnviron); 
  
  // Detect Division
  wire d_is_div_rem = (d_opcode == OpcodeRegReg) && (d_funct7 == 7'b0000001);

  // Wires from Execute Stage for Hazard Detection
  wire x_is_load;
  wire [4:0] x_rd;
  wire x_is_div_rem;
  wire x_div_busy;

  // Stall Logic
  // If X is Load, and D depends on X's destination -> Stall
  wire stall_load_use = x_is_load && ((d_rs1 == x_rd && d_rs1 != 0) || (d_rs2 == x_rd && d_rs2 != 0));
  assign stall_pipeline = stall_load_use; 


  /* EXECUTE STAGE */


  // Pipeline Registers D->X
  reg [`REG_SIZE:0] x_pc;
  reg [`INST_SIZE:0] x_inst;
  reg [`REG_SIZE:0] x_rs1_data;
  reg [`REG_SIZE:0] x_rs2_data;
  reg [`REG_SIZE:0] x_imm;
  reg [4:0] x_rd_reg;
  reg [2:0] x_funct3_reg;
  reg [6:0] x_funct7_reg;
  reg [6:0] x_opcode_reg;
  
  // Control signals passed to X
  reg x_is_load_reg;
  reg x_is_store_reg;
  reg x_reg_we_reg;

  always @(posedge clk) begin
    if (rst || execute_redirect || stall_pipeline) begin
        // Flush Execute (Bubble)
        x_pc <= 0;
        x_inst <= 0; // NOP
        x_is_load_reg <= 0;
        x_is_store_reg <= 0;
        x_reg_we_reg <= 0;
        x_rd_reg <= 0;
        x_opcode_reg <= 0;
    end else begin
        x_pc <= d_pc;
        x_inst <= d_inst;
        x_rs1_data <= d_rs1_data_raw;
        x_rs2_data <= d_rs2_data_raw;
        x_rd_reg <= d_rd;
        x_funct3_reg <= d_funct3;
        x_funct7_reg <= d_funct7;
        x_opcode_reg <= d_opcode;
        
        // Pass immediates based on type
        if (d_is_store) x_imm <= d_imm_s;
        else if (d_is_branch) x_imm <= d_imm_b;
        else if (d_is_lui || d_is_auipc) x_imm <= d_imm_u;
        else if (d_is_jal) x_imm <= d_imm_j;
        else x_imm <= d_imm_i; // RegImm, Load, Jalr

        // Control Signals D->X
        x_is_load_reg <= d_is_load;
        x_is_store_reg <= d_is_store;
        // Reg Write Enable: Load, Lui, Auipc, Jal, Jalr, RegImm, RegReg
        x_reg_we_reg <= (d_is_load || d_is_lui || d_is_auipc || d_is_jal || d_is_jalr || d_opcode == OpcodeRegImm || d_opcode == OpcodeRegReg) && (d_rd != 0);
    end
  end
  
  // Expose signals for Hazard Unit
  assign x_is_load = x_is_load_reg;
  assign x_rd = x_rd_reg;

  // Wires from Memory and Writeback for Bypassing
  wire m_reg_we;
  wire [4:0] m_rd;
  wire [`REG_SIZE:0] m_alu_result;
  
  // Forwarding Logic (MX and WX Bypass)
  reg [`REG_SIZE:0] x_rs1_forwarded;
  reg [`REG_SIZE:0] x_rs2_forwarded;
  
  wire [4:0] x_rs1 = x_inst[19:15];
  wire [4:0] x_rs2 = x_inst[24:20];

  always @(*) begin
    // MX Bypass (Memory -> Execute)
    if (m_reg_we && m_rd != 0 && m_rd == x_rs1) 
        x_rs1_forwarded = m_alu_result;
    // WX Bypass (Writeback -> Execute)
    else if (w_reg_we && w_rd != 0 && w_rd == x_rs1) 
        x_rs1_forwarded = w_rd_data;
    else 
        x_rs1_forwarded = x_rs1_data;

    // MX Bypass
    if (m_reg_we && m_rd != 0 && m_rd == x_rs2) 
        x_rs2_forwarded = m_alu_result;
    // WX Bypass
    else if (w_reg_we && w_rd != 0 && w_rd == x_rs2) 
        x_rs2_forwarded = w_rd_data;
    else 
        x_rs2_forwarded = x_rs2_data;
  end

  // ALU Operations
  wire [`REG_SIZE:0] x_op_a = (x_opcode_reg == OpcodeAuipc) ? x_pc : x_rs1_forwarded;
  wire [`REG_SIZE:0] x_op_b = (x_opcode_reg == OpcodeRegReg) ? x_rs2_forwarded : x_imm;

  wire [`REG_SIZE:0] alu_sum;
  wire [`REG_SIZE:0] alu_and = x_op_a & x_op_b;
  wire [`REG_SIZE:0] alu_or  = x_op_a | x_op_b;
  wire [`REG_SIZE:0] alu_xor = x_op_a ^ x_op_b;
  wire [`REG_SIZE:0] alu_sll = x_op_a << x_op_b[4:0];
  wire [`REG_SIZE:0] alu_srl = x_op_a >> x_op_b[4:0];
  wire [`REG_SIZE:0] alu_sra = $signed(x_op_a) >>> x_op_b[4:0];
  
  // CLA instance
  cla adder_inst (.a(x_op_a), .b(x_op_b), .cin(1'b0), .sum(alu_sum));
  
  // Subtraction for branches/comparisons
  wire [`REG_SIZE:0] sub_res;
  cla sub_inst (.a(x_op_a), .b(~x_op_b), .cin(1'b1), .sum(sub_res)); // A - B

  wire x_is_slt  = ($signed(x_op_a) < $signed(x_op_b));
  wire x_is_sltu = (x_op_a < x_op_b);
  wire x_eq      = (x_op_a == x_op_b);
  
  reg [`REG_SIZE:0] x_alu_result;
  
  // Divider Interface
  wire x_is_div_op = (x_opcode_reg == OpcodeRegReg) && (x_funct7_reg == 7'b0000001);
  wire [31:0] div_rem, div_quot;
  
  DividerUnsignedPipelined div_module (
    .clk(clk), .rst(rst), .stall(1'b0), // TODO: Handle stall if needed for dependent divides
    .i_dividend(x_rs1_forwarded),
    .i_divisor(x_rs2_forwarded),
    .o_remainder(div_rem),
    .o_quotient(div_quot)
  );

  always @(*) begin
    if (x_opcode_reg == OpcodeLui) x_alu_result = x_imm;
    else if (x_is_div_op) begin
         // Simple muxing for now, real divide stall logic needed for Milestone 2 fully
         case (x_funct3_reg)
            3'b100: x_alu_result = div_quot; // DIV
            3'b101: x_alu_result = div_quot; // DIVU (unsigned same for now)
            3'b110: x_alu_result = div_rem;  // REM
            3'b111: x_alu_result = div_rem;  // REMU
            default: x_alu_result = 0;
         endcase
    end else begin
        case (x_funct3_reg)
            3'b000: x_alu_result = (x_opcode_reg == OpcodeRegReg && x_funct7_reg[5]) ? sub_res : alu_sum; // ADD/SUB
            3'b001: x_alu_result = alu_sll;
            3'b010: x_alu_result = {31'b0, x_is_slt};
            3'b011: x_alu_result = {31'b0, x_is_sltu};
            3'b100: x_alu_result = alu_xor;
            3'b101: x_alu_result = (x_funct7_reg[5]) ? alu_sra : alu_srl;
            3'b110: x_alu_result = alu_or;
            3'b111: x_alu_result = alu_and;
            default: x_alu_result = 0;
        endcase
    end
  end

  // Branch Logic
  wire x_take_branch = (x_opcode_reg == OpcodeBranch) && (
      (x_funct3_reg == 3'b000 && x_eq) ||                  // BEQ
      (x_funct3_reg == 3'b001 && !x_eq) ||                 // BNE
      (x_funct3_reg == 3'b100 && $signed(sub_res[31])) ||  // BLT
      (x_funct3_reg == 3'b101 && !$signed(sub_res[31])) || // BGE
      (x_funct3_reg == 3'b110 && x_is_sltu) ||             // BLTU
      (x_funct3_reg == 3'b111 && !x_is_sltu)               // BGEU
  );

  assign execute_redirect = x_take_branch || (x_opcode_reg == OpcodeJal) || (x_opcode_reg == OpcodeJalr);
  
  // Calculate target PC
  wire [`REG_SIZE:0] pc_plus_imm = x_pc + x_imm;
  wire [`REG_SIZE:0] jalr_target = (x_rs1_forwarded + x_imm) & ~32'd1;
  
  assign x_target_pc = (x_opcode_reg == OpcodeJalr) ? jalr_target : pc_plus_imm;

  // For JAL/JALR, result is PC+4
  wire [`REG_SIZE:0] x_final_result = (x_opcode_reg == OpcodeJal || x_opcode_reg == OpcodeJalr) ? (x_pc + 4) : x_alu_result;


  /* MEMORY STAGE */
  
  // Pipeline Registers X->M
  reg [`REG_SIZE:0] m_pc;
  reg [`INST_SIZE:0] m_inst;
  reg [`REG_SIZE:0] m_alu_res_reg;
  reg [`REG_SIZE:0] m_store_data;
  reg m_reg_we_reg;
  reg m_is_load_reg;
  reg m_is_store_reg;
  reg [4:0] m_rd_reg;
  reg [2:0] m_funct3_reg;

  always @(posedge clk) begin
    if (rst) begin
        m_pc <= 0;
        m_inst <= 0;
        m_reg_we_reg <= 0;
        m_is_load_reg <= 0;
        m_is_store_reg <= 0;
    end else begin
        m_pc <= x_pc;
        m_inst <= x_inst;
        m_alu_res_reg <= x_final_result;
        m_store_data <= x_rs2_forwarded; // Data to store (before WM bypass)
        m_reg_we_reg <= x_reg_we_reg;
        m_is_load_reg <= x_is_load_reg;
        m_is_store_reg <= x_is_store_reg;
        m_rd_reg <= x_rd_reg;
        m_funct3_reg <= x_funct3_reg;
    end
  end
  
  // WM Bypass: Forward data from Writeback to Memory Stage for Stores
  reg [`REG_SIZE:0] m_final_store_data;
  always @(*) begin
    if (w_reg_we && w_rd != 0 && w_rd == m_inst[24:20]) // rs2 is bits 24:20
        m_final_store_data = w_rd_data;
    else
        m_final_store_data = m_store_data;
  end

  // Memory Interface Signals
  always @(*) begin
      addr_to_dmem = m_alu_res_reg;
      store_data_to_dmem = m_final_store_data;
  end
  
  always @(*) begin
    if (m_is_store_reg) begin
        case(m_funct3_reg)
            3'b000: store_we_to_dmem = 4'b0001; // SB
            3'b001: store_we_to_dmem = 4'b0011; // SH
            3'b010: store_we_to_dmem = 4'b1111; // SW
            default: store_we_to_dmem = 4'b0000;
        endcase
    end else begin
        store_we_to_dmem = 4'b0000;
    end
  end
  
  // Expose for Forwarding unit
  assign m_reg_we = m_reg_we_reg;
  assign m_rd = m_rd_reg;
  assign m_alu_result = m_alu_res_reg;


  /* WRITEBACK STAGE */
  
  // Pipeline Registers M->W
  reg [`REG_SIZE:0] w_pc;
  reg [`INST_SIZE:0] w_inst;
  reg [`REG_SIZE:0] w_alu_res_reg;
  reg [`REG_SIZE:0] w_load_data_reg;
  reg w_reg_we_reg;
  reg w_is_load_reg;
  reg [4:0] w_rd_reg;
  reg [2:0] w_funct3_reg;

  always @(posedge clk) begin
    if (rst) begin
        w_pc <= 0;
        w_inst <= 0;
        w_reg_we_reg <= 0;
    end else begin
        w_pc <= m_pc;
        w_inst <= m_inst;
        w_alu_res_reg <= m_alu_res_reg;
        w_load_data_reg <= load_data_from_dmem;
        w_reg_we_reg <= m_reg_we_reg;
        w_is_load_reg <= m_is_load_reg;
        w_rd_reg <= m_rd_reg;
        w_funct3_reg <= m_funct3_reg;
    end
  end

  // Load Data Processing
  reg [`REG_SIZE:0] w_final_load_data;
  always @(*) begin
      case(w_funct3_reg)
        3'b000: w_final_load_data = {{24{w_load_data_reg[7]}}, w_load_data_reg[7:0]};   // LB
        3'b001: w_final_load_data = {{16{w_load_data_reg[15]}}, w_load_data_reg[15:0]}; // LH
        3'b010: w_final_load_data = w_load_data_reg;                                    // LW
        3'b100: w_final_load_data = {24'b0, w_load_data_reg[7:0]};                      // LBU
        3'b101: w_final_load_data = {16'b0, w_load_data_reg[15:0]};                     // LHU
        default: w_final_load_data = w_load_data_reg;
      endcase
  end

  assign w_rd_data = w_is_load_reg ? w_final_load_data : w_alu_res_reg;
  assign w_reg_we = w_reg_we_reg;
  assign w_rd = w_rd_reg;

  // Trace Outputs
  always @(*) begin
      trace_writeback_pc = w_pc;
      trace_writeback_inst = w_inst;
  end
  
  always @(posedge clk) begin
      if (rst) halt <= 0;
      else if (w_inst[6:0] == OpcodeEnviron && w_inst[31:20] == 12'h000) halt <= 1; // ECALL causes halt for testbench
  end

endmodule

module MemorySingleCycle #(
    parameter NUM_WORDS = 512
) (
    input                    rst,                 // rst for both imem and dmem
    input                    clk,                 // clock for both imem and dmem
	                                              // The memory reads/writes on @(negedge clk)
    input      [`REG_SIZE:0] pc_to_imem,          // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] inst_from_imem,      // the value at memory location pc_to_imem
    input      [`REG_SIZE:0] addr_to_dmem,        // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] load_data_from_dmem, // the value at memory location addr_to_dmem
    input      [`REG_SIZE:0] store_data_to_dmem,  // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
    // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
    // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
    input      [        3:0] store_we_to_dmem
);

  // memory is arranged as an array of 4B words
  reg [`REG_SIZE:0] mem_array[0:NUM_WORDS-1];

  // preload instructions to mem_array
  initial begin
    $readmemh("mem_initial_contents.hex", mem_array);
  end

  localparam AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam AddrLsb = 2;

  always @(negedge clk) begin
    inst_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
  end

  always @(negedge clk) begin
    if (store_we_to_dmem[0]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
    end
    if (store_we_to_dmem[1]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
    end
    if (store_we_to_dmem[2]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
    end
    if (store_we_to_dmem[3]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
    end
    // dmem is "read-first": read returns value before the write
    load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
  end
endmodule

/* This design has just one clock for both processor and memory. */
  ; module Processor (
    input                 clk,
    input                 rst,
    output                halt,
    output [ `REG_SIZE:0] trace_writeback_pc,
    output [`INST_SIZE:0] trace_writeback_inst
);

  wire [`INST_SIZE:0] inst_from_imem;
  wire [ `REG_SIZE:0] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [         3:0] mem_data_we;

  // This wire is set by cocotb to the name of the currently-running test, to make it easier
  // to see what is going on in the waveforms.
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(
      .NUM_WORDS(8192)
  ) memory (
    .rst                 (rst),
    .clk                 (clk),
    // imem is read-only
    .pc_to_imem          (pc_to_imem),
    .inst_from_imem      (inst_from_imem),
    // dmem is read-write
    .addr_to_dmem        (mem_data_addr),
    .load_data_from_dmem (mem_data_loaded_value),
    .store_data_to_dmem  (mem_data_to_write),
    .store_we_to_dmem    (mem_data_we)
  );

  DatapathPipelined datapath (
    .clk                  (clk),
    .rst                  (rst),
    .pc_to_imem           (pc_to_imem),
    .inst_from_imem       (inst_from_imem),
    .addr_to_dmem         (mem_data_addr),
    .store_data_to_dmem   (mem_data_to_write),
    .store_we_to_dmem     (mem_data_we),
    .load_data_from_dmem  (mem_data_loaded_value),
    .halt                 (halt),
    .trace_writeback_pc   (trace_writeback_pc),
    .trace_writeback_inst (trace_writeback_inst)
  );

endmodule