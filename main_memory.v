module main_memory (
    input             clk,
    input             reset,
    input             req,      // Request memory operation
    input      [3:0]  we,       // Write enable mask (word write if != 0, block read if == 0)
    input      [31:0] a,        // Address
    input      [31:0] wd,       // Write data (Word)
    output reg [127:0] rd,      // Read data (Cache Line, 4 words)
    output reg        ready     // High when operation is complete
);

    // 1024 words = 4KB memory
    reg [31:0] RAM[1023:0]; 

    // Initialize with program data
    initial begin
        // Note: program.hex will be loaded by imem.v natively, but for unified memory we load it here too.
        $readmemh("program.hex", RAM);
    end

    reg [2:0] state;
    localparam IDLE = 0, WAIT1 = 1, WAIT2 = 2, WAIT3 = 3, DONE = 4;

    // Block address (128-bit aligned = 4 words = 16 bytes)
    // a is a byte address, a[31:2] is word index.
    // To align to 4 words, clear the bottom 2 bits of the word index.
    wire [29:0] block_addr = a[31:2] & ~30'd3;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            ready <= 0;
            rd <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    if (req) begin
                        state <= WAIT1;
                    end
                end
                WAIT1: state <= WAIT2;
                WAIT2: state <= WAIT3;
                WAIT3: state <= DONE;
                DONE: begin
                    ready <= 1;
                    if (|we) begin
                        if (we[0]) RAM[a[31:2]][7:0]   <= wd[7:0];
                        if (we[1]) RAM[a[31:2]][15:8]  <= wd[15:8];
                        if (we[2]) RAM[a[31:2]][23:16] <= wd[23:16];
                        if (we[3]) RAM[a[31:2]][31:24] <= wd[31:24];
                    end else begin
                        rd <= {RAM[block_addr+3], RAM[block_addr+2], RAM[block_addr+1], RAM[block_addr]};
                    end
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
