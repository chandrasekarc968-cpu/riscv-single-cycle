module icache (
    input             clk,
    input             reset,
    
    // CPU Interface
    input      [31:0] cpu_addr,
    input             cpu_req, // High when CPU wants to read instruction
    output reg [31:0] cpu_rdata,
    output reg        cpu_stall,
    
    // Memory Interface
    output reg        mem_req,
    output reg [31:0] mem_addr,
    input     [127:0] mem_rdata,
    input             mem_ready
);

    // Direct-Mapped Cache parameters: 64 lines, 16 bytes per line = 1KB cache
    localparam NUM_LINES   = 64;
    localparam INDEX_BITS  = 6;   // log2(64)
    localparam OFFSET_BITS = 4;   // 16 bytes per line
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS; // 22 bits

    reg [TAG_BITS-1:0]  tags  [NUM_LINES-1:0];
    reg                 valid [NUM_LINES-1:0];
    reg [127:0]         data  [NUM_LINES-1:0];
    
    wire [1:0]            word_offset = cpu_addr[3:2];
    wire [INDEX_BITS-1:0] index       = cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag         = cpu_addr[31:INDEX_BITS+OFFSET_BITS];
    
    wire hit = valid[index] && (tags[index] == tag);
    
    reg state;
    localparam IDLE  = 0,
               FETCH = 1;

    always @(*) begin
        cpu_stall = 0;
        mem_req = 0;
        mem_addr = cpu_addr;
        
        case (word_offset)
            2'b00: cpu_rdata = data[index][31:0];
            2'b01: cpu_rdata = data[index][63:32];
            2'b10: cpu_rdata = data[index][95:64];
            2'b11: cpu_rdata = data[index][127:96];
        endcase

        case (state)
            IDLE: begin
                if (cpu_req && !hit) begin
                    cpu_stall = 1;
                    mem_req = 1;
                end
            end
            FETCH: begin
                cpu_stall = 1;
                mem_req = 1;
            end
        endcase
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req && !hit) begin
                        state <= FETCH;
                    end
                end
                
                FETCH: begin
                    if (mem_ready) begin
                        valid[index] <= 1;
                        tags[index]  <= tag;
                        data[index]  <= mem_rdata;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
