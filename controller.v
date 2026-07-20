// 1. Top-Level Controller Wrapper
module controller (
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7b5,
    input        zero,
    output       pc_src,
    output [1:0] result_src,
    output       mem_write,
    output [3:0] alu_control,
    output       alu_src,
    output [2:0] imm_src,
    output       reg_write
);

    wire [1:0] alu_op;
    wire       branch;
    wire       jump;

    // Instantiate Main Decoder
    maindec md (
        .op(op),
        .result_src(result_src),
        .mem_write(mem_write),
        .branch(branch),
        .alu_src(alu_src),
        .reg_write(reg_write),
        .jump(jump),
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

    // Old PC Logic:
    // assign pc_src = (branch & zero) | jump;

    // New PC Logic (Outputs 2 bits):
    // 00 = PC+4
    // 01 = PC+Imm (JAL or successful branch)
    // 10 = ALU Result (JALR)
    
    assign pc_src = jalr ? 2'b10 : 
                    ((branch & zero) | jump) ? 2'b01 : 
                    2'b00;
endmodule

// 2. Main Decoder
module maindec (
    input  [6:0] op,
    output reg [1:0] result_src,
    output reg       mem_write,
    output reg       branch,
    output reg       alu_src,
    output reg       reg_write,
    output reg       jump,
    output reg [2:0] imm_src,
    output reg [1:0] alu_op
);

    always @(*) begin
        // Default all signals to 0 to prevent accidental latches
        reg_write = 0; imm_src = 3'b000; alu_src = 0; mem_write = 0; 
        result_src = 2'b00; branch = 0; alu_op = 2'b00; jump = 0;
        
        case(op)
            7'b0000011: begin // Load (lw)
                reg_write = 1; imm_src = 3'b000; alu_src = 1; 
                result_src = 2'b01; alu_op = 2'b00; 
            end
            7'b0100011: begin // Store (sw)
                imm_src = 3'b001; alu_src = 1; mem_write = 1; 
                alu_op = 2'b00; 
            end
            7'b0110011: begin // R-type (add, sub, and, or, slt)
                reg_write = 1; alu_src = 0; result_src = 2'b00; 
                alu_op = 2'b10; 
            end
            7'b0010011: begin // I-type ALU (addi, andi, ori, slti)
                reg_write = 1; imm_src = 3'b000; alu_src = 1; 
                result_src = 2'b00; alu_op = 2'b10; 
            end
            7'b1100011: begin // Branch (beq)
                imm_src = 3'b010; alu_src = 0; branch = 1; 
                alu_op = 2'b01; 
            end
            7'b1101111: begin // Jump (jal)
                reg_write = 1; imm_src = 3'b011; jump = 1; 
                result_src = 2'b10; 
                // Add this case to the maindec case(op) block:
    7'b0110111: begin // LUI
        reg_write  = 1; 
        imm_src    = 3'b100; // U-type immediate
        result_src = 2'b11;  // Route imm_ext directly to Register File
        
        // Don't cares (set to 0 for safety)
        alu_src = 0; mem_write = 0; branch = 0; alu_op = 2'b00; jump = 0;
                  end
            end
            // Add this case to the maindec case(op) block:
    7'b1100111: begin // JALR
        reg_write  = 1; 
        imm_src    = 3'b000; // I-type immediate
        alu_src    = 1;      // Feed immediate to ALU
        alu_op     = 2'b00;  // Force ALU to ADD (rs1 + imm)
        result_src = 2'b10;  // Save PC+4 to Register File
        jalr       = 1;      // New signal!
        
        // Others
        branch = 0; jump = 0; mem_write = 0;
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
    // R-type subtraction only happens if op[5] is 1 (R-type, not I-type) AND funct7[5] is 1
    assign rtype_sub = funct7b5 & opb5; 

    always @(*) begin
        case(alu_op)
            2'b00: alu_control = 4'b0000; // Load/Store: Always ADD to calculate address
            2'b01: alu_control = 4'b1000; // Branch: Always SUB to compare values
            2'b10: begin                  // R-type or I-type ALU operations
                case(funct3)
                    3'b000: if (rtype_sub) alu_control = 4'b1000; // sub
                            else           alu_control = 4'b0000; // add / addi
                    3'b010: alu_control = 4'b0010;                // slt / slti
                    3'b110: alu_control = 4'b0110;                // or / ori
                    3'b111: alu_control = 4'b0111;                // and / andi
                    default: alu_control = 4'b0000;
                endcase
            end
            default: alu_control = 4'b0000;
        endcase
    end
endmodule