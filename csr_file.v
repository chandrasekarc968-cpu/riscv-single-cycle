module csr_file (
    input         clk,
    input         reset,
    
    // CPU CSR instruction interface
    input  [11:0] csr_addr,
    input  [31:0] csr_wdata,
    input         csr_we,
    output reg [31:0] csr_rdata,
    
    // Exception / Trap interface
    input         trap,          // Asserted to trigger a trap
    input  [31:0] trap_cause,    // Exception cause code
    input  [31:0] trap_pc,       // PC of the instruction that caused the trap
    input         mret,          // Asserted to return from a trap
    
    // Outputs to datapath
    output [31:0] epc,           // Address to return to
    output [31:0] trap_vector,   // Address to jump to on trap
    output        interrupt_en,  // Global interrupt enable
    input  [31:0] hartid         // Hardware thread ID
);

    // CSRs
    reg [31:0] mstatus; // Machine Status
    reg [31:0] mtvec;   // Machine Trap Vector Base Address
    reg [31:0] mepc;    // Machine Exception PC
    reg [31:0] mcause;  // Machine Cause

    // mstatus bit definitions
    // bit 3 = MIE (Machine Interrupt Enable)
    // bit 7 = MPIE (Machine Previous Interrupt Enable)
    
    assign epc = mepc;
    assign trap_vector = mtvec;
    assign interrupt_en = mstatus[3];

    // CSR Read
    always @(*) begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'hF14: csr_rdata = hartid;
            default: csr_rdata = 32'b0;
        endcase
    end

    // CSR Write and Trap Handling
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mstatus <= 32'b0;
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
        end else if (trap) begin
            // Hardware trap logic
            mepc <= trap_pc;
            mcause <= trap_cause;
            // MPIE = MIE, MIE = 0
            mstatus[7] <= mstatus[3];
            mstatus[3] <= 1'b0;
        end else if (mret) begin
            // Hardware MRET logic
            // MIE = MPIE
            mstatus[3] <= mstatus[7];
            // MPIE is usually set to 1, but we'll leave it as is for simplicity or set to 1.
            mstatus[7] <= 1'b1;
        end else if (csr_we) begin
            // Software CSR write
            case (csr_addr)
                12'h300: mstatus <= csr_wdata;
                12'h305: mtvec   <= csr_wdata;
                12'h341: mepc    <= csr_wdata;
                12'h342: mcause  <= csr_wdata;
            endcase
        end
    end
endmodule
