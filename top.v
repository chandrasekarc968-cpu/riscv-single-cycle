module top (
    input clk,
    input reset
);

    wire [31:0] pc, instr, read_data;
    wire [31:0] data_adr, write_data;
    wire [3:0]  mem_write;
    wire        mem_read;
    wire        stall;

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
        .stall(stall)
    );

    // Instantiate Instruction Memory
    imem imem_inst (
        .a(pc),
        .rd(instr)
    );

    // MMIO Address Decoding
    wire is_mmio = (data_adr[31:28] == 4'h8);
    wire is_uart_tx = is_mmio && (data_adr == 32'h80000000);
    wire is_uart_rx = is_mmio && (data_adr == 32'h80000004);
    wire is_timer   = is_mmio && (data_adr == 32'h80000008);

    // UART RX Logic (Stall to read synchronously)
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

    // Timer Logic
    reg [31:0] timer_val;
    always @(posedge clk or posedge reset) begin
        if (reset) timer_val <= 0;
        else timer_val <= timer_val + 1;
    end

    // UART TX Logic
    always @(posedge clk) begin
        if (is_uart_tx && mem_write[0]) begin
            $write("%c", write_data[7:0]);
        end
    end

    // Memory routing
    wire        cache_stall;
    wire [31:0] cache_rdata;
    
    // CPU reads from MMIO if requested, else from cache
    assign read_data = is_timer   ? timer_val :
                       is_uart_rx ? {24'b0, uart_char} :
                       cache_rdata;
                       
    // Stall CPU if cache stalls or MMIO is waiting
    assign stall = is_mmio ? mmio_stall : cache_stall;
    
    // Cache memory inputs
    wire        cache_req   = (mem_read | (|mem_write)) & ~is_mmio;
    wire [3:0]  cache_wmask = is_mmio ? 4'b0000 : mem_write;

    // Interconnect between Cache and Main Memory
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
