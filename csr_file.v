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
    input         sret,          // Asserted to return from S-mode trap
    output reg    trap_illegal,  // Asserted if a privilege violation occurs
    
    // Outputs to datapath
    output [31:0] epc,           // Address to return to
    output [31:0] trap_vector,   // Address to jump to on trap
    output        interrupt_en,  // Global interrupt enable
    input  [31:0] hartid,        // Hardware thread ID
    output [1:0]  priv_out,      // Current privilege level
    
    // External Interrupts (from PLIC)
    input         ext_intr_m,    // M-mode external interrupt
    input         ext_intr_s,    // S-mode external interrupt
    
    // Virtual Memory
    output [31:0] satp_out       // Supervisor Address Translation and Protection
);

    // Current Privilege Level
    reg [1:0] priv; // 3 = M, 1 = S, 0 = U
    assign priv_out = priv;

    // M-Mode CSRs
    reg [31:0] mstatus; 
    reg [31:0] mtvec;   
    reg [31:0] mepc;    
    reg [31:0] mcause;  
    reg [31:0] mideleg; // Interrupt Delegation
    reg [31:0] medeleg; // Exception Delegation

    // S-Mode CSRs
    reg [31:0] stvec;
    reg [31:0] sepc;
    reg [31:0] scause;
    reg [31:0] satp;
    
    // mstatus bit definitions
    // bit 1 = SIE
    // bit 3 = MIE 
    // bit 5 = SPIE
    // bit 7 = MPIE 
    // bit 8 = SPP (1 bit)
    // bits 12:11 = MPP (2 bits)

    assign satp_out = satp;

    // Trap routing logic
    // We delegate to S-mode if the trap is delegated AND we are not currently in M-mode
    wire is_interrupt = trap_cause[31];
    wire [30:0] cause_code = trap_cause[30:0];
    
    wire delegated = is_interrupt ? mideleg[cause_code] : medeleg[cause_code];
    wire trap_to_s = delegated && (priv <= 2'b01);

    assign epc = trap_to_s ? sepc : mepc;
    assign trap_vector = trap_to_s ? stvec : mtvec;
    
    // Interrupt enable (simplified)
    // If in M-mode, MIE matters. If in S-mode, SIE matters. 
    // If in U-mode, both M and S interrupts are globally enabled.
    assign interrupt_en = (priv == 2'b11) ? mstatus[3] : 
                          (priv == 2'b01) ? mstatus[1] : 1'b1;

    // Access Control Logic
    wire [1:0] required_priv = csr_addr[9:8];
    wire read_only = (csr_addr[11:10] == 2'b11);
    wire priv_violation = (priv < required_priv) || (csr_we && read_only);

    // CSR Read
    always @(*) begin
        if (priv_violation) begin
            csr_rdata = 32'b0;
        end else begin
            case (csr_addr)
                // Supervisor CSRs
                12'h100: csr_rdata = mstatus & 32'h00000122; // sstatus (restricted view of mstatus: SPP, SPIE, SIE)
                12'h105: csr_rdata = stvec;
                12'h141: csr_rdata = sepc;
                12'h142: csr_rdata = scause;
                12'h180: csr_rdata = satp;
                
                // Machine CSRs
                12'h300: csr_rdata = mstatus;
                12'h302: csr_rdata = medeleg;
                12'h303: csr_rdata = mideleg;
                12'h305: csr_rdata = mtvec;
                12'h341: csr_rdata = mepc;
                12'h342: csr_rdata = mcause;
                12'hF14: csr_rdata = hartid;
                default: csr_rdata = 32'b0;
            endcase
        end
    end

    // CSR Write and Trap Handling
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            priv    <= 2'b11; // Boot in M-mode
            mstatus <= 32'b0;
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
            mideleg <= 32'b0;
            medeleg <= 32'b0;
            stvec   <= 32'b0;
            sepc    <= 32'b0;
            scause  <= 32'b0;
            satp    <= 32'b0;
            trap_illegal <= 1'b0;
        end else begin
            trap_illegal <= 1'b0;
            
            if (csr_we && priv_violation) begin
                trap_illegal <= 1'b1;
            end else if (trap) begin
                if (trap_to_s) begin
                    // Trap to S-mode
                    sepc <= trap_pc;
                    scause <= trap_cause;
                    mstatus[8] <= priv[0];    // SPP = priv[0]
                    mstatus[5] <= mstatus[1]; // SPIE = SIE
                    mstatus[1] <= 1'b0;       // SIE = 0
                    priv <= 2'b01;            // Enter S-mode
                end else begin
                    // Trap to M-mode
                    mepc <= trap_pc;
                    mcause <= trap_cause;
                    mstatus[12:11] <= priv;   // MPP = priv
                    mstatus[7] <= mstatus[3]; // MPIE = MIE
                    mstatus[3] <= 1'b0;       // MIE = 0
                    priv <= 2'b11;            // Enter M-mode
                end
            end else if (mret) begin
                if (priv == 2'b11) begin
                    priv <= mstatus[12:11]; // Return to MPP
                    mstatus[3] <= mstatus[7]; // MIE = MPIE
                    mstatus[7] <= 1'b1;       // MPIE = 1
                    mstatus[12:11] <= 2'b00;  // MPP = U
                end else begin
                    trap_illegal <= 1'b1; // mret from non-M-mode is illegal
                end
            end else if (sret) begin
                if (priv >= 2'b01) begin
                    priv <= {1'b0, mstatus[8]}; // Return to SPP (0 or 1)
                    mstatus[1] <= mstatus[5];   // SIE = SPIE
                    mstatus[5] <= 1'b1;         // SPIE = 1
                    mstatus[8] <= 1'b0;         // SPP = U
                end else begin
                    trap_illegal <= 1'b1; // sret from U-mode is illegal
                end
            end else if (csr_we) begin
                // Software CSR write
                case (csr_addr)
                    12'h100: begin // sstatus (restricted view)
                        mstatus[1] <= csr_wdata[1]; // SIE
                        mstatus[5] <= csr_wdata[5]; // SPIE
                        mstatus[8] <= csr_wdata[8]; // SPP
                    end
                    12'h105: stvec   <= csr_wdata;
                    12'h141: sepc    <= csr_wdata;
                    12'h142: scause  <= csr_wdata;
                    12'h180: satp    <= csr_wdata;
                    
                    12'h300: mstatus <= csr_wdata;
                    12'h302: medeleg <= csr_wdata;
                    12'h303: mideleg <= csr_wdata;
                    12'h305: mtvec   <= csr_wdata;
                    12'h341: mepc    <= csr_wdata;
                    12'h342: mcause  <= csr_wdata;
                endcase
            end
        end
    end
endmodule
