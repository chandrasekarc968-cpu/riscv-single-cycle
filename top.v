module top (
    input clk,
    input reset
);

    wire [31:0] pc, instr, read_data;
    wire [31:0] data_adr, write_data;
    wire [3:0]  mem_write;
    wire        mem_read;
    wire        stall;
    wire        cpu_stall_req;
    wire        timer_interrupt;

    // Instantiate the RISC-V Processor Core
    riscv rv32core (
        .clk(clk),
        .reset(reset),
        .instr(instr),
        .read_data(read_data),
        .pc(pc),
        .alu_result(data_adr),
        .write_data(write_data),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .stall(stall),
        .cpu_stall_req(cpu_stall_req),
        .ext_interrupt(timer_interrupt)
    );

    wire        icache_stall;
    wire        icache_mem_req;
    wire [31:0] icache_mem_addr;
    wire [127:0] icache_mem_rdata;
    wire        icache_mem_ready;

    // Instantiate Instruction Cache
    icache icache_inst (
        .clk(clk),
        .reset(reset),
        .cpu_addr(pc),
        .cpu_req(1'b1), // CPU always fetching unless stalled
        .cpu_rdata(instr),
        .cpu_stall(icache_stall),
        .mem_req(icache_mem_req),
        .mem_addr(icache_mem_addr),
        .mem_rdata(icache_mem_rdata),
        .mem_ready(icache_mem_ready)
    );

    // ---------------------------------------------------------
    // MMIO Address Decoding
    // ---------------------------------------------------------
    // Memory Map:
    //   0x00000000 - 0x009FFFFF : Main RAM (10MB)
    //   0x80000000              : UART TX (write byte)
    //   0x80000004              : UART RX (read byte, stalls until input ready)
    //   0x80000008              : Timer (cycle counter, read-only)
    //   0x8000000C              : Cycle counter (alias, read-only)
    //   0x80000010              : Simulation finish (write any value to halt)
    // ---------------------------------------------------------

    wire is_mmio    = (data_adr[31:28] == 4'h8);
    wire is_uart_tx = is_mmio && (data_adr == 32'h80000000);
    wire is_uart_rx = is_mmio && (data_adr == 32'h80000004);
    wire is_timer   = is_mmio && (data_adr == 32'h80000008);
    wire is_cycles  = is_mmio && (data_adr == 32'h8000000C);
    wire is_finish  = is_mmio && (data_adr == 32'h80000010);

    // ---------------------------------------------------------
    // UART RX Logic (Stall to read synchronously)
    // ---------------------------------------------------------
    reg [7:0] uart_char;
    reg       uart_char_valid;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_char <= 0;
            uart_char_valid <= 0;
        end else if (is_uart_rx && mem_read && !uart_char_valid) begin
            uart_char <= $fgetc(32'h8000_0000);
            uart_char_valid <= 1;
        end else if (is_uart_rx && mem_read && uart_char_valid) begin
            uart_char_valid <= 0; // consumed
        end
    end
    
    wire mmio_stall = (is_uart_rx && mem_read && !uart_char_valid);

    // ---------------------------------------------------------
    // Timer / Cycle Counter
    // ---------------------------------------------------------
    reg [31:0] timer_val;
    always @(posedge clk or posedge reset) begin
        if (reset) timer_val <= 0;
        else timer_val <= timer_val + 1;
    end
    
    // Trigger interrupt every 4096 cycles (pulse for 1 cycle)
    assign timer_interrupt = (timer_val[11:0] == 12'hFFF);

    // ---------------------------------------------------------
    // UART TX Logic
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (is_uart_tx && mem_write[0]) begin
            $write("%c", write_data[7:0]);
        end
    end

    // ---------------------------------------------------------
    // Simulation Finish MMIO
    // ---------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset && is_finish && |mem_write) begin
            $display("\n--- Simulation finished by program (wrote to 0x80000010) at cycle %0d ---", timer_val);
            $finish;
        end
    end
    // synthesis translate_on

    // ---------------------------------------------------------
    // Memory Routing
    // ---------------------------------------------------------
    wire        cache_stall;
    wire [31:0] cache_rdata;
    
    // CPU reads from MMIO if requested, else from cache
    assign read_data = is_timer   ? timer_val :
                       is_cycles  ? timer_val :
                       is_uart_rx ? {24'b0, uart_char} :
                       cache_rdata;
                       
    // Stall CPU if cache stalls, MMIO is waiting, or CPU requires a stall (e.g. multi-cycle math)
    assign stall = is_mmio ? mmio_stall : (cache_stall | icache_stall | cpu_stall_req);
    
    // Cache memory inputs: suppress requests for MMIO addresses
    wire        cache_req   = (mem_read | (|mem_write)) & ~is_mmio;
    wire [3:0]  cache_wmask = is_mmio ? 4'b0000 : mem_write;

    // D-Cache Memory Interface
    wire        dcache_mem_req;
    wire [3:0]  dcache_mem_we;
    wire [31:0] dcache_mem_addr;
    wire [31:0] dcache_mem_wdata;
    wire [127:0] dcache_mem_rdata;
    wire        dcache_mem_ready;

    // Main Memory Interface
    wire        mem_req;
    wire [3:0]  mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [127:0] mem_rdata;
    wire        mem_ready;

    // Instantiate Data Cache
    dcache dcache_inst (
        .clk(clk),
        .reset(reset),
        .cpu_addr(data_adr),
        .cpu_wdata(write_data),
        .cpu_wmask(cache_wmask),
        .cpu_req(cache_req),
        .cpu_rdata(cache_rdata),
        .cpu_stall(cache_stall),
        .mem_req(dcache_mem_req),
        .mem_we(dcache_mem_we),
        .mem_addr(dcache_mem_addr),
        .mem_wdata(dcache_mem_wdata),
        .mem_rdata(dcache_mem_rdata),
        .mem_ready(dcache_mem_ready)
    );

    // Instantiate Memory Arbiter
    memory_arbiter arbiter_inst (
        .clk(clk),
        .reset(reset),
        
        .icache_req(icache_mem_req),
        .icache_addr(icache_mem_addr),
        .icache_rdata(icache_mem_rdata),
        .icache_ready(icache_mem_ready),
        
        .dcache_req(dcache_mem_req),
        .dcache_we(dcache_mem_we),
        .dcache_addr(dcache_mem_addr),
        .dcache_wdata(dcache_mem_wdata),
        .dcache_rdata(dcache_mem_rdata),
        .dcache_ready(dcache_mem_ready),
        
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    // Instantiate Slow Main Memory
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
