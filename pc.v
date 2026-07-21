module pc (
    input             clk,
    input             reset,
    input             en,
    input      [31:0] pc_next,
    output reg [31:0] pc
);

    // The PC updates on the rising edge of the clock or when reset is triggered
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'h00000000; // On reset, start at memory address 0
        end else if (en) begin
            pc <= pc_next;      // Otherwise, jump to the next calculated address if enabled
        end
    end

endmodule