module dcache (
    input             clk,
    input             reset,
    
    // CPU Interface
    input      [31:0] cpu_addr,
    input      [31:0] cpu_wdata,
    input      [3:0]  cpu_wmask,
    input             cpu_req, // Asserted when memory is being accessed (mem_read or mem_write)
    output reg [31:0] cpu_rdata,
    output reg        cpu_stall,
    
    // Memory Interface
    output reg        mem_req,
    output reg [3:0]  mem_we,
    output reg [31:0] mem_addr,
    output reg [31:0] mem_wdata,
    input      [127:0] mem_rdata,
    input             mem_ready
);

    // Cache parameters: 64 lines, 16 bytes (4 words) per line = 1KB cache
    localparam NUM_LINES   = 64;
    localparam INDEX_BITS  = 6;   // log2(64)
    localparam OFFSET_BITS = 4;   // 16 bytes per line -> bits [3:0]
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS; // 22 bits

    reg [TAG_BITS-1:0]  tags  [NUM_LINES-1:0];
    reg                 valid [NUM_LINES-1:0];
    reg [127:0]         data  [NUM_LINES-1:0];
    
    wire [1:0]            word_offset = cpu_addr[3:2];
    wire [INDEX_BITS-1:0] index       = cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]; // [9:4]
    wire [TAG_BITS-1:0]   tag         = cpu_addr[31:INDEX_BITS+OFFSET_BITS];             // [31:10]
    
    wire hit = valid[index] && (tags[index] == tag);
    wire is_write = |cpu_wmask;
    
    // State machine: IDLE -> FETCH (read miss) or WRITEBACK (write-through to memory)
    //                FETCH -> IDLE (line filled)
    //                WRITEBACK -> WB_FILL (write-allocate: fetch line after write-through)
    //                WB_FILL -> IDLE (line filled and updated)
    reg [2:0] state;
    localparam IDLE      = 0,
               FETCH     = 1,
               WRITEBACK = 2,
               WB_FILL   = 3;

    // Latch the write request info so it persists across state transitions
    reg [3:0]  latched_wmask;
    reg [31:0] latched_wdata;
    reg [1:0]  latched_word_offset;
    
    always @(*) begin
        // Default combinational outputs
        cpu_stall = 0;
        mem_req = 0;
        mem_we = 0;
        mem_addr = cpu_addr;
        mem_wdata = cpu_wdata;
        
        // Cache read data mux
        case (word_offset)
            2'b00: cpu_rdata = data[index][31:0];
            2'b01: cpu_rdata = data[index][63:32];
            2'b10: cpu_rdata = data[index][95:64];
            2'b11: cpu_rdata = data[index][127:96];
        endcase

        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (is_write) begin
                        // Write-through: always stall to write to main memory
                        cpu_stall = 1;
                        mem_req = 1;
                        mem_we = cpu_wmask;
                    end else if (!hit) begin
                        // Read miss: fetch block from memory
                        cpu_stall = 1;
                        mem_req = 1;
                        mem_we = 4'b0000;
                    end
                    // Read hit: no stall, data is available combinationally
                end
            end
            FETCH: begin
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 4'b0000;
            end
            WRITEBACK: begin
                cpu_stall = 1;
                mem_req = 1;
                mem_we = latched_wmask;
            end
            WB_FILL: begin
                // Write-allocate: fetch the cache line after writing through
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 4'b0000;
            end
            default: begin
                cpu_stall = 0;
                mem_req = 0;
            end
        endcase
    end
    
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            latched_wmask <= 0;
            latched_wdata <= 0;
            latched_word_offset <= 0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid[i] <= 0;
                tags[i] <= 0;
                data[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (is_write) begin
                            // Latch write info for use across states
                            latched_wmask <= cpu_wmask;
                            latched_wdata <= cpu_wdata;
                            latched_word_offset <= word_offset;
                            state <= WRITEBACK;
                        end else if (!hit) begin
                            state <= FETCH;
                        end
                    end
                end
                FETCH: begin
                    // Read miss: fill cache line from memory
                    if (mem_ready) begin
                        valid[index] <= 1;
                        tags[index] <= tag;
                        data[index] <= mem_rdata;
                        state <= IDLE;
                    end
                end
                WRITEBACK: begin
                    // Write-through complete, now write-allocate (fetch the line)
                    if (mem_ready) begin
                        if (hit) begin
                            // Cache hit: update cache line in-place
                            if (latched_wmask[0]) data[index][(latched_word_offset*32) +:  8] <= latched_wdata[7:0];
                            if (latched_wmask[1]) data[index][(latched_word_offset*32)+8 +:  8] <= latched_wdata[15:8];
                            if (latched_wmask[2]) data[index][(latched_word_offset*32)+16 +: 8] <= latched_wdata[23:16];
                            if (latched_wmask[3]) data[index][(latched_word_offset*32)+24 +: 8] <= latched_wdata[31:24];
                            state <= IDLE;
                        end else begin
                            // Cache miss: fetch the line (write-allocate)
                            state <= WB_FILL;
                        end
                    end
                end
                WB_FILL: begin
                    // Write-allocate: fill cache line, then apply the write
                    if (mem_ready) begin
                        valid[index] <= 1;
                        tags[index] <= tag;
                        // Load line from memory, then overlay the written bytes
                        data[index] <= mem_rdata;
                        if (latched_wmask[0]) data[index][(latched_word_offset*32) +:  8] <= latched_wdata[7:0];
                        if (latched_wmask[1]) data[index][(latched_word_offset*32)+8 +:  8] <= latched_wdata[15:8];
                        if (latched_wmask[2]) data[index][(latched_word_offset*32)+16 +: 8] <= latched_wdata[23:16];
                        if (latched_wmask[3]) data[index][(latched_word_offset*32)+24 +: 8] <= latched_wdata[31:24];
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
