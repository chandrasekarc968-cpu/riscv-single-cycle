module plic (
    input clk,
    input reset,
    
    // MMIO Interface
    input         req,
    input         we,
    input  [31:0] addr,
    input  [31:0] wdata,
    input  [3:0]  wmask,
    output reg [31:0] rdata,
    
    // Interrupt Sources (Source 0 is tied to 0)
    input  [31:1] irq_sources,
    
    // Context Outputs
    output core0_m_ext,
    output core0_s_ext,
    output core1_m_ext,
    output core1_s_ext
);

    // Contexts:
    // 0: Core 0 M-mode
    // 1: Core 0 S-mode
    // 2: Core 1 M-mode
    // 3: Core 1 S-mode

    // 1. Priorities (Sources 1-31)
    reg [2:0] priority [1:31]; // 3-bit priority (0-7), 0 means disabled
    
    // 2. Pending Bits
    reg [31:1] pending;
    
    // Edge detectors for IRQs
    reg [31:1] irq_sources_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) irq_sources_reg <= 31'b0;
        else irq_sources_reg <= irq_sources;
    end
    
    // 3. Enable Bits (per Context)
    reg [31:1] enables [0:3];
    
    // 4. Thresholds (per Context)
    reg [2:0] threshold [0:3];
    
    // Arbitration and Target Selection
    reg [4:0] max_id [0:3];
    reg [2:0] max_pri [0:3];
    
    integer c, i;
    always @(*) begin
        for (c = 0; c < 4; c = c + 1) begin
            max_id[c] = 0;
            max_pri[c] = 0;
            for (i = 1; i < 32; i = i + 1) begin
                if (pending[i] && enables[c][i] && (priority[i] > max_pri[c])) begin
                    max_pri[c] = priority[i];
                    max_id[c] = i;
                end
            end
        end
    end
    
    assign core0_m_ext = (max_pri[0] > threshold[0]);
    assign core0_s_ext = (max_pri[1] > threshold[1]);
    assign core1_m_ext = (max_pri[2] > threshold[2]);
    assign core1_s_ext = (max_pri[3] > threshold[3]);

    wire [31:0] rel_addr = addr - 32'h0C000000;
    
    integer j;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pending <= 31'b0;
            for (j = 1; j < 32; j = j + 1) priority[j] <= 0;
            for (j = 0; j < 4; j = j + 1) begin
                enables[j] <= 31'b0;
                threshold[j] <= 0;
            end
            rdata <= 0;
        end else begin
            // 1. Hardware sets pending bits on rising edge of IRQ
            for (j = 1; j < 32; j = j + 1) begin
                if (irq_sources[j] && !irq_sources_reg[j]) begin
                    pending[j] <= 1'b1;
                end
            end
            
            rdata <= 32'b0;
            
            if (req) begin
                if (we) begin
                    // Write Logic
                    if (rel_addr >= 32'h00000004 && rel_addr <= 32'h0000007C) begin
                        priority[rel_addr[6:2]] <= wdata[2:0];
                    end
                    else if (rel_addr == 32'h00002000) enables[0] <= wdata[31:1];
                    else if (rel_addr == 32'h00002080) enables[1] <= wdata[31:1];
                    else if (rel_addr == 32'h00002100) enables[2] <= wdata[31:1];
                    else if (rel_addr == 32'h00002180) enables[3] <= wdata[31:1];
                    
                    else if (rel_addr == 32'h00200000) threshold[0] <= wdata[2:0];
                    else if (rel_addr == 32'h00201000) threshold[1] <= wdata[2:0];
                    else if (rel_addr == 32'h00202000) threshold[2] <= wdata[2:0];
                    else if (rel_addr == 32'h00203000) threshold[3] <= wdata[2:0];
                    
                    else if (rel_addr == 32'h00200004) pending[wdata[4:0]] <= 1'b0; // Complete C0 M
                    else if (rel_addr == 32'h00201004) pending[wdata[4:0]] <= 1'b0; // Complete C0 S
                    else if (rel_addr == 32'h00202004) pending[wdata[4:0]] <= 1'b0; // Complete C1 M
                    else if (rel_addr == 32'h00203004) pending[wdata[4:0]] <= 1'b0; // Complete C1 S
                end else begin
                    // Read Logic
                    if (rel_addr >= 32'h00000004 && rel_addr <= 32'h0000007C) begin
                        rdata <= {29'b0, priority[rel_addr[6:2]]};
                    end
                    else if (rel_addr == 32'h00001000) rdata <= {pending, 1'b0};
                    
                    else if (rel_addr == 32'h00002000) rdata <= {enables[0], 1'b0};
                    else if (rel_addr == 32'h00002080) rdata <= {enables[1], 1'b0};
                    else if (rel_addr == 32'h00002100) rdata <= {enables[2], 1'b0};
                    else if (rel_addr == 32'h00002180) rdata <= {enables[3], 1'b0};
                    
                    else if (rel_addr == 32'h00200000) rdata <= {29'b0, threshold[0]};
                    else if (rel_addr == 32'h00201000) rdata <= {29'b0, threshold[1]};
                    else if (rel_addr == 32'h00202000) rdata <= {29'b0, threshold[2]};
                    else if (rel_addr == 32'h00203000) rdata <= {29'b0, threshold[3]};
                    
                    else if (rel_addr == 32'h00200004) begin rdata <= {27'b0, max_id[0]}; pending[max_id[0]] <= 1'b0; end // Claim C0 M
                    else if (rel_addr == 32'h00201004) begin rdata <= {27'b0, max_id[1]}; pending[max_id[1]] <= 1'b0; end // Claim C0 S
                    else if (rel_addr == 32'h00202004) begin rdata <= {27'b0, max_id[2]}; pending[max_id[2]] <= 1'b0; end // Claim C1 M
                    else if (rel_addr == 32'h00203004) begin rdata <= {27'b0, max_id[3]}; pending[max_id[3]] <= 1'b0; end // Claim C1 S
                end
            end
        end
    end
endmodule
