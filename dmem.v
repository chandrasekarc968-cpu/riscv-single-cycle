module dmem (
    input             clk,
    input      [3:0]  we,    // Write Enable Mask (1 bit per byte)
    input      [31:0] a,     // Memory Address (calculated by the ALU)
    input      [31:0] wd,    // Write Data
    output     [31:0] rd     // Read Data
);

    // Create a memory array: 256 words deep (1024 bytes).
    reg [31:0] RAM[255:0];

    // Combinational Read: Data is available immediately when the address arrives.
    // We drop the bottom 2 bits (a[31:2]) to convert the byte address to a word index.
    assign rd = RAM[a[31:2]];

    // Synchronous Write with byte enables
    always @(posedge clk) begin
        if (we[0]) RAM[a[31:2]][7:0]   <= wd[7:0];
        if (we[1]) RAM[a[31:2]][15:8]  <= wd[15:8];
        if (we[2]) RAM[a[31:2]][23:16] <= wd[23:16];
        if (we[3]) RAM[a[31:2]][31:24] <= wd[31:24];
    end

endmodule