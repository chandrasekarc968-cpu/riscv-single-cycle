module memory_arbiter (
    input clk,
    input reset,
    
    // I-Cache Interface
    input         icache_req,
    input  [31:0] icache_addr,
    output [127:0] icache_rdata,
    output        icache_ready,
    
    // D-Cache Interface
    input         dcache_req,
    input         dcache_we,
    input  [31:0] dcache_addr,
    input  [127:0] dcache_wdata,
    output [127:0] dcache_rdata,
    output        dcache_ready,
    
    // Snoop Interface from L2 -> D-Cache
    input         snoop_req,
    input         snoop_is_write,
    input  [31:0] snoop_addr,
    output        snoop_hit,
    output        snoop_dirty,
    output [127:0] snoop_rdata,
    
    // D-Cache is_shared signal
    output        dcache_is_shared,
    
    // Downstream Memory Interface (To L2 Cache)
    output        mem_req,
    output        mem_we,
    output [31:0] mem_addr,
    output [127:0] mem_wdata,
    input  [127:0] mem_rdata,
    input         mem_ready,
    input         mem_is_shared
);

    // Pass-through Snoop signals directly to D-Cache
    // (I-Cache is read-only, so we assume no self-modifying code for now)
    assign snoop_hit = 1'b0; // Will be connected in top.v, wait, arbiter needs to pass them? 
    // Actually, if we just wire them straight in top.v, we don't even need them in arbiter.v!
    // But since top.v connects D-Cache to Arbiter, it's cleaner to let top.v connect them directly to D-Cache.
    // Wait, D-Cache and I-Cache are instantiated in top.v, right next to arbiter.v.
    // We don't even need to route snoop signals through arbiter.v!
    
    // Let's just output mem_is_shared so top.v can route it to dcache.
    assign dcache_is_shared = mem_is_shared;

    // State machine to handle multi-cycle memory requests
    // We lock the arbiter to one master until the request completes.
    reg [1:0] state;
    localparam IDLE = 0,
               SERVING_DCACHE = 1,
               SERVING_ICACHE = 2;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (dcache_req) state <= SERVING_DCACHE;
                    else if (icache_req) state <= SERVING_ICACHE;
                end
                SERVING_DCACHE: begin
                    if (mem_ready) state <= IDLE;
                end
                SERVING_ICACHE: begin
                    if (mem_ready) state <= IDLE;
                end
            endcase
        end
    end

    // Combinational routing
    assign mem_req = (state == IDLE) ? (dcache_req | icache_req) : 1'b1;
    
    assign mem_we = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_we : 1'b0;
    
    assign mem_addr = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_addr : icache_addr;
    
    assign mem_wdata = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_wdata : 128'b0;

    // Responses
    assign dcache_rdata = mem_rdata;
    assign icache_rdata = mem_rdata;
    
    assign dcache_ready = (state == SERVING_DCACHE) && mem_ready;
    assign icache_ready = (state == SERVING_ICACHE) && mem_ready;

endmodule
