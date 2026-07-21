module dcache (
    input             clk,
    input             reset,
    
    // CPU Interface
    input      [31:0] cpu_addr,
    input      [31:0] cpu_wdata,
    input      [3:0]  cpu_wmask,
    input             cpu_req,
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

    // 2-Way Set Associative Cache parameters: 32 sets, 2 ways, 16 bytes per line = 1KB cache
    localparam NUM_SETS    = 32;
    localparam INDEX_BITS  = 5;   // log2(32)
    localparam OFFSET_BITS = 4;   // 16 bytes per line
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS; // 23 bits

    // Way 0 Arrays
    reg [TAG_BITS-1:0]  tags_0  [NUM_SETS-1:0];
    reg                 valid_0 [NUM_SETS-1:0];
    reg [127:0]         data_0  [NUM_SETS-1:0];
    
    // Way 1 Arrays
    reg [TAG_BITS-1:0]  tags_1  [NUM_SETS-1:0];
    reg                 valid_1 [NUM_SETS-1:0];
    reg [127:0]         data_1  [NUM_SETS-1:0];
    
    // LRU state (0 = Way 0 is LRU, 1 = Way 1 is LRU)
    reg                 lru     [NUM_SETS-1:0];
    
    wire [1:0]            word_offset = cpu_addr[3:2];
    wire [INDEX_BITS-1:0] index       = cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]; // [8:4]
    wire [TAG_BITS-1:0]   tag         = cpu_addr[31:INDEX_BITS+OFFSET_BITS];             // [31:9]
    
    wire hit_0 = valid_0[index] && (tags_0[index] == tag);
    wire hit_1 = valid_1[index] && (tags_1[index] == tag);
    wire hit   = hit_0 || hit_1;
    wire is_write = |cpu_wmask;
    
    // Select correct line on a hit
    wire [127:0] hit_line = hit_1 ? data_1[index] : data_0[index];
    
    // Determine which way to replace on a miss
    // If way 0 is invalid, pick way 0. Else if way 1 is invalid, pick way 1. Else pick LRU way.
    wire replace_way = (!valid_0[index]) ? 1'b0 :
                       (!valid_1[index]) ? 1'b1 : 
                       lru[index];
    
    reg [2:0] state;
    localparam IDLE      = 0,
               FETCH     = 1,
               WRITEBACK = 2,
               WB_FILL   = 3;

    // Latch the write request info
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
            2'b00: cpu_rdata = hit_line[31:0];
            2'b01: cpu_rdata = hit_line[63:32];
            2'b10: cpu_rdata = hit_line[95:64];
            2'b11: cpu_rdata = hit_line[127:96];
        endcase

        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (is_write) begin
                        cpu_stall = 1;
                        mem_req = 1;
                        mem_we = cpu_wmask;
                    end else if (!hit) begin
                        cpu_stall = 1;
                        mem_req = 1;
                        mem_we = 4'b0000;
                    end
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
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 4'b0000;
            end
        endcase
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_0[i] <= 0;
                valid_1[i] <= 0;
                lru[i]     <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (is_write) begin
                            latched_wmask <= cpu_wmask;
                            latched_wdata <= cpu_wdata;
                            latched_word_offset <= word_offset;
                            state <= WRITEBACK;
                        end else if (hit) begin
                            // Update LRU on read hit
                            if (hit_0) lru[index] <= 1'b1; // Mark 0 as recently used, so replace 1 next
                            else       lru[index] <= 1'b0;
                        end else begin
                            state <= FETCH;
                        end
                    end
                end
                
                FETCH: begin
                    if (mem_ready) begin
                        // Fill cache line
                        if (replace_way == 1'b0) begin
                            valid_0[index] <= 1;
                            tags_0[index]  <= tag;
                            data_0[index]  <= mem_rdata;
                            lru[index]     <= 1'b1; // Way 0 just used, point LRU to way 1
                        end else begin
                            valid_1[index] <= 1;
                            tags_1[index]  <= tag;
                            data_1[index]  <= mem_rdata;
                            lru[index]     <= 1'b0; // Way 1 just used, point LRU to way 0
                        end
                        state <= IDLE;
                    end
                end
                
                WRITEBACK: begin
                    if (mem_ready) begin
                        if (hit) begin
                            // Update the hit way with the written word (write-through)
                            if (hit_0) begin
                                case (latched_word_offset)
                                    2'b00: begin
                                        if (latched_wmask[0]) data_0[index][7:0]   <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_0[index][15:8]  <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_0[index][23:16] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_0[index][31:24] <= latched_wdata[31:24];
                                    end
                                    2'b01: begin
                                        if (latched_wmask[0]) data_0[index][39:32] <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_0[index][47:40] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_0[index][55:48] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_0[index][63:56] <= latched_wdata[31:24];
                                    end
                                    2'b10: begin
                                        if (latched_wmask[0]) data_0[index][71:64] <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_0[index][79:72] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_0[index][87:80] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_0[index][95:88] <= latched_wdata[31:24];
                                    end
                                    2'b11: begin
                                        if (latched_wmask[0]) data_0[index][103:96]  <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_0[index][111:104] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_0[index][119:112] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_0[index][127:120] <= latched_wdata[31:24];
                                    end
                                endcase
                                lru[index] <= 1'b1;
                            end else begin
                                case (latched_word_offset)
                                    2'b00: begin
                                        if (latched_wmask[0]) data_1[index][7:0]   <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_1[index][15:8]  <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_1[index][23:16] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_1[index][31:24] <= latched_wdata[31:24];
                                    end
                                    2'b01: begin
                                        if (latched_wmask[0]) data_1[index][39:32] <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_1[index][47:40] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_1[index][55:48] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_1[index][63:56] <= latched_wdata[31:24];
                                    end
                                    2'b10: begin
                                        if (latched_wmask[0]) data_1[index][71:64] <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_1[index][79:72] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_1[index][87:80] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_1[index][95:88] <= latched_wdata[31:24];
                                    end
                                    2'b11: begin
                                        if (latched_wmask[0]) data_1[index][103:96]  <= latched_wdata[7:0];
                                        if (latched_wmask[1]) data_1[index][111:104] <= latched_wdata[15:8];
                                        if (latched_wmask[2]) data_1[index][119:112] <= latched_wdata[23:16];
                                        if (latched_wmask[3]) data_1[index][127:120] <= latched_wdata[31:24];
                                    end
                                endcase
                                lru[index] <= 1'b0;
                            end
                            state <= IDLE;
                        end else begin
                            // Write miss: write-allocate -> fetch the updated line from memory
                            state <= WB_FILL;
                        end
                    end
                end
                
                WB_FILL: begin
                    if (mem_ready) begin
                        // Load the block which now includes our write
                        if (replace_way == 1'b0) begin
                            valid_0[index] <= 1;
                            tags_0[index]  <= tag;
                            data_0[index]  <= mem_rdata;
                            lru[index]     <= 1'b1;
                        end else begin
                            valid_1[index] <= 1;
                            tags_1[index]  <= tag;
                            data_1[index]  <= mem_rdata;
                            lru[index]     <= 1'b0;
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
