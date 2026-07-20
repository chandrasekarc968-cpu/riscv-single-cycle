module top (
    input clk,
    input reset
);

    wire [31:0] pc, instr, read_data;
    wire [31:0] data_adr, write_data;
    wire        mem_write;

    // Instantiate the RISC-V Processor Core
    riscv rv32core (
        .clk(clk),
        .reset(reset),
        .instr(instr),
        .read_data(read_data),
        .pc(pc),
        .alu_result(data_adr),
        .write_data(write_data),
        .mem_write(mem_write)
    );

    // Instantiate Instruction Memory
    imem imem_inst (
        .a(pc),
        .rd(instr)
    );

    // Instantiate Data Memory
    dmem dmem_inst (
        .clk(clk),
        .we(mem_write),
        .a(data_adr),
        .wd(write_data),
        .rd(read_data)
    );

endmodule
