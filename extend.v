module extend (
    input      [31:7] instr,    // We only need bits 31 down to 7 for immediates
    input      [2:0]  imm_src,  // Control signal to choose the format
    output reg [31:0] imm_ext
);

    always @(*) begin
        case (imm_src)
            // I-Type (e.g., ADDI, LW)
            // 12-bit immediate at instr[31:20]
            3'b000: imm_ext = {{20{instr[31]}}, instr[31:20]};
            
            // S-Type (e.g., SW)
            // 12-bit immediate split: instr[31:25] and instr[11:7]
            3'b001: imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            
            // B-Type (e.g., BEQ)
            // 13-bit immediate (even multiples only, so 0 at the end)
            // Split: instr[31], instr[7], instr[30:25], instr[11:8]
            3'b010: imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            
            // J-Type (e.g., JAL)
            // 21-bit immediate (even multiples only, so 0 at the end)
            // Split: instr[31], instr[19:12], instr[20], instr[30:21]
            3'b011: imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            
            // U-Type (e.g., LUI, AUIPC)
            // 20-bit immediate shifted left by 12 bits
            3'b100: imm_ext = {instr[31:12], 12'b0};
            
            default: imm_ext = 32'b0; // Default case
        endcase
    end

endmodule