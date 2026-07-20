module riscv (
    input         clk,
    input         reset,
    input  [31:0] instr,
    input  [31:0] read_data,
    output [31:0] pc,
    output [31:0] alu_result,
    output [31:0] write_data,
    output        mem_write
);

    // Internal wires for Datapath and Control
    wire       pc_src, alu_src, reg_write, zero;
    wire [1:0] result_src;
    wire [2:0] imm_src;
    wire [3:0] alu_control;
    
    wire [31:0] pc_next, pc_plus_4, pc_target;
    wire [31:0] imm_ext;
    wire [31:0] srcA, srcB;
    wire [31:0] result;

    // ---------------------------------------------------------
    // CONTROL UNIT
    // ---------------------------------------------------------
    controller c (
        .op(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7b5(instr[30]),
        .zero(zero),
        .pc_src(pc_src),
        .result_src(result_src),
        .mem_write(mem_write),
        .alu_control(alu_control),
        .alu_src(alu_src),
        .imm_src(imm_src),
        .reg_write(reg_write)
    );

    // ---------------------------------------------------------
    // DATAPATH
    // ---------------------------------------------------------
    
    // PC Logic (Multiplexers and PC Register)
    assign pc_plus_4 = pc + 32'd4;
    assign pc_target = pc + imm_ext;
    assign pc_next   = pc_src ? pc_target : pc_plus_4;

    pc pcreg (
        .clk(clk),
        .reset(reset),
        .pc_next(pc_next),
        .pc(pc)
    );

    // Register File
    regfile rf (
        .clk(clk),
        .we3(reg_write),
        .a1(instr[19:15]),
        .a2(instr[24:20]),
        .a3(instr[11:7]),
        .wd3(result),
        .rd1(srcA),
        .rd2(write_data) // rd2 goes directly to Data Memory write port
    );

    // Immediate Extension
    extend ext (
        .instr(instr[31:7]),
        .imm_src(imm_src),
        .imm_ext(imm_ext)
    );

    // ALU
    assign srcB = alu_src ? imm_ext : write_data;

    alu alu_inst (
        .srcA(srcA),
        .srcB(srcB),
        .alu_control(alu_control),
        .alu_result(alu_result),
        .zero(zero)
    );

    // Writeback Logic (Multiplexer sending data back to RegFile)
    assign result = (result_src == 2'b00) ? alu_result :
                    (result_src == 2'b01) ? read_data :
                                            pc_plus_4;

endmodule