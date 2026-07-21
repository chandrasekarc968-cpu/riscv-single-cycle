module main_memory #(
    parameter LATENCY = 4  // Number of wait cycles before memory responds (simulates DRAM latency)
) (
    input             clk,
    input             reset,
    input             req,      // Request memory operation
    input             we,       // Write enable (1 = block write 128-bit, 0 = block read 128-bit)
    input      [31:0] a,        // Address
    input      [127:0] wd,      // Write data (Cache Line, 4 words)
    output reg [127:0] rd,      // Read data (Cache Line, 4 words)
    output reg        ready     // High when operation is complete
);

    // 2,621,440 words = 10MB memory
    reg [31:0] RAM[2621439:0]; 

    // Initialize with program data
    initial begin
        $readmemh("program.hex", RAM);
    end

    reg [3:0] wait_counter;  // Supports up to LATENCY=15

    localparam IDLE = 0, WAITING = 1, DONE = 2;
    reg [1:0] state;

    // Block address (128-bit aligned = 4 words = 16 bytes)
    // a is a byte address, a[31:2] is word index.
    // To align to 4 words, clear the bottom 2 bits of the word index.
    wire [29:0] block_addr = a[31:2] & ~30'd3;

    // Word address for bounds checking
    wire [29:0] word_addr = a[31:2];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            ready <= 0;
            rd <= 0;
            wait_counter <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    if (req) begin
                        wait_counter <= 0;
                        state <= WAITING;
                    end
                end
                WAITING: begin
                    if (wait_counter >= LATENCY - 1) begin
                        state <= DONE;
                    end else begin
                        wait_counter <= wait_counter + 1;
                    end
                end
                DONE: begin
                    ready <= 1;

                    // Simulation-only: address bounds check
                    // synthesis translate_off
                    if (word_addr >= 2621440) begin
                        $display("WARNING [main_memory]: Address 0x%08x out of bounds (10MB limit)", a);
                    end
                    // synthesis translate_on

                    if (we) begin
                        RAM[block_addr]   <= wd[31:0];
                        RAM[block_addr+1] <= wd[63:32];
                        RAM[block_addr+2] <= wd[95:64];
                        RAM[block_addr+3] <= wd[127:96];
                    end else begin
                        rd <= {RAM[block_addr+3], RAM[block_addr+2], RAM[block_addr+1], RAM[block_addr]};
                    end
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
