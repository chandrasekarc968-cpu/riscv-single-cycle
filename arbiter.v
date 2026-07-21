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
    input  [3:0]  dcache_we,
    input  [31:0] dcache_addr,
    input  [31:0] dcache_wdata,
    output [127:0] dcache_rdata,
    output        dcache_ready,
    
    // Main Memory Interface
    output        mem_req,
    output [3:0]  mem_we,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    input  [127:0] mem_rdata,
    input         mem_ready
);

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
    
    assign mem_we = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_we : 4'b0000;
    
    assign mem_addr = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_addr : icache_addr;
    
    assign mem_wdata = (state == SERVING_DCACHE || (state == IDLE && dcache_req)) ? dcache_wdata : 32'b0;

    // Responses
    assign dcache_rdata = mem_rdata;
    assign icache_rdata = mem_rdata;
    
    assign dcache_ready = (state == SERVING_DCACHE) && mem_ready;
    assign icache_ready = (state == SERVING_ICACHE) && mem_ready;

endmodule
