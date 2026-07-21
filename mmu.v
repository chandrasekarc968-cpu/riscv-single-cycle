module mmu (
    input clk,
    input reset,
    
    input [31:0] satp,
    
    // CPU I-Side
    input         i_req,
    input  [31:0] i_va,
    output [31:0] i_pa,
    output        i_stall,
    output        i_page_fault,
    
    // CPU D-Side
    input         d_req,
    input         d_we,
    input  [31:0] d_va,
    output [31:0] d_pa,
    output        d_stall,
    output        d_page_fault,
    
    // PTW Memory Interface (Routes to D-Cache)
    output reg        ptw_req,
    output reg [31:0] ptw_addr,
    input      [31:0] ptw_rdata, // 32-bit word from cache
    input             ptw_ready
);

    wire mode = satp[31];
    wire [21:0] root_ppn = satp[21:0];

    // TLB Definitions
    localparam TLB_ENTRIES = 16;
    reg [19:0] itlb_vpn  [TLB_ENTRIES-1:0];
    reg [19:0] itlb_ppn  [TLB_ENTRIES-1:0];
    reg [7:0]  itlb_flag [TLB_ENTRIES-1:0];
    reg        itlb_v    [TLB_ENTRIES-1:0];

    reg [19:0] dtlb_vpn  [TLB_ENTRIES-1:0];
    reg [19:0] dtlb_ppn  [TLB_ENTRIES-1:0];
    reg [7:0]  dtlb_flag [TLB_ENTRIES-1:0];
    reg        dtlb_v    [TLB_ENTRIES-1:0];

    reg [3:0] itlb_replace_ptr;
    reg [3:0] dtlb_replace_ptr;

    wire [19:0] i_vpn = i_va[31:12];
    wire [19:0] d_vpn = d_va[31:12];

    // ITLB Lookup
    reg itlb_hit;
    reg [19:0] itlb_hit_ppn;
    reg [7:0]  itlb_hit_flag;
    integer i;
    always @(*) begin
        itlb_hit = 0;
        itlb_hit_ppn = 20'b0;
        itlb_hit_flag = 8'b0;
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
            if (itlb_v[i] && itlb_vpn[i] == i_vpn) begin
                itlb_hit = 1;
                itlb_hit_ppn = itlb_ppn[i];
                itlb_hit_flag = itlb_flag[i];
            end
        end
    end

    // DTLB Lookup
    reg dtlb_hit;
    reg [19:0] dtlb_hit_ppn;
    reg [7:0]  dtlb_hit_flag;
    integer d;
    always @(*) begin
        dtlb_hit = 0;
        dtlb_hit_ppn = 20'b0;
        dtlb_hit_flag = 8'b0;
        for (d = 0; d < TLB_ENTRIES; d = d + 1) begin
            if (dtlb_v[d] && dtlb_vpn[d] == d_vpn) begin
                dtlb_hit = 1;
                dtlb_hit_ppn = dtlb_ppn[d];
                dtlb_hit_flag = dtlb_flag[d];
            end
        end
    end

    // Translators
    assign i_pa = (mode == 0) ? i_va : {itlb_hit_ppn, i_va[11:0]};
    assign d_pa = (mode == 0) ? d_va : {dtlb_hit_ppn, d_va[11:0]};

    // Stalls & Faults
    wire i_miss = mode && i_req && !itlb_hit;
    wire d_miss = mode && d_req && !dtlb_hit;

    // PTW State Machine
    reg [2:0] ptw_state;
    localparam PTW_IDLE    = 0,
               PTW_L1_REQ  = 1,
               PTW_L1_WAIT = 2,
               PTW_L0_REQ  = 3,
               PTW_L0_WAIT = 4;

    reg ptw_is_iside; // 1 = Fetching for ITLB, 0 = Fetching for DTLB
    reg [19:0] ptw_vpn;
    reg [31:0] ptw_pte_l1;

    assign i_stall = i_miss || (ptw_state != PTW_IDLE && ptw_is_iside);
    assign d_stall = d_miss || (ptw_state != PTW_IDLE && !ptw_is_iside);
    
    // Very simplified fault logic
    assign i_page_fault = (mode && i_req && itlb_hit && (itlb_hit_flag[3] == 0)); // X=0
    assign d_page_fault = (mode && d_req && dtlb_hit && 
                          (d_we ? (dtlb_hit_flag[2] == 0) : (dtlb_hit_flag[1] == 0))); // W=0 / R=0

    wire [9:0] vpn1 = ptw_vpn[19:10];
    wire [9:0] vpn0 = ptw_vpn[9:0];

    always @(*) begin
        ptw_req = 0;
        ptw_addr = 32'b0;
        
        case (ptw_state)
            PTW_L1_REQ: begin
                ptw_req = 1;
                ptw_addr = {root_ppn[19:0], vpn1, 2'b00}; // root_ppn * 4096 + vpn1 * 4
            end
            PTW_L0_REQ: begin
                ptw_req = 1;
                ptw_addr = {ptw_pte_l1[29:10], vpn0, 2'b00}; // pte.ppn * 4096 + vpn0 * 4
            end
        endcase
    end

    integer j;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ptw_state <= PTW_IDLE;
            itlb_replace_ptr <= 0;
            dtlb_replace_ptr <= 0;
            for (j = 0; j < TLB_ENTRIES; j = j + 1) begin
                itlb_v[j] <= 0;
                dtlb_v[j] <= 0;
            end
        end else begin
            // Whenever satp changes, flush the TLB (simplified SFENCE.VMA)
            // We can just detect a write to SATP in top.v and trigger a reset,
            // or just let it happen naturally if this was a real OS.
            // For now, assume SFENCE.VMA resets the MMU.
            
            case (ptw_state)
                PTW_IDLE: begin
                    if (d_miss) begin
                        ptw_state <= PTW_L1_REQ;
                        ptw_is_iside <= 0;
                        ptw_vpn <= d_vpn;
                    end else if (i_miss) begin
                        ptw_state <= PTW_L1_REQ;
                        ptw_is_iside <= 1;
                        ptw_vpn <= i_vpn;
                    end
                end
                
                PTW_L1_REQ: begin
                    ptw_state <= PTW_L1_WAIT;
                end
                
                PTW_L1_WAIT: begin
                    if (ptw_ready) begin
                        ptw_pte_l1 <= ptw_rdata;
                        if (ptw_rdata[0] == 0) begin
                            // Invalid PTE! Just map it as invalid in TLB to trigger a page fault next cycle
                            if (ptw_is_iside) begin
                                itlb_v[itlb_replace_ptr] <= 1;
                                itlb_vpn[itlb_replace_ptr] <= ptw_vpn;
                                itlb_flag[itlb_replace_ptr] <= 8'b0; // Invalid flags
                                itlb_replace_ptr <= itlb_replace_ptr + 1;
                            end else begin
                                dtlb_v[dtlb_replace_ptr] <= 1;
                                dtlb_vpn[dtlb_replace_ptr] <= ptw_vpn;
                                dtlb_flag[dtlb_replace_ptr] <= 8'b0;
                                dtlb_replace_ptr <= dtlb_replace_ptr + 1;
                            end
                            ptw_state <= PTW_IDLE;
                        end else if ((ptw_rdata[3:1] != 3'b000)) begin
                            // Leaf PTE (Megapage)
                            if (ptw_is_iside) begin
                                itlb_v[itlb_replace_ptr] <= 1;
                                itlb_vpn[itlb_replace_ptr] <= ptw_vpn;
                                itlb_ppn[itlb_replace_ptr] <= {ptw_rdata[29:20], ptw_vpn[9:0]}; // Megapage PPN
                                itlb_flag[itlb_replace_ptr] <= ptw_rdata[7:0];
                                itlb_replace_ptr <= itlb_replace_ptr + 1;
                            end else begin
                                dtlb_v[dtlb_replace_ptr] <= 1;
                                dtlb_vpn[dtlb_replace_ptr] <= ptw_vpn;
                                dtlb_ppn[dtlb_replace_ptr] <= {ptw_rdata[29:20], ptw_vpn[9:0]};
                                dtlb_flag[dtlb_replace_ptr] <= ptw_rdata[7:0];
                                dtlb_replace_ptr <= dtlb_replace_ptr + 1;
                            end
                            ptw_state <= PTW_IDLE;
                        end else begin
                            // Pointer to L0
                            ptw_state <= PTW_L0_REQ;
                        end
                    end
                end
                
                PTW_L0_REQ: begin
                    ptw_state <= PTW_L0_WAIT;
                end
                
                PTW_L0_WAIT: begin
                    if (ptw_ready) begin
                        if (ptw_is_iside) begin
                            itlb_v[itlb_replace_ptr] <= 1;
                            itlb_vpn[itlb_replace_ptr] <= ptw_vpn;
                            itlb_ppn[itlb_replace_ptr] <= ptw_rdata[29:10];
                            itlb_flag[itlb_replace_ptr] <= ptw_rdata[7:0];
                            itlb_replace_ptr <= itlb_replace_ptr + 1;
                        end else begin
                            dtlb_v[dtlb_replace_ptr] <= 1;
                            dtlb_vpn[dtlb_replace_ptr] <= ptw_vpn;
                            dtlb_ppn[dtlb_replace_ptr] <= ptw_rdata[29:10];
                            dtlb_flag[dtlb_replace_ptr] <= ptw_rdata[7:0];
                            dtlb_replace_ptr <= dtlb_replace_ptr + 1;
                        end
                        ptw_state <= PTW_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
