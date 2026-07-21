module regfile (
    input             clk,
    input             we3,       // Write Enable
    input      [4:0]  a1,        // Read Address 1 (rs1)
    input      [4:0]  a2,        // Read Address 2 (rs2)
    input      [4:0]  a3,        // Write Address (rd)
    input      [31:0] wd3,       // Write Data
    output     [31:0] rd1,       // Read Data 1
    output     [31:0] rd2        // Read Data 2
);

    // Create an array of 32 registers, each 32 bits wide
    reg [31:0] rf [31:0];

    // Simulation-only: initialize all registers to zero to avoid X-values in waveforms
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'b0;
    end
    // synthesis translate_on

    // Synchronous Write: Happens strictly on the rising edge of the clock
    always @(posedge clk) begin
        // Only write if Write Enable is high AND the target register is not x0 (address 0)
        if (we3 && (a3 != 5'b00000)) begin
            rf[a3] <= wd3;
        end
    end

    // Asynchronous Read: Data is available immediately when the address changes
    // If the address is 0, always output 32 bits of zero (RISC-V requirement for x0)
    assign rd1 = (a1 != 5'b00000) ? rf[a1] : 32'b0;
    assign rd2 = (a2 != 5'b00000) ? rf[a2] : 32'b0;

endmodule