module alu (
    input       [31:0] srcA,
    input       [31:0] srcB,
    input       [3:0]  alu_control,
    output reg  [31:0] alu_result,
    output             zero
);

    always @(*) begin
        case (alu_control)
            4'b0000: alu_result = srcA + srcB;                             // ADD / ADDI / Load / Store
            4'b1000: alu_result = srcA - srcB;                             // SUB / Branch comparisons
            4'b0001: alu_result = srcA << srcB[4:0];                       // SLL / SLLI (Shift Left Logical)
            4'b0010: alu_result = ($signed(srcA) < $signed(srcB)) ? 1 : 0; // SLT / SLTI (Set Less Than, Signed)
            4'b0011: alu_result = (srcA < srcB) ? 1 : 0;                   // SLTU / SLTIU (Set Less Than, Unsigned)
            4'b0100: alu_result = srcA ^ srcB;                             // XOR / XORI
            4'b0101: alu_result = srcA >> srcB[4:0];                       // SRL / SRLI (Shift Right Logical)
            4'b1101: alu_result = $signed(srcA) >>> srcB[4:0];             // SRA / SRAI (Shift Right Arithmetic)
            4'b0110: alu_result = srcA | srcB;                             // OR / ORI
            4'b0111: alu_result = srcA & srcB;                             // AND / ANDI
            default: alu_result = 32'b0;                                   // Default case to prevent latches
        endcase
    end

    // The zero flag is set to 1 if the ALU result is exactly 0. 
    // This is primarily used by the Control Unit to evaluate BEQ (Branch if Equal) instructions.
    assign zero = (alu_result == 32'b0);

endmodule