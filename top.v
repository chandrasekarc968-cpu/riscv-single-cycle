module top (
    input clk,
    input reset
);

    // =========================================================
    // Core 0 Signals
    // =========================================================
    wire [31:0] core0_pc, core0_instr, core0_read_data;
    wire [31:0] core0_data_adr, core0_write_data;
    wire [3:0]  core0_mem_write;
    wire        core0_mem_read, core0_stall, core0_cpu_stall_req;
    
    wire        core0_icache_stall, core0_cache_stall;
    wire [31:0] core0_cache_rdata;
    
    // Core 0 Memory Interface
    wire        core0_icache_mem_req;
    wire [31:0] core0_icache_mem_addr;
    wire [127:0] core0_icache_mem_rdata;
    wire        core0_icache_mem_ready;
    
    wire        core0_dcache_mem_req;
    wire        core0_dcache_mem_we;
    wire [31:0] core0_dcache_mem_addr;
    wire [127:0] core0_dcache_mem_wdata;
    wire [127:0] core0_dcache_mem_rdata;
    wire        core0_dcache_mem_ready;

    wire        core0_mem_req;
    wire        core0_mem_we;
    wire [31:0] core0_mem_addr;
    wire [127:0] core0_mem_wdata;
    wire [127:0] core0_mem_rdata;
    wire        core0_mem_ready;

    wire        core0_l2_req;
    wire        core0_l2_we;
    wire [31:0] core0_l2_addr;
    wire [127:0] core0_l2_wdata;
    wire [127:0] core0_l2_rdata;
    wire        core0_l2_ready;

    wire        core0_snoop_req;
    wire        core0_snoop_is_write;
    wire [31:0] core0_snoop_addr;
    
    wire        core0_l1_snoop_hit, core0_l2_snoop_hit;
    wire        core0_l1_snoop_dirty, core0_l2_snoop_dirty;
    wire [127:0] core0_l1_snoop_rdata, core0_l2_snoop_rdata;

    wire        core0_snoop_hit = core0_l1_snoop_hit | core0_l2_snoop_hit;
    wire        core0_snoop_dirty = core0_l1_snoop_dirty | core0_l2_snoop_dirty;
    wire [127:0] core0_snoop_rdata = core0_l1_snoop_hit ? core0_l1_snoop_rdata : core0_l2_snoop_rdata;

    wire        core0_mem_is_shared;
    wire        core0_dcache_is_shared;

    // =========================================================
    // Core 1 Signals
    // =========================================================
    wire [31:0] core1_pc, core1_instr, core1_read_data;
    wire [31:0] core1_data_adr, core1_write_data;
    wire [3:0]  core1_mem_write;
    wire        core1_mem_read, core1_stall, core1_cpu_stall_req;
    
    wire        core1_icache_stall, core1_cache_stall;
    wire [31:0] core1_cache_rdata;
    
    // Core 1 Memory Interface
    wire        core1_icache_mem_req;
    wire [31:0] core1_icache_mem_addr;
    wire [127:0] core1_icache_mem_rdata;
    wire        core1_icache_mem_ready;
    
    wire        core1_dcache_mem_req;
    wire        core1_dcache_mem_we;
    wire [31:0] core1_dcache_mem_addr;
    wire [127:0] core1_dcache_mem_wdata;
    wire [127:0] core1_dcache_mem_rdata;
    wire        core1_dcache_mem_ready;

    wire        core1_mem_req;
    wire        core1_mem_we;
    wire [31:0] core1_mem_addr;
    wire [127:0] core1_mem_wdata;
    wire [127:0] core1_mem_rdata;
    wire        core1_mem_ready;

    wire        core1_l2_req;
    wire        core1_l2_we;
    wire [31:0] core1_l2_addr;
    wire [127:0] core1_l2_wdata;
    wire [127:0] core1_l2_rdata;
    wire        core1_l2_ready;

    wire        core1_snoop_req;
    wire        core1_snoop_is_write;
    wire [31:0] core1_snoop_addr;
    
    wire        core1_l1_snoop_hit, core1_l2_snoop_hit;
    wire        core1_l1_snoop_dirty, core1_l2_snoop_dirty;
    wire [127:0] core1_l1_snoop_rdata, core1_l2_snoop_rdata;

    wire        core1_snoop_hit = core1_l1_snoop_hit | core1_l2_snoop_hit;
    wire        core1_snoop_dirty = core1_l1_snoop_dirty | core1_l2_snoop_dirty;
    wire [127:0] core1_snoop_rdata = core1_l1_snoop_hit ? core1_l1_snoop_rdata : core1_l2_snoop_rdata;

    wire        core1_mem_is_shared;
    wire        core1_dcache_is_shared;

    // =========================================================
    // Shared MMIO Arbitration
    // =========================================================
    wire core0_is_mmio = (core0_data_adr[31:28] == 4'h8) || (core0_data_adr[31:24] == 8'h0C);
    wire core1_is_mmio = (core1_data_adr[31:28] == 4'h8) || (core1_data_adr[31:24] == 8'h0C);
    
    wire mmio_grant0 = core0_is_mmio;
    wire mmio_grant1 = core1_is_mmio & ~core0_is_mmio;
    
    wire [31:0] mmio_adr   = mmio_grant0 ? core0_data_adr : core1_data_adr;
    wire [31:0] mmio_wdata = mmio_grant0 ? core0_write_data : core1_write_data;
    wire [3:0]  mmio_wmask = mmio_grant0 ? core0_mem_write :
                             mmio_grant1 ? core1_mem_write : 4'b0000;
    wire        mmio_read  = mmio_grant0 ? core0_mem_read :
                             mmio_grant1 ? core1_mem_read : 1'b0;

    wire is_uart_tx = (mmio_adr == 32'h80000000);
    wire is_uart_rx = (mmio_adr == 32'h80000004);
    wire is_timer   = (mmio_adr == 32'h80000008);
    wire is_cycles  = (mmio_adr == 32'h8000000C);
    wire is_finish  = (mmio_adr == 32'h80000010);
    wire is_mutex   = (mmio_adr == 32'h80000014);
    wire is_plic    = (mmio_adr[31:24] == 8'h0C);

    // =========================================================
    // MMIO Logic
    // =========================================================
    
    // UART RX
    reg [7:0] uart_char;
    reg       uart_char_valid;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_char <= 0;
            uart_char_valid <= 0;
        end else if (is_uart_rx && mmio_read && !uart_char_valid) begin
            uart_char <= $fgetc(32'h8000_0000);
            uart_char_valid <= 1;
        end else if (is_uart_rx && mmio_read && uart_char_valid) begin
            uart_char_valid <= 0;
        end
    end
    wire uart_rx_stall = (is_uart_rx && mmio_read && !uart_char_valid);

    // Timer
    reg [31:0] timer_val;
    always @(posedge clk or posedge reset) begin
        if (reset) timer_val <= 0;
        else timer_val <= timer_val + 1;
    end
    wire timer_interrupt = (timer_val[11:0] == 12'hFFF);

    // Hardware Mutex (Read-to-Lock)
    reg mutex;
    always @(posedge clk or posedge reset) begin
        if (reset) mutex <= 0;
        else if (is_mutex && mmio_read) mutex <= 1'b1;
        else if (is_mutex && |mmio_wmask) mutex <= mmio_wdata[0];
    end

    // UART TX
    always @(posedge clk) begin
        if (is_uart_tx && mmio_wmask[0]) begin
            $write("%c", mmio_wdata[7:0]);
        end
    end

    // Simulation Finish
    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset && is_finish && |mmio_wmask) begin
            $display("\n--- Simulation finished by program (wrote to 0x80000010) at cycle %0d ---", timer_val);
            $finish;
        end
    end
    // synthesis translate_on

    wire [31:0] plic_rdata;
    wire core0_m_ext, core0_s_ext, core1_m_ext, core1_s_ext;
    
    plic plic_inst (
        .clk(clk),
        .reset(reset),
        .req(is_plic && (mmio_read || |mmio_wmask)),
        .we(|mmio_wmask),
        .addr(mmio_adr),
        .wdata(mmio_wdata),
        .wmask(mmio_wmask),
        .rdata(plic_rdata),
        .irq_sources({29'b0, timer_interrupt, uart_char_valid}), // 2: Timer, 1: UART RX
        .core0_m_ext(core0_m_ext),
        .core0_s_ext(core0_s_ext),
        .core1_m_ext(core1_m_ext),
        .core1_s_ext(core1_s_ext)
    );

    wire [31:0] mmio_rdata = is_timer ? timer_val :
                             is_cycles ? timer_val :
                             is_uart_rx ? {24'b0, uart_char} :
                             is_mutex ? {31'b0, mutex} : 
                             is_plic ? plic_rdata : 32'b0;

    // =========================================================
    // Core 0 Instantiation
    // =========================================================
    assign core0_read_data = core0_is_mmio ? mmio_rdata : core0_cache_rdata;
    wire core0_mmio_stall = core0_is_mmio & (~mmio_grant0 | uart_rx_stall);
    wire [31:0] core0_satp;
    
    wire        core0_cache_req   = (core0_mem_read | (|core0_mem_write)) & ~core0_is_mmio;
    wire [3:0]  core0_cache_wmask = core0_is_mmio ? 4'b0000 : core0_mem_write;
    
    riscv core0 (
        .clk(clk),
        .reset(reset),
        .instr(core0_instr),
        .read_data(core0_read_data),
        .pc(core0_pc),
        .alu_result(core0_data_adr),
        .write_data(core0_write_data),
        .mem_write(core0_mem_write),
        .mem_read(core0_mem_read),
        .stall(core0_stall),
        .cpu_stall_req(core0_cpu_stall_req),
        .ext_intr_m(core0_m_ext),
        .ext_intr_s(core0_s_ext),
        .hartid(32'd0),
        .satp_out(core0_satp)
    );

    wire [31:0] core0_pc_pa, core0_data_pa;
    wire core0_mmu_i_stall, core0_mmu_d_stall;
    wire core0_ptw_req;
    wire [31:0] core0_ptw_addr;

    mmu mmu0 (
        .clk(clk), .reset(reset),
        .satp(core0_satp),
        .i_req(1'b1), .i_va(core0_pc), .i_pa(core0_pc_pa), .i_stall(core0_mmu_i_stall), .i_page_fault(),
        .d_req(core0_cache_req), .d_we(|core0_cache_wmask), .d_va(core0_data_adr), .d_pa(core0_data_pa), .d_stall(core0_mmu_d_stall), .d_page_fault(),
        .ptw_req(core0_ptw_req), .ptw_addr(core0_ptw_addr), .ptw_rdata(core0_cache_rdata), .ptw_ready(!core0_cache_stall)
    );
    
    assign core0_stall = core0_mmio_stall | core0_cache_stall | core0_icache_stall | core0_cpu_stall_req | core0_mmu_i_stall | core0_mmu_d_stall;

    icache icache0 (
        .clk(clk), .reset(reset),
        .cpu_addr(core0_pc_pa), .cpu_req(1'b1), .cpu_rdata(core0_instr), .cpu_stall(core0_icache_stall),
        .mem_req(core0_icache_mem_req), .mem_addr(core0_icache_mem_addr),
        .mem_rdata(core0_icache_mem_rdata), .mem_ready(core0_icache_mem_ready)
    );

    wire        dcache0_req_in   = core0_ptw_req ? 1'b1 : core0_cache_req;
    wire [31:0] dcache0_addr_in  = core0_ptw_req ? core0_ptw_addr : core0_data_pa;
    wire [3:0]  dcache0_wmask_in = core0_ptw_req ? 4'b0000 : core0_cache_wmask;
    wire [31:0] dcache0_wdata_in = core0_ptw_req ? 32'b0 : core0_write_data;

    dcache dcache0 (
        .clk(clk), .reset(reset),
        .cpu_addr(dcache0_addr_in), .cpu_wdata(dcache0_wdata_in), .cpu_wmask(dcache0_wmask_in),
        .cpu_req(dcache0_req_in), .cpu_rdata(core0_cache_rdata), .cpu_stall(core0_cache_stall),
        .mem_req(core0_dcache_mem_req), .mem_we(core0_dcache_mem_we), .mem_addr(core0_dcache_mem_addr),
        .mem_wdata(core0_dcache_mem_wdata), .mem_rdata(core0_dcache_mem_rdata), .mem_ready(core0_dcache_mem_ready),
        .mem_is_shared(core0_dcache_is_shared),
        
        .snoop_req(core0_snoop_req), .snoop_is_write(core0_snoop_is_write), .snoop_addr(core0_snoop_addr),
        .snoop_hit(core0_l1_snoop_hit), .snoop_dirty(core0_l1_snoop_dirty), .snoop_rdata(core0_l1_snoop_rdata)
    );

    memory_arbiter arbiter0 (
        .clk(clk), .reset(reset),
        .icache_req(core0_icache_mem_req), .icache_addr(core0_icache_mem_addr),
        .icache_rdata(core0_icache_mem_rdata), .icache_ready(core0_icache_mem_ready),
        .dcache_req(core0_dcache_mem_req), .dcache_we(core0_dcache_mem_we), .dcache_addr(core0_dcache_mem_addr),
        .dcache_wdata(core0_dcache_mem_wdata), .dcache_rdata(core0_dcache_mem_rdata), .dcache_ready(core0_dcache_mem_ready),
        .dcache_is_shared(core0_dcache_is_shared),
        
        .mem_req(core0_mem_req), .mem_we(core0_mem_we), .mem_addr(core0_mem_addr),
        .mem_wdata(core0_mem_wdata), .mem_rdata(core0_mem_rdata), .mem_ready(core0_mem_ready),
        .mem_is_shared(core0_mem_is_shared)
    );

    // =========================================================
    // Core 1 Instantiation
    // =========================================================
    assign core1_read_data = core1_is_mmio ? mmio_rdata : core1_cache_rdata;
    wire core1_mmio_stall = core1_is_mmio & (~mmio_grant1 | uart_rx_stall);
    wire [31:0] core1_satp;
    
    wire        core1_cache_req   = (core1_mem_read | (|core1_mem_write)) & ~core1_is_mmio;
    wire [3:0]  core1_cache_wmask = core1_is_mmio ? 4'b0000 : core1_mem_write;

    riscv core1 (
        .clk(clk),
        .reset(reset),
        .instr(core1_instr),
        .read_data(core1_read_data),
        .pc(core1_pc),
        .alu_result(core1_data_adr),
        .write_data(core1_write_data),
        .mem_write(core1_mem_write),
        .mem_read(core1_mem_read),
        .stall(core1_stall),
        .cpu_stall_req(core1_cpu_stall_req),
        .ext_intr_m(core1_m_ext),
        .ext_intr_s(core1_s_ext),
        .hartid(32'd1),
        .satp_out(core1_satp)
    );

    wire [31:0] core1_pc_pa, core1_data_pa;
    wire core1_mmu_i_stall, core1_mmu_d_stall;
    wire core1_ptw_req;
    wire [31:0] core1_ptw_addr;

    mmu mmu1 (
        .clk(clk), .reset(reset),
        .satp(core1_satp),
        .i_req(1'b1), .i_va(core1_pc), .i_pa(core1_pc_pa), .i_stall(core1_mmu_i_stall), .i_page_fault(),
        .d_req(core1_cache_req), .d_we(|core1_cache_wmask), .d_va(core1_data_adr), .d_pa(core1_data_pa), .d_stall(core1_mmu_d_stall), .d_page_fault(),
        .ptw_req(core1_ptw_req), .ptw_addr(core1_ptw_addr), .ptw_rdata(core1_cache_rdata), .ptw_ready(!core1_cache_stall)
    );
    
    assign core1_stall = core1_mmio_stall | core1_cache_stall | core1_icache_stall | core1_cpu_stall_req | core1_mmu_i_stall | core1_mmu_d_stall;

    icache icache1 (
        .clk(clk), .reset(reset),
        .cpu_addr(core1_pc_pa), .cpu_req(1'b1), .cpu_rdata(core1_instr), .cpu_stall(core1_icache_stall),
        .mem_req(core1_icache_mem_req), .mem_addr(core1_icache_mem_addr),
        .mem_rdata(core1_icache_mem_rdata), .mem_ready(core1_icache_mem_ready)
    );

    wire        dcache1_req_in   = core1_ptw_req ? 1'b1 : core1_cache_req;
    wire [31:0] dcache1_addr_in  = core1_ptw_req ? core1_ptw_addr : core1_data_pa;
    wire [3:0]  dcache1_wmask_in = core1_ptw_req ? 4'b0000 : core1_cache_wmask;
    wire [31:0] dcache1_wdata_in = core1_ptw_req ? 32'b0 : core1_write_data;

    dcache dcache1 (
        .clk(clk), .reset(reset),
        .cpu_addr(dcache1_addr_in), .cpu_wdata(dcache1_wdata_in), .cpu_wmask(dcache1_wmask_in),
        .cpu_req(dcache1_req_in), .cpu_rdata(core1_cache_rdata), .cpu_stall(core1_cache_stall),
        .mem_req(core1_dcache_mem_req), .mem_we(core1_dcache_mem_we), .mem_addr(core1_dcache_mem_addr),
        .mem_wdata(core1_dcache_mem_wdata), .mem_rdata(core1_dcache_mem_rdata), .mem_ready(core1_dcache_mem_ready),
        .mem_is_shared(core1_dcache_is_shared),
        
        .snoop_req(core1_snoop_req), .snoop_is_write(core1_snoop_is_write), .snoop_addr(core1_snoop_addr),
        .snoop_hit(core1_l1_snoop_hit), .snoop_dirty(core1_l1_snoop_dirty), .snoop_rdata(core1_l1_snoop_rdata)
    );

    memory_arbiter arbiter1 (
        .clk(clk), .reset(reset),
        .icache_req(core1_icache_mem_req), .icache_addr(core1_icache_mem_addr),
        .icache_rdata(core1_icache_mem_rdata), .icache_ready(core1_icache_mem_ready),
        .dcache_req(core1_dcache_mem_req), .dcache_we(core1_dcache_mem_we), .dcache_addr(core1_dcache_mem_addr),
        .dcache_wdata(core1_dcache_mem_wdata), .dcache_rdata(core1_dcache_mem_rdata), .dcache_ready(core1_dcache_mem_ready),
        .dcache_is_shared(core1_dcache_is_shared),
        
        .mem_req(core1_mem_req), .mem_we(core1_mem_we), .mem_addr(core1_mem_addr),
        .mem_wdata(core1_mem_wdata), .mem_rdata(core1_mem_rdata), .mem_ready(core1_mem_ready),
        .mem_is_shared(core1_mem_is_shared)
    );

    // =========================================================
    // Main Memory & Bus Arbiter
    // =========================================================
    wire        mem_req;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [127:0] mem_wdata;
    wire [127:0] mem_rdata;
    wire        mem_ready;

    wire        l3_req;
    wire        l3_we;
    wire [31:0] l3_addr;
    wire [127:0] l3_wdata;
    wire [127:0] l3_rdata;
    wire        l3_ready;

    // L2 Cache for Core 0 (4-Way, 4KB = 64 sets)
    block_cache #(.WAYS(4), .SETS(64), .INDEX_BITS(6)) l2_cache_0 (
        .clk(clk), .reset(reset),
        .up_req(core0_mem_req), .up_we(core0_mem_we), .up_addr(core0_mem_addr), .up_wdata(core0_mem_wdata), .up_rdata(core0_mem_rdata), .up_ready(core0_mem_ready),
        .down_req(core0_l2_req), .down_we(core0_l2_we), .down_addr(core0_l2_addr), .down_wdata(core0_l2_wdata), .down_rdata(core0_l2_rdata), .down_ready(core0_l2_ready),
        .down_is_shared(core0_mem_is_shared),
        
        .snoop_req(core0_snoop_req), .snoop_is_write(core0_snoop_is_write), .snoop_addr(core0_snoop_addr),
        .snoop_hit(core0_l2_snoop_hit), .snoop_dirty(core0_l2_snoop_dirty), .snoop_rdata(core0_l2_snoop_rdata)
    );

    // L2 Cache for Core 1 (4-Way, 4KB = 64 sets)
    block_cache #(.WAYS(4), .SETS(64), .INDEX_BITS(6)) l2_cache_1 (
        .clk(clk), .reset(reset),
        .up_req(core1_mem_req), .up_we(core1_mem_we), .up_addr(core1_mem_addr), .up_wdata(core1_mem_wdata), .up_rdata(core1_mem_rdata), .up_ready(core1_mem_ready),
        .down_req(core1_l2_req), .down_we(core1_l2_we), .down_addr(core1_l2_addr), .down_wdata(core1_l2_wdata), .down_rdata(core1_l2_rdata), .down_ready(core1_l2_ready),
        .down_is_shared(core1_mem_is_shared),
        
        .snoop_req(core1_snoop_req), .snoop_is_write(core1_snoop_is_write), .snoop_addr(core1_snoop_addr),
        .snoop_hit(core1_l2_snoop_hit), .snoop_dirty(core1_l2_snoop_dirty), .snoop_rdata(core1_l2_snoop_rdata)
    );

    bus_arbiter main_bus (
        .clk(clk),
        .reset(reset),
        
        .core0_req(core0_l2_req),
        .core0_we(core0_l2_we),
        .core0_addr(core0_l2_addr),
        .core0_wdata(core0_l2_wdata),
        .core0_rdata(core0_l2_rdata),
        .core0_ready(core0_l2_ready),
        .core0_is_shared(core0_mem_is_shared),
        
        .core1_req(core1_l2_req),
        .core1_we(core1_l2_we),
        .core1_addr(core1_l2_addr),
        .core1_wdata(core1_l2_wdata),
        .core1_rdata(core1_l2_rdata),
        .core1_ready(core1_l2_ready),
        .core1_is_shared(core1_mem_is_shared),
        
        .core0_snoop_req(core0_snoop_req),
        .core0_snoop_is_write(core0_snoop_is_write),
        .core0_snoop_addr(core0_snoop_addr),
        .core0_snoop_hit(core0_snoop_hit),
        .core0_snoop_dirty(core0_snoop_dirty),
        .core0_snoop_rdata(core0_snoop_rdata),

        .core1_snoop_req(core1_snoop_req),
        .core1_snoop_is_write(core1_snoop_is_write),
        .core1_snoop_addr(core1_snoop_addr),
        .core1_snoop_hit(core1_snoop_hit),
        .core1_snoop_dirty(core1_snoop_dirty),
        .core1_snoop_rdata(core1_snoop_rdata),

        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    // L3 Shared Cache (8-Way, 16KB = 128 sets)
    // L3 is the Point of Coherency (PoC), so it ignores snoops!
    block_cache #(.WAYS(8), .SETS(128), .INDEX_BITS(7)) l3_shared_cache (
        .clk(clk), .reset(reset),
        .up_req(mem_req), .up_we(mem_we), .up_addr(mem_addr), .up_wdata(mem_wdata), .up_rdata(mem_rdata), .up_ready(mem_ready),
        .down_req(l3_req), .down_we(l3_we), .down_addr(l3_addr), .down_wdata(l3_wdata), .down_rdata(l3_rdata), .down_ready(l3_ready),
        .down_is_shared(1'b0), // L3 is the bottom, never shared
        .snoop_req(1'b0), .snoop_is_write(1'b0), .snoop_addr(32'b0), // No snooping for L3
        .snoop_hit(), .snoop_dirty(), .snoop_rdata()
    );

    main_memory main_mem_inst (
        .clk(clk),
        .reset(reset),
        .req(l3_req),
        .we(l3_we),
        .a(l3_addr),
        .wd(l3_wdata),
        .rd(l3_rdata),
        .ready(l3_ready)
    );

endmodule
