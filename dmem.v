module dmem (
    input             clk,
    input             we,    // Write Enable (High for Store instructions)
    input      [31:0] a,     // Memory Address (calculated by the ALU)
    input      [31:0] wd,    // Write Data (from the Register File)
    output     [31:0] rd     // Read Data (to the Register File)
);

    // Create a memory array: 256 words deep (1024 bytes). 
    // You can increase this size if you need more RAM!
    reg [31:0] RAM[255:0];

    // Combinational Read: Data is available immediately when the address arrives.
    // Like instruction memory, addresses are byte-aligned.
    // We drop the bottom 2 bits (a[31:2]) to convert the byte address to a word index.
    assign rd = RAM[a[31:2]];

    // Synchronous Write: Data is saved strictly on the rising edge of the clock.
    always @(posedge clk) begin
        if (we) begin
            RAM[a[31:2]] <= wd;
        end
    end

endmodule