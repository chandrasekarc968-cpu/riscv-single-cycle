module imem (
    input      [31:0] a,
    output     [31:0] rd
);
    // 4096 words = 16KB instruction memory
    reg [31:0] RAM[4095:0];

    initial begin
        $readmemh("program.hex", RAM);
    end

    wire [11:0] word_addr = a[13:2]; // 12-bit word index for 4096 entries
    assign rd = RAM[word_addr];

    // Simulation-only: warn if PC exceeds IMEM bounds
    // synthesis translate_off
    always @(*) begin
        if (a[31:14] != 0 && a !== 32'bx)
            $display("WARNING [imem]: PC 0x%08x exceeds 16KB instruction memory", a);
    end
    // synthesis translate_on

endmodule
