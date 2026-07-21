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
    
    // Memory Interface (To Arbiter -> L2)
    output reg        mem_req,
    output reg        mem_we,
    output reg [31:0] mem_addr,
    output reg [127:0] mem_wdata,
    input      [127:0] mem_rdata,
    input             mem_ready,
    input             mem_is_shared,
    
    // Snoop Interface (From Arbiter)
    input             snoop_req,
    input             snoop_is_write,
    input      [31:0] snoop_addr,
    output reg        snoop_hit,
    output reg        snoop_dirty,
    output reg [127:0] snoop_rdata
);

    localparam NUM_SETS    = 32;
    localparam INDEX_BITS  = 5;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;

    localparam MESI_I = 2'b00;
    localparam MESI_S = 2'b01;
    localparam MESI_E = 2'b10;
    localparam MESI_M = 2'b11;

    reg [TAG_BITS-1:0]  tags_0  [NUM_SETS-1:0];
    reg [1:0]           mesi_0  [NUM_SETS-1:0];
    reg [127:0]         data_0  [NUM_SETS-1:0];
    
    reg [TAG_BITS-1:0]  tags_1  [NUM_SETS-1:0];
    reg [1:0]           mesi_1  [NUM_SETS-1:0];
    reg [127:0]         data_1  [NUM_SETS-1:0];
    
    reg                 lru     [NUM_SETS-1:0];
    
    wire [1:0]            word_offset = cpu_addr[3:2];
    wire [INDEX_BITS-1:0] index       = cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag         = cpu_addr[31:INDEX_BITS+OFFSET_BITS];
    
    wire hit_0 = (mesi_0[index] != MESI_I) && (tags_0[index] == tag);
    wire hit_1 = (mesi_1[index] != MESI_I) && (tags_1[index] == tag);
    wire hit   = hit_0 || hit_1;
    wire [1:0] hit_mesi = hit_1 ? mesi_1[index] : mesi_0[index];
    wire is_write = |cpu_wmask;
    
    wire local_hit = is_write ? (hit && (hit_mesi == MESI_E || hit_mesi == MESI_M)) : hit;
    
    wire [127:0] hit_line = hit_1 ? data_1[index] : data_0[index];
    
    wire replace_way = (mesi_0[index] == MESI_I) ? 1'b0 :
                       (mesi_1[index] == MESI_I) ? 1'b1 : 
                       lru[index];

    wire [1:0] replace_mesi = replace_way ? mesi_1[index] : mesi_0[index];
    wire [TAG_BITS-1:0] replace_tag = replace_way ? tags_1[index] : tags_0[index];
    
    // Snoop Logic
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:INDEX_BITS+OFFSET_BITS];

    wire snp_hit_0 = (mesi_0[snoop_index] != MESI_I) && (tags_0[snoop_index] == snoop_tag);
    wire snp_hit_1 = (mesi_1[snoop_index] != MESI_I) && (tags_1[snoop_index] == snoop_tag);
    
    always @(*) begin
        snoop_hit = snp_hit_0 || snp_hit_1;
        snoop_dirty = (snp_hit_0 && mesi_0[snoop_index] == MESI_M) || (snp_hit_1 && mesi_1[snoop_index] == MESI_M);
        snoop_rdata = snp_hit_1 ? data_1[snoop_index] : (snp_hit_0 ? data_0[snoop_index] : 128'b0);
    end

    // Combinational Write-Through Logic
    // In UPGRADE, we need to send the full 128-bit block with the word modified.
    reg [127:0] upgraded_block;
    always @(*) begin
        upgraded_block = hit_line;
        case (word_offset)
            2'b00: begin
                if (cpu_wmask[0]) upgraded_block[7:0]   = cpu_wdata[7:0];
                if (cpu_wmask[1]) upgraded_block[15:8]  = cpu_wdata[15:8];
                if (cpu_wmask[2]) upgraded_block[23:16] = cpu_wdata[23:16];
                if (cpu_wmask[3]) upgraded_block[31:24] = cpu_wdata[31:24];
            end
            2'b01: begin
                if (cpu_wmask[0]) upgraded_block[39:32] = cpu_wdata[7:0];
                if (cpu_wmask[1]) upgraded_block[47:40] = cpu_wdata[15:8];
                if (cpu_wmask[2]) upgraded_block[55:48] = cpu_wdata[23:16];
                if (cpu_wmask[3]) upgraded_block[63:56] = cpu_wdata[31:24];
            end
            2'b10: begin
                if (cpu_wmask[0]) upgraded_block[71:64] = cpu_wdata[7:0];
                if (cpu_wmask[1]) upgraded_block[79:72] = cpu_wdata[15:8];
                if (cpu_wmask[2]) upgraded_block[87:80] = cpu_wdata[23:16];
                if (cpu_wmask[3]) upgraded_block[95:88] = cpu_wdata[31:24];
            end
            2'b11: begin
                if (cpu_wmask[0]) upgraded_block[103:96]  = cpu_wdata[7:0];
                if (cpu_wmask[1]) upgraded_block[111:104] = cpu_wdata[15:8];
                if (cpu_wmask[2]) upgraded_block[119:112] = cpu_wdata[23:16];
                if (cpu_wmask[3]) upgraded_block[127:120] = cpu_wdata[31:24];
            end
        endcase
    end
    
    reg [1:0] state;
    localparam IDLE    = 0,
               EVICT   = 1,
               FETCH   = 2,
               UPGRADE = 3;

    always @(*) begin
        cpu_stall = 0;
        mem_req = 0;
        mem_we = 0;
        mem_addr = cpu_addr;
        mem_wdata = 128'b0;
        
        case (word_offset)
            2'b00: cpu_rdata = hit_line[31:0];
            2'b01: cpu_rdata = hit_line[63:32];
            2'b10: cpu_rdata = hit_line[95:64];
            2'b11: cpu_rdata = hit_line[127:96];
        endcase

        case (state)
            IDLE: begin
                if (cpu_req && !local_hit) begin
                    cpu_stall = 1;
                end
            end
            UPGRADE: begin
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 1;
                mem_addr = {tag, index, 4'b0000};
                mem_wdata = upgraded_block;
            end
            EVICT: begin
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 1;
                mem_addr = {replace_tag, index, 4'b0000};
                mem_wdata = replace_way ? data_1[index] : data_0[index];
            end
            FETCH: begin
                cpu_stall = 1;
                mem_req = 1;
                mem_we = 0;
                mem_addr = {tag, index, 4'b0000};
            end
        endcase
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                mesi_0[i] <= MESI_I;
                mesi_1[i] <= MESI_I;
                lru[i] <= 0;
            end
        end else begin
            // 1. Process Snoop Requests
            if (snoop_req && snoop_hit) begin
                if (snp_hit_0) mesi_0[snoop_index] <= snoop_is_write ? MESI_I : MESI_S;
                if (snp_hit_1) mesi_1[snoop_index] <= snoop_is_write ? MESI_I : MESI_S;
            end
            
            // 2. Process CPU
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (local_hit) begin
                            if (is_write) begin
                                if (hit_0) begin
                                    data_0[index] <= upgraded_block;
                                    mesi_0[index] <= MESI_M;
                                    lru[index] <= 1'b1;
                                end else begin
                                    data_1[index] <= upgraded_block;
                                    mesi_1[index] <= MESI_M;
                                    lru[index] <= 1'b0;
                                end
                            end else begin
                                lru[index] <= hit_0 ? 1'b1 : 1'b0;
                            end
                        end else if (hit && is_write && hit_mesi == MESI_S) begin
                            state <= UPGRADE;
                        end else begin
                            if (replace_mesi == MESI_M) state <= EVICT;
                            else state <= FETCH;
                        end
                    end
                end
                
                UPGRADE: begin
                    if (mem_ready) begin
                        if (hit_0) begin
                            data_0[index] <= upgraded_block;
                            mesi_0[index] <= MESI_E;
                            lru[index] <= 1'b1;
                        end else begin
                            data_1[index] <= upgraded_block;
                            mesi_1[index] <= MESI_E;
                            lru[index] <= 1'b0;
                        end
                        state <= IDLE;
                    end
                end
                
                EVICT: begin
                    if (mem_ready) begin
                        state <= FETCH;
                    end
                end
                
                FETCH: begin
                    if (mem_ready) begin
                        if (replace_way == 1'b0) begin
                            mesi_0[index] <= is_write ? MESI_M : (mem_is_shared ? MESI_S : MESI_E);
                            tags_0[index] <= tag;
                            data_0[index] <= is_write ? upgraded_block : mem_rdata;
                            lru[index] <= 1'b1;
                        end else begin
                            mesi_1[index] <= is_write ? MESI_M : (mem_is_shared ? MESI_S : MESI_E);
                            tags_1[index] <= tag;
                            data_1[index] <= is_write ? upgraded_block : mem_rdata;
                            lru[index] <= 1'b0;
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
