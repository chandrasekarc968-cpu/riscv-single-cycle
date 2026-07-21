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
    wire [3:0]  core0_dcache_mem_we;
    wire [31:0] core0_dcache_mem_addr, core0_dcache_mem_wdata;
    wire [127:0] core0_dcache_mem_rdata;
    wire        core0_dcache_mem_ready;

    wire        core0_mem_req;
    wire [3:0]  core0_mem_we;
    wire [31:0] core0_mem_addr, core0_mem_wdata;
    wire [127:0] core0_mem_rdata;
    wire        core0_mem_ready;

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
    wire [3:0]  core1_dcache_mem_we;
    wire [31:0] core1_dcache_mem_addr, core1_dcache_mem_wdata;
    wire [127:0] core1_dcache_mem_rdata;
    wire        core1_dcache_mem_ready;

    wire        core1_mem_req;
    wire [3:0]  core1_mem_we;
    wire [31:0] core1_mem_addr, core1_mem_wdata;
    wire [127:0] core1_mem_rdata;
    wire        core1_mem_ready;

    // =========================================================
    // Shared MMIO Arbitration
    // =========================================================
    wire core0_is_mmio = (core0_data_adr[31:28] == 4'h8);
    wire core1_is_mmio = (core1_data_adr[31:28] == 4'h8);
    
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

    wire [31:0] mmio_rdata = is_timer ? timer_val :
                             is_cycles ? timer_val :
                             is_uart_rx ? {24'b0, uart_char} :
                             is_mutex ? {31'b0, mutex} : 32'b0;

    // =========================================================
    // Core 0 Instantiation
    // =========================================================
    assign core0_read_data = core0_is_mmio ? mmio_rdata : core0_cache_rdata;
    wire core0_mmio_stall = core0_is_mmio & (~mmio_grant0 | uart_rx_stall);
    assign core0_stall = core0_mmio_stall | core0_cache_stall | core0_icache_stall | core0_cpu_stall_req;
    
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
        .ext_interrupt(timer_interrupt),
        .hartid(32'd0)
    );

    icache icache0 (
        .clk(clk), .reset(reset),
        .cpu_addr(core0_pc), .cpu_req(1'b1), .cpu_rdata(core0_instr), .cpu_stall(core0_icache_stall),
        .mem_req(core0_icache_mem_req), .mem_addr(core0_icache_mem_addr),
        .mem_rdata(core0_icache_mem_rdata), .mem_ready(core0_icache_mem_ready)
    );

    dcache dcache0 (
        .clk(clk), .reset(reset),
        .cpu_addr(core0_data_adr), .cpu_wdata(core0_write_data), .cpu_wmask(core0_cache_wmask),
        .cpu_req(core0_cache_req), .cpu_rdata(core0_cache_rdata), .cpu_stall(core0_cache_stall),
        .mem_req(core0_dcache_mem_req), .mem_we(core0_dcache_mem_we), .mem_addr(core0_dcache_mem_addr),
        .mem_wdata(core0_dcache_mem_wdata), .mem_rdata(core0_dcache_mem_rdata), .mem_ready(core0_dcache_mem_ready)
    );

    memory_arbiter arbiter0 (
        .clk(clk), .reset(reset),
        .icache_req(core0_icache_mem_req), .icache_addr(core0_icache_mem_addr),
        .icache_rdata(core0_icache_mem_rdata), .icache_ready(core0_icache_mem_ready),
        .dcache_req(core0_dcache_mem_req), .dcache_we(core0_dcache_mem_we), .dcache_addr(core0_dcache_mem_addr),
        .dcache_wdata(core0_dcache_mem_wdata), .dcache_rdata(core0_dcache_mem_rdata), .dcache_ready(core0_dcache_mem_ready),
        .mem_req(core0_mem_req), .mem_we(core0_mem_we), .mem_addr(core0_mem_addr),
        .mem_wdata(core0_mem_wdata), .mem_rdata(core0_mem_rdata), .mem_ready(core0_mem_ready)
    );

    // =========================================================
    // Core 1 Instantiation
    // =========================================================
    assign core1_read_data = core1_is_mmio ? mmio_rdata : core1_cache_rdata;
    wire core1_mmio_stall = core1_is_mmio & (~mmio_grant1 | uart_rx_stall);
    assign core1_stall = core1_mmio_stall | core1_cache_stall | core1_icache_stall | core1_cpu_stall_req;
    
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
        .ext_interrupt(timer_interrupt),
        .hartid(32'd1)
    );

    icache icache1 (
        .clk(clk), .reset(reset),
        .cpu_addr(core1_pc), .cpu_req(1'b1), .cpu_rdata(core1_instr), .cpu_stall(core1_icache_stall),
        .mem_req(core1_icache_mem_req), .mem_addr(core1_icache_mem_addr),
        .mem_rdata(core1_icache_mem_rdata), .mem_ready(core1_icache_mem_ready)
    );

    dcache dcache1 (
        .clk(clk), .reset(reset),
        .cpu_addr(core1_data_adr), .cpu_wdata(core1_write_data), .cpu_wmask(core1_cache_wmask),
        .cpu_req(core1_cache_req), .cpu_rdata(core1_cache_rdata), .cpu_stall(core1_cache_stall),
        .mem_req(core1_dcache_mem_req), .mem_we(core1_dcache_mem_we), .mem_addr(core1_dcache_mem_addr),
        .mem_wdata(core1_dcache_mem_wdata), .mem_rdata(core1_dcache_mem_rdata), .mem_ready(core1_dcache_mem_ready)
    );

    memory_arbiter arbiter1 (
        .clk(clk), .reset(reset),
        .icache_req(core1_icache_mem_req), .icache_addr(core1_icache_mem_addr),
        .icache_rdata(core1_icache_mem_rdata), .icache_ready(core1_icache_mem_ready),
        .dcache_req(core1_dcache_mem_req), .dcache_we(core1_dcache_mem_we), .dcache_addr(core1_dcache_mem_addr),
        .dcache_wdata(core1_dcache_mem_wdata), .dcache_rdata(core1_dcache_mem_rdata), .dcache_ready(core1_dcache_mem_ready),
        .mem_req(core1_mem_req), .mem_we(core1_mem_we), .mem_addr(core1_mem_addr),
        .mem_wdata(core1_mem_wdata), .mem_rdata(core1_mem_rdata), .mem_ready(core1_mem_ready)
    );

    // =========================================================
    // Main Memory & Bus Arbiter
    // =========================================================
    wire        mem_req;
    wire [3:0]  mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [127:0] mem_rdata;
    wire        mem_ready;

    bus_arbiter main_bus (
        .clk(clk),
        .reset(reset),
        
        .core0_req(core0_mem_req),
        .core0_we(core0_mem_we),
        .core0_addr(core0_mem_addr),
        .core0_wdata(core0_mem_wdata),
        .core0_rdata(core0_mem_rdata),
        .core0_ready(core0_mem_ready),
        
        .core1_req(core1_mem_req),
        .core1_we(core1_mem_we),
        .core1_addr(core1_mem_addr),
        .core1_wdata(core1_mem_wdata),
        .core1_rdata(core1_mem_rdata),
        .core1_ready(core1_mem_ready),
        
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    main_memory main_mem_inst (
        .clk(clk),
        .reset(reset),
        .req(mem_req),
        .we(mem_we),
        .a(mem_addr),
        .wd(mem_wdata),
        .rd(mem_rdata),
        .ready(mem_ready)
    );

endmodule
