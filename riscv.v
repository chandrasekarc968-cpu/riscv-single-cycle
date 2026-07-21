module riscv (
    input         clk,
    input         reset,
    input  [31:0] instr,
    input  [31:0] read_data,
    output [31:0] pc,
    output [31:0] alu_result,
    output [31:0] write_data,
    output [3:0]  mem_write,
    output        mem_read,
    input         stall,
    output        cpu_stall_req,
    input         ext_interrupt
);

    // Internal wires for Datapath and Control
    wire [2:0] result_src;
    wire       alu_src, reg_write, zero, jump, jalr, branch;
    wire       mem_write_ctrl;
    wire [2:0] imm_src;
    wire [3:0] alu_control;
    
    wire [31:0] pc_next, pc_plus_4, pc_target;
    wire [31:0] imm_ext;
    wire [31:0] srcA, srcB;
    wire [31:0] result;
    wire [31:0] rf_write_data;

    wire       muldiv_en;

    wire       csr_write;
    wire       trap_ecall;
    wire       mret;

    // ---------------------------------------------------------
    // CONTROL UNIT
    // ---------------------------------------------------------
    controller c (
        .op(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7b5(instr[30]),
        .funct7b0(instr[25]),
        .funct12(instr[31:20]),
        .result_src(result_src),
        .mem_write(mem_write_ctrl),
        .mem_read(mem_read),
        .alu_control(alu_control),
        .alu_src(alu_src),
        .imm_src(imm_src),
        .reg_write(reg_write),
        .jump(jump),
        .jalr(jalr),
        .muldiv_en(muldiv_en),
        .csr_write(csr_write),
        .trap_ecall(trap_ecall),
        .mret(mret),
        .branch(branch)
    );

    // ---------------------------------------------------------
    // BRANCH EVALUATION UNIT
    // ---------------------------------------------------------
    reg branch_taken;
    always @(*) begin
        if (branch) begin
            case (instr[14:12]) // funct3
                3'b000: branch_taken = zero;           // BEQ
                3'b001: branch_taken = !zero;          // BNE
                3'b100: branch_taken = alu_result[0];  // BLT
                3'b101: branch_taken = !alu_result[0]; // BGE
                3'b110: branch_taken = alu_result[0];  // BLTU
                3'b111: branch_taken = !alu_result[0]; // BGEU
                default: branch_taken = 1'b0;
            endcase
        end else begin
            branch_taken = 1'b0;
        end
    end

    wire [1:0] pc_src;
    assign pc_src = jalr ? 2'b10 : ((branch & branch_taken) | jump) ? 2'b01 : 2'b00;

    // ---------------------------------------------------------
    // MEMORY INTERFACE UNIT
    // ---------------------------------------------------------
    wire [1:0] addr_offset = alu_result[1:0];
    reg [3:0]  we_mask;
    reg [31:0] formatted_read_data;
    reg [31:0] aligned_write_data;
    
    // Store logic (Write)
    always @(*) begin
        we_mask = 4'b0000;
        aligned_write_data = rf_write_data; // Default
        
        if (mem_write_ctrl) begin
            case (instr[14:12]) // funct3
                3'b000: begin // SB
                    aligned_write_data = {4{rf_write_data[7:0]}};
                    case (addr_offset)
                        2'b00: we_mask = 4'b0001;
                        2'b01: we_mask = 4'b0010;
                        2'b10: we_mask = 4'b0100;
                        2'b11: we_mask = 4'b1000;
                    endcase
                end
                3'b001: begin // SH
                    aligned_write_data = {2{rf_write_data[15:0]}};
                    case (addr_offset[1])
                        1'b0: we_mask = 4'b0011;
                        1'b1: we_mask = 4'b1100;
                    endcase
                end
                3'b010: begin // SW
                    we_mask = 4'b1111;
                end
                default: we_mask = 4'b0000;
            endcase
        end
    end

    assign mem_write = stall ? 4'b0000 : we_mask;
    assign write_data = aligned_write_data;

    // Load logic (Read)
    always @(*) begin
        case (instr[14:12]) // funct3
            3'b000: begin // LB
                case (addr_offset)
                    2'b00: formatted_read_data = {{24{read_data[7]}}, read_data[7:0]};
                    2'b01: formatted_read_data = {{24{read_data[15]}}, read_data[15:8]};
                    2'b10: formatted_read_data = {{24{read_data[23]}}, read_data[23:16]};
                    2'b11: formatted_read_data = {{24{read_data[31]}}, read_data[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (addr_offset[1])
                    1'b0: formatted_read_data = {{16{read_data[15]}}, read_data[15:0]};
                    1'b1: formatted_read_data = {{16{read_data[31]}}, read_data[31:16]};
                endcase
            end
            3'b010: begin // LW
                formatted_read_data = read_data;
            end
            3'b100: begin // LBU
                case (addr_offset)
                    2'b00: formatted_read_data = {24'b0, read_data[7:0]};
                    2'b01: formatted_read_data = {24'b0, read_data[15:8]};
                    2'b10: formatted_read_data = {24'b0, read_data[23:16]};
                    2'b11: formatted_read_data = {24'b0, read_data[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (addr_offset[1])
                    1'b0: formatted_read_data = {16'b0, read_data[15:0]};
                    1'b1: formatted_read_data = {16'b0, read_data[31:16]};
                endcase
            end
            default: formatted_read_data = read_data;
        endcase
    end

    // ---------------------------------------------------------
    // DATAPATH
    // ---------------------------------------------------------
    
    // JALR target: alu_result with bit 0 cleared (RISC-V spec requirement)
    wire [31:0] jalr_target = {alu_result[31:1], 1'b0};

    // PC Logic
    assign pc_plus_4 = pc + 32'd4;
    assign pc_target = pc + imm_ext;
    assign pc_next = (pc_src == 2'b00) ? pc_plus_4 :
                     (pc_src == 2'b01) ? pc_target :   // Branch or JAL
                                         jalr_target;  // JALR (bit 0 cleared per spec)

    wire        interrupt_en;
    wire        do_trap = (ext_interrupt & interrupt_en) | trap_ecall;
    wire [31:0] trap_cause = (ext_interrupt & interrupt_en) ? 32'h80000007 : 32'h0000000B;
    wire [31:0] epc;
    wire [31:0] trap_vector;
    wire [31:0] csr_rdata;

    wire [31:0] pc_next_trap = do_trap ? trap_vector :
                               mret    ? epc :
                               pc_next;

    pc pcreg (
        .clk(clk),
        .reset(reset),
        .en(~stall),
        .pc_next(pc_next_trap),
        .pc(pc)
    );

    // CSR File
    csr_file csrs (
        .clk(clk),
        .reset(reset),
        .csr_addr(instr[31:20]),
        .csr_wdata(srcA), // Simplest CSR write: RS1
        .csr_we(csr_write & ~stall),
        .csr_rdata(csr_rdata),
        
        .trap(do_trap & ~stall),
        .trap_cause(trap_cause),
        .trap_pc(pc),
        .mret(mret & ~stall),
        
        .epc(epc),
        .trap_vector(trap_vector),
        .interrupt_en(interrupt_en)
    );

    // Register File
    regfile rf (
        .clk(clk),
        .we3(reg_write & ~stall),
        .a1(instr[19:15]),
        .a2(instr[24:20]),
        .a3(instr[11:7]),
        .wd3(result),
        .rd1(srcA),
        .rd2(rf_write_data)
    );

    // Immediate Extension
    extend ext (
        .instr(instr[31:7]),
        .imm_src(imm_src),
        .imm_ext(imm_ext)
    );

    // ALU
    assign srcB = alu_src ? imm_ext : rf_write_data;

    alu alu_inst (
        .srcA(srcA),
        .srcB(srcB),
        .alu_control(alu_control),
        .alu_result(alu_result),
        .zero(zero)
    );

    wire [31:0] muldiv_result;
    wire        muldiv_ready;
    
    muldiv md_inst (
        .clk(clk),
        .reset(reset),
        .start(muldiv_en),
        .funct3(instr[14:12]),
        .srcA(srcA),
        .srcB(rf_write_data),
        .result(muldiv_result),
        .ready(muldiv_ready)
    );
    
    assign cpu_stall_req = muldiv_en & ~muldiv_ready;

    // Writeback Logic
    assign result = (result_src == 3'b000) ? alu_result :
                    (result_src == 3'b001) ? formatted_read_data : 
                    (result_src == 3'b010) ? pc_plus_4 : 
                    (result_src == 3'b011) ? imm_ext :
                    (result_src == 3'b100) ? pc_target : 
                    (result_src == 3'b101) ? muldiv_result : 
                    (result_src == 3'b110) ? csr_rdata : 32'b0;

endmodule