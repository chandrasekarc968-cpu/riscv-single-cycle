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
        
        // Failsafe: stop simulation after 500,000 time units (50,000 clock cycles)
        // This is long enough for real programs with cache stalls but prevents runaways
        #500000;
        $display("\n--- Simulation TIMEOUT after 500,000 time units ---");
        // Optionally turn off VCD dumping before timeout to limit file size
        $dumpoff;
        $finish;
    end
    
    // Legacy monitor for backward-compatible test programs
    // Programs can also halt via MMIO write to 0x80000010 (handled in top.v)
    always @(negedge clk) begin
        // If the CPU is attempting a memory write...
        if (dut.mem_write) begin
            // Check if it's writing the value 12 to address 84 (legacy test.s success check)
            if (dut.data_adr === 32'd84 && dut.write_data === 32'd12) begin
                $display("Simulation SUCCEEDED (legacy check)");
                $finish;
            end
        end
    end
endmodule