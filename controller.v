// 1. Top-Level Controller Wrapper
module controller (
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7b5,
    output [2:0] result_src,
    output       mem_write,
    output [3:0] alu_control,
    output       alu_src,
    output [2:0] imm_src,
    output       reg_write,
    output       jump,
    output       jalr,
    output       branch
);

    wire [1:0] alu_op;

    // Instantiate Main Decoder
    maindec md (
        .op(op),
        .result_src(result_src),
        .mem_write(mem_write),
        .branch(branch),
        .alu_src(alu_src),
        .reg_write(reg_write),
        .jump(jump),
        .jalr(jalr),
        .imm_src(imm_src),
        .alu_op(alu_op)
    );

    // Instantiate ALU Decoder
    aludec ad (
        .opb5(op[5]),
        .funct3(funct3),
        .funct7b5(funct7b5),
        .alu_op(alu_op),
        .alu_control(alu_control)
    );

endmodule

// 2. Main Decoder
module maindec (
    input  [6:0] op,
    output reg [2:0] result_src,
    output reg       mem_write,
    output reg       branch,
    output reg       alu_src,
    output reg       reg_write,
    output reg       jump,
    output reg       jalr,
    output reg [2:0] imm_src,
    output reg [1:0] alu_op
);

    always @(*) begin
        // Default all signals to 0 to prevent accidental latches
        reg_write = 0; imm_src = 3'b000; alu_src = 0; mem_write = 0; 
        result_src = 3'b000; branch = 0; alu_op = 2'b00; jump = 0; jalr = 0;
        
        case(op)
            7'b0000011: begin // Load (lw, lh, lb, lhu, lbu)
                reg_write = 1; imm_src = 3'b000; alu_src = 1; 
                result_src = 3'b001; alu_op = 2'b00; 
            end
            7'b0100011: begin // Store (sw, sh, sb)
                imm_src = 3'b001; alu_src = 1; mem_write = 1; 
                alu_op = 2'b00; 
            end
            7'b0110011: begin // R-type
                reg_write = 1; alu_src = 0; result_src = 3'b000; 
                alu_op = 2'b10; 
            end
            7'b0010011: begin // I-type ALU
                reg_write = 1; imm_src = 3'b000; alu_src = 1; 
                result_src = 3'b000; alu_op = 2'b10; 
            end
            7'b1100011: begin // Branch
                imm_src = 3'b010; alu_src = 0; branch = 1; 
                alu_op = 2'b01; 
            end
            7'b1101111: begin // Jump (jal)
                reg_write = 1; imm_src = 3'b011; jump = 1; 
                result_src = 3'b010; 
            end
            7'b1100111: begin // JALR
                reg_write = 1; imm_src = 3'b000; alu_src = 1; jalr = 1;
                result_src = 3'b010; alu_op = 2'b00; 
            end
            7'b0110111: begin // LUI
                reg_write = 1; imm_src = 3'b100; result_src = 3'b011;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1; imm_src = 3'b100; result_src = 3'b100;
            end
        endcase
    end
endmodule

// 3. ALU Decoder
module aludec (
    input        opb5,
    input  [2:0] funct3,
    input        funct7b5,
    input  [1:0] alu_op,
    output reg [3:0] alu_control
);

    wire rtype_sub;
    assign rtype_sub = funct7b5 & opb5; 

    always @(*) begin
        case(alu_op)
            2'b00: alu_control = 4'b0000; // Load/Store/JALR: ADD
            2'b01: begin                  // Branches
                case(funct3)
                    3'b000, 3'b001: alu_control = 4'b1000; // BEQ, BNE use SUB
                    3'b100, 3'b101: alu_control = 4'b0010; // BLT, BGE use SLT
                    3'b110, 3'b111: alu_control = 4'b0011; // BLTU, BGEU use SLTU
                    default: alu_control = 4'b1000;
                endcase
            end
            2'b10: begin                  // R-type or I-type ALU operations
                case(funct3)
                    3'b000: if (rtype_sub) alu_control = 4'b1000; // sub
                            else           alu_control = 4'b0000; // add / addi
                    3'b001: alu_control = 4'b0001;                // sll / slli
                    3'b010: alu_control = 4'b0010;                // slt / slti
                    3'b011: alu_control = 4'b0011;                // sltu / sltiu
                    3'b100: alu_control = 4'b0100;                // xor / xori
                    3'b101: if (funct7b5)  alu_control = 4'b1101; // sra / srai
                            else           alu_control = 4'b0101; // srl / srli
                    3'b110: alu_control = 4'b0110;                // or / ori
                    3'b111: alu_control = 4'b0111;                // and / andi
                    default: alu_control = 4'b0000;
                endcase
            end
            default: alu_control = 4'b0000;
        endcase
    end
endmodule