module tb;
    integer c;
    initial begin
        $display("Enter a char:");
        c = $fgetc(32'h8000_0000);
        $display("You entered: %c (%d)", c, c);
    end
endmodule
