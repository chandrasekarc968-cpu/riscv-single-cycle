module block_cache #(
    parameter WAYS = 4,
    parameter SETS = 64,
    parameter INDEX_BITS = 6
) (
    input clk,
    input reset,
    
    // Upstream (Closer to CPU)
    input          up_req,
    input          up_we,
    input  [31:0]  up_addr,
    input  [127:0] up_wdata,
    output reg [127:0] up_rdata,
    output reg         up_ready,
    
    // Downstream (Closer to Memory)
    output reg         down_req,
    output reg         down_we,
    output reg [31:0]  down_addr,
    output reg [127:0] down_wdata,
    input  [127:0] down_rdata,
    input              down_ready,
    input              down_is_shared, // When fetching, does another core have it?
    
    // Snoop Interface (From Bus)
    input              snoop_req,
    input              snoop_is_write,
    input  [31:0]      snoop_addr,
    output reg         snoop_hit,
    output reg         snoop_dirty,
    output reg [127:0] snoop_rdata
);

    localparam OFFSET_BITS = 4;
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
    
    localparam MESI_I = 2'b00;
    localparam MESI_S = 2'b01;
    localparam MESI_E = 2'b10;
    localparam MESI_M = 2'b11;

    reg [TAG_BITS-1:0] tags [SETS*WAYS-1:0];
    reg [1:0]          mesi [SETS*WAYS-1:0];
    reg [127:0]        data [SETS*WAYS-1:0];
    
    reg [3:0] replace_ptr [SETS-1:0];

    wire [INDEX_BITS-1:0] index = up_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag   = up_addr[31:INDEX_BITS+OFFSET_BITS];

    // Main Hit Logic
    reg [3:0] hit_way;
    reg       hit;
    reg [1:0] hit_mesi;
    
    integer w;
    always @(*) begin
        hit = 0;
        hit_way = 0;
        hit_mesi = MESI_I;
        for (w = 0; w < WAYS; w = w + 1) begin
            if (mesi[index * WAYS + w] != MESI_I && (tags[index * WAYS + w] == tag)) begin
                hit = 1;
                hit_way = w;
                hit_mesi = mesi[index * WAYS + w];
            end
        end
    end

    wire local_hit = up_we ? (hit && (hit_mesi == MESI_E || hit_mesi == MESI_M)) : hit;

    wire [3:0] evict_way = replace_ptr[index];
    wire [1:0] evict_mesi = mesi[index * WAYS + evict_way];
    wire [TAG_BITS-1:0] evict_tag = tags[index * WAYS + evict_way];

    // Snoop Hit Logic
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:INDEX_BITS+OFFSET_BITS];

    reg [3:0] snp_way;
    integer sw;
    always @(*) begin
        snoop_hit = 0;
        snp_way = 0;
        for (sw = 0; sw < WAYS; sw = sw + 1) begin
            if (mesi[snoop_index * WAYS + sw] != MESI_I && tags[snoop_index * WAYS + sw] == snoop_tag) begin
                snoop_hit = 1;
                snp_way = sw;
            end
        end
        snoop_dirty = snoop_hit && (mesi[snoop_index * WAYS + snp_way] == MESI_M);
        snoop_rdata = snoop_hit ? data[snoop_index * WAYS + snp_way] : 128'b0;
    end

    reg [1:0] state;
    localparam IDLE    = 0,
               EVICT   = 1,
               FETCH   = 2,
               UPGRADE = 3;

    always @(*) begin
        up_ready = 0;
        up_rdata = 128'b0;
        down_req = 0;
        down_we  = 0;
        down_addr = 32'b0;
        down_wdata = 128'b0;

        case (state)
            IDLE: begin
                if (up_req && local_hit) begin
                    up_ready = 1;
                    up_rdata = data[index * WAYS + hit_way];
                end
            end
            UPGRADE: begin
                down_req = 1;
                down_we  = 1;
                down_addr = {tag, index, 4'b0000};
                down_wdata = up_wdata; // Write through the new block
            end
            EVICT: begin
                down_req = 1;
                down_we  = 1;
                down_addr = {evict_tag, index, 4'b0000};
                down_wdata = data[index * WAYS + evict_way];
            end
            FETCH: begin
                down_req = 1;
                down_we  = 0;
                down_addr = {tag, index, 4'b0000};
            end
        endcase
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < SETS*WAYS; i = i + 1) begin
                mesi[i] <= MESI_I;
            end
            for (i = 0; i < SETS; i = i + 1) begin
                replace_ptr[i] <= 0;
            end
        end else begin
            // 1. Process Snoop Requests (Highest Priority)
            if (snoop_req && snoop_hit) begin
                if (snoop_is_write) begin
                    mesi[snoop_index * WAYS + snp_way] <= MESI_I; // Invalidate
                end else begin
                    mesi[snoop_index * WAYS + snp_way] <= MESI_S; // Downgrade to Shared
                end
            end
            
            // 2. Process CPU/Upstream Requests
            case (state)
                IDLE: begin
                    if (up_req) begin
                        if (local_hit) begin
                            if (up_we) begin
                                data[index * WAYS + hit_way] <= up_wdata;
                                mesi[index * WAYS + hit_way] <= MESI_M; // Upgrade to Modified
                            end
                        end else if (hit && up_we && hit_mesi == MESI_S) begin
                            state <= UPGRADE;
                        end else begin
                            if (evict_mesi == MESI_M) state <= EVICT;
                            else state <= FETCH;
                        end
                    end
                end
                
                UPGRADE: begin
                    if (down_ready) begin
                        data[index * WAYS + hit_way] <= up_wdata;
                        mesi[index * WAYS + hit_way] <= MESI_E; // Exclusive (we just wrote it through, now we own it)
                        state <= IDLE;
                    end
                end
                
                EVICT: begin
                    if (down_ready) begin
                        state <= FETCH;
                    end
                end
                
                FETCH: begin
                    if (down_ready) begin
                        tags[index * WAYS + evict_way]  <= tag;
                        data[index * WAYS + evict_way]  <= (up_we) ? up_wdata : down_rdata;
                        
                        if (up_we) mesi[index * WAYS + evict_way] <= MESI_M;
                        else mesi[index * WAYS + evict_way] <= down_is_shared ? MESI_S : MESI_E;
                        
                        if (replace_ptr[index] == WAYS - 1)
                            replace_ptr[index] <= 0;
                        else
                            replace_ptr[index] <= replace_ptr[index] + 1;
                            
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
