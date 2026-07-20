module tb;
    reg clk;
    reg reset;
    
    // Instantiate the top-level module
    top dut(
        .clk(clk), 
        .reset(reset)
    );
    
    // Generate a clock with a 10-time-unit period
    always #5 clk = ~clk;
    
    initial begin
        // Generate waveform file for GTKWave
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);
        
        // Start simulation with reset active
        clk = 0; 
        reset = 1;
        
        // Release reset after 10 time units
        #10 reset = 0;
        
        // Failsafe: stop simulation after 100 time units
        #100 $display("Simulation FAILED: Timeout");
        $finish;
    end
    
    // Monitor for successful completion
    always @(negedge clk) begin
        // If the CPU is attempting a memory write...
        if (dut.mem_write) begin
            // Check if it's writing the value 12 to address 84
            if (dut.data_adr === 32'd84 && dut.write_data === 32'd12) begin
                $display("Simulation SUCCEEDED");
                $finish;
            end
        end
    end
endmodule