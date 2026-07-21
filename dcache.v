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

    // Cache parameters: 16 lines, 16 bytes (4 words) per line.
    reg [23:0]  tags [15:0];
    reg         valid [15:0];
    reg [127:0] data [15:0];
    
    wire [1:0]  word_offset = cpu_addr[3:2];
    wire [3:0]  index       = cpu_addr[7:4];
    wire [23:0] tag         = cpu_addr[31:8];
    
    wire hit = valid[index] && (tags[index] == tag);
    wire is_write = |cpu_wmask;
    
    reg [1:0] state;
    localparam IDLE = 0, FETCH = 1, WRITE = 2;
    
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

        if (state == IDLE) begin
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
            end
        end else if (state == FETCH || state == WRITE) begin
            cpu_stall = 1;
            mem_req = 1;
            if (state == WRITE) mem_we = cpu_wmask;
            else mem_we = 4'b0000;
        end
    end
    
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < 16; i = i + 1) begin
                valid[i] <= 0;
                tags[i] <= 0;
                data[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (is_write) state <= WRITE;
                        else if (!hit) state <= FETCH;
                    end
                end
                FETCH: begin
                    if (mem_ready) begin
                        valid[index] <= 1;
                        tags[index] <= tag;
                        data[index] <= mem_rdata;
                        state <= IDLE;
                    end
                end
                WRITE: begin
                    if (mem_ready) begin
                        // Update cache if it's a hit, so we read the new data later
                        if (hit) begin
                            if (cpu_wmask[0]) data[index][(word_offset*32) +: 8]   <= cpu_wdata[7:0];
                            if (cpu_wmask[1]) data[index][(word_offset*32)+8 +: 8] <= cpu_wdata[15:8];
                            if (cpu_wmask[2]) data[index][(word_offset*32)+16 +: 8]<= cpu_wdata[23:16];
                            if (cpu_wmask[3]) data[index][(word_offset*32)+24 +: 8]<= cpu_wdata[31:24];
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
