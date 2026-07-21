module bus_arbiter (
    input clk,
    input reset,
    
    // Core 0 Interface
    input         core0_req,
    input         core0_we,
    input  [31:0] core0_addr,
    input  [127:0] core0_wdata,
    output [127:0] core0_rdata,
    output        core0_ready,
    output        core0_is_shared,
    
    // Core 1 Interface
    input         core1_req,
    input         core1_we,
    input  [31:0] core1_addr,
    input  [127:0] core1_wdata,
    output [127:0] core1_rdata,
    output        core1_ready,
    output        core1_is_shared,
    
    // Snoop Interfaces
    output        core0_snoop_req,
    output        core0_snoop_is_write,
    output [31:0] core0_snoop_addr,
    input         core0_snoop_hit,
    input         core0_snoop_dirty,
    input  [127:0] core0_snoop_rdata,

    output        core1_snoop_req,
    output        core1_snoop_is_write,
    output [31:0] core1_snoop_addr,
    input         core1_snoop_hit,
    input         core1_snoop_dirty,
    input  [127:0] core1_snoop_rdata,

    // Main Memory / L3 Interface
    output        mem_req,
    output        mem_we,
    output [31:0] mem_addr,
    output [127:0] mem_wdata,
    input  [127:0] mem_rdata,
    input         mem_ready
);

    reg [1:0] state;
    localparam IDLE = 0,
               SERVING_CORE0 = 1,
               SERVING_CORE1 = 2;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (core0_req) state <= SERVING_CORE0;
                    else if (core1_req) state <= SERVING_CORE1;
                end
                SERVING_CORE0: begin
                    if (mem_ready) state <= IDLE;
                end
                SERVING_CORE1: begin
                    if (mem_ready) state <= IDLE;
                end
            endcase
        end
    end

    wire select_core0 = (state == SERVING_CORE0 || (state == IDLE && core0_req));
    wire select_core1 = (state == SERVING_CORE1 || (state == IDLE && !core0_req && core1_req));

    // Snoop Broadcast Logic (Always Snoop the Non-Requesting Core)
    assign core1_snoop_req      = select_core0 ? core0_req : 1'b0;
    assign core1_snoop_is_write = core0_we;
    assign core1_snoop_addr     = core0_addr;

    assign core0_snoop_req      = select_core1 ? core1_req : 1'b0;
    assign core0_snoop_is_write = core1_we;
    assign core0_snoop_addr     = core1_addr;

    // Coherency State Evaluation
    assign core0_is_shared = core1_snoop_hit && !core0_we;
    assign core1_is_shared = core0_snoop_hit && !core1_we;

    wire active_we   = select_core0 ? core0_we : core1_we;
    wire active_addr = select_core0 ? core0_addr : core1_addr;
    wire [127:0] active_wdata = select_core0 ? core0_wdata : core1_wdata;

    wire active_snoop_dirty = select_core0 ? core1_snoop_dirty : core0_snoop_dirty;
    wire [127:0] active_snoop_rdata = select_core0 ? core1_snoop_rdata : core0_snoop_rdata;

    // Is this a Cache-to-Cache Transfer?
    // Occurs when reading a memory location that the other core has Modified (dirty).
    wire cache_to_cache_transfer = (!active_we) && active_snoop_dirty;

    // Request to Main Memory / L3
    assign mem_req = (state == IDLE) ? (core0_req | core1_req) : 1'b1;
    
    // If Cache-to-Cache, we must FORCE a write to L3 to update memory, saving the dirty data.
    assign mem_we    = cache_to_cache_transfer ? 1'b1 : active_we;
    assign mem_addr  = select_core0 ? core0_addr : core1_addr;
    assign mem_wdata = cache_to_cache_transfer ? active_snoop_rdata : active_wdata;
    
    // Response Routing
    // If Cache-to-Cache, we intercept the dirty data and send it directly back to the requesting core!
    assign core0_rdata = (select_core0 && cache_to_cache_transfer) ? core1_snoop_rdata : mem_rdata;
    assign core1_rdata = (select_core1 && cache_to_cache_transfer) ? core0_snoop_rdata : mem_rdata;
    
    assign core0_ready = (state == SERVING_CORE0) & mem_ready;
    assign core1_ready = (state == SERVING_CORE1) & mem_ready;

endmodule
