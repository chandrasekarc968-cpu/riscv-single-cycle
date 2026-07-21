module bus_arbiter (
    input clk,
    input reset,
    
    // Core 0 Interface
    input         core0_req,
    input  [3:0]  core0_we,
    input  [31:0] core0_addr,
    input  [31:0] core0_wdata,
    output [127:0] core0_rdata,
    output        core0_ready,
    
    // Core 1 Interface
    input         core1_req,
    input  [3:0]  core1_we,
    input  [31:0] core1_addr,
    input  [31:0] core1_wdata,
    output [127:0] core1_rdata,
    output        core1_ready,
    
    // Main Memory Interface
    output        mem_req,
    output [3:0]  mem_we,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    input  [127:0] mem_rdata,
    input         mem_ready
);

    // State machine to lock the main memory to one core until request finishes
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
                    // Priority to Core 0 if both request simultaneously
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

    // Request to Main Memory
    assign mem_req = (state == IDLE) ? (core0_req | core1_req) : 1'b1;
    
    // Core 0 gets priority if IDLE and both request
    wire select_core0 = (state == SERVING_CORE0 || (state == IDLE && core0_req));
    
    assign mem_we    = select_core0 ? core0_we    : core1_we;
    assign mem_addr  = select_core0 ? core0_addr  : core1_addr;
    assign mem_wdata = select_core0 ? core0_wdata : core1_wdata;
    
    // Route read data and ready signals back
    assign core0_rdata = mem_rdata;
    assign core1_rdata = mem_rdata;
    
    assign core0_ready = (state == SERVING_CORE0) & mem_ready;
    assign core1_ready = (state == SERVING_CORE1) & mem_ready;

endmodule
