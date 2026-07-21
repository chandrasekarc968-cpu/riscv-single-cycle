module muldiv (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [2:0]  funct3,
    input  wire [31:0] srcA,
    input  wire [31:0] srcB,
    output reg  [31:0] result,
    output reg         ready
);

    localparam STATE_IDLE = 2'b00;
    localparam STATE_MUL  = 2'b01;
    localparam STATE_DIV  = 2'b10;
    
    reg [1:0] state;
    reg [5:0] count;
    
    reg [64:0] acc;
    reg [31:0] b_reg;
    reg        sign_a;
    reg        sign_b;
    reg        neg_res;
    reg [2:0]  op_reg;

    wire is_div = funct3[2];
    
    assign ready = (state == STATE_MUL && count == 32) || 
                   (state == STATE_DIV && count == 32) ||
                   (state == STATE_IDLE && start && (srcB == 0 || (sign_a && srcA == 32'h80000000 && sign_b && srcB == 32'hFFFFFFFF)));

    always @(*) begin
        result = 32'b0;
        if (state == STATE_MUL && count == 32) begin
            if (op_reg == 3'b000) begin
                result = neg_res ? -acc[31:0] : acc[31:0];
            end else begin
                result = neg_res ? -acc[63:32] : acc[63:32];
            end
        end else if (state == STATE_DIV && count == 32) begin
            if (op_reg == 3'b100 || op_reg == 3'b101) begin
                result = neg_res ? -acc[31:0] : acc[31:0];
            end else begin
                result = neg_res ? -acc[63:32] : acc[63:32];
            end
        end else if (state == STATE_IDLE && start) begin
            if (is_div && srcB == 0) begin
                result = (funct3 == 3'b100 || funct3 == 3'b101) ? 32'hFFFFFFFF : srcA;
            end else if (is_div && sign_a && srcA == 32'h80000000 && sign_b && srcB == 32'hFFFFFFFF) begin
                result = (funct3 == 3'b100 || funct3 == 3'b101) ? 32'h80000000 : 0;
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start && !ready) begin
                        count <= 0;
                        op_reg <= funct3;
                        b_reg <= srcB;
                        
                        if (!is_div) begin
                            sign_a = (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010) ? srcA[31] : 1'b0;
                            sign_b = (funct3 == 3'b000 || funct3 == 3'b001) ? srcB[31] : 1'b0;
                            neg_res = sign_a ^ sign_b;
                            acc <= {33'b0, (sign_a ? -srcA : srcA)};
                            b_reg <= sign_b ? -srcB : srcB;
                            state <= STATE_MUL;
                        end else begin
                            sign_a = (funct3 == 3'b100 || funct3 == 3'b110) ? srcA[31] : 1'b0;
                            sign_b = (funct3 == 3'b100 || funct3 == 3'b110) ? srcB[31] : 1'b0;
                            neg_res = (funct3 == 3'b100) ? (sign_a ^ sign_b) : 
                                      (funct3 == 3'b110) ? sign_a : 1'b0;
                            acc <= {33'b0, (sign_a ? -srcA : srcA)};
                            b_reg <= sign_b ? -srcB : srcB;
                            state <= STATE_DIV;
                        end
                    end
                end
                
                STATE_MUL: begin
                    if (count == 32) begin
                        state <= STATE_IDLE;
                    end else begin
                        if (acc[0]) begin
                            acc = {1'b0, acc[64:32] + b_reg, acc[31:1]};
                        end else begin
                            acc = {1'b0, acc[64:1]};
                        end
                        count <= count + 1;
                    end
                end
                
                STATE_DIV: begin
                    if (count == 32) begin
                        state <= STATE_IDLE;
                    end else begin
                        acc = {acc[63:0], 1'b0};
                        if (acc[64:32] >= {1'b0, b_reg}) begin
                            acc[64:32] = acc[64:32] - {1'b0, b_reg};
                            acc[0] = 1'b1;
                        end
                        count <= count + 1;
                    end
                end
            endcase
        end
    end
endmodule
