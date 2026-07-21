// Simple test program for the new RISC-V instructions
.text
main:
    li x1, 10           // Pseudo-inst: ADDI x1, x0, 10
    li x2, 5
    
    // ALU tests
    add x3, x1, x2      // x3 = 15
    sub x4, x1, x2      // x4 = 5
    xor x5, x1, x2      // x5 = 10 ^ 5 = 15
    
    // Shift tests
    slli x6, x2, 2      // x6 = 5 << 2 = 20
    srai x7, x1, 1      // x7 = 10 >> 1 = 5
    
    // Memory tests
    sw x3, 0(x0)        // store 15 at mem[0]
    lw x8, 0(x0)        // load 15 into x8
    
    sb x2, 4(x0)        // store byte 5 at mem[4]
    lb x9, 4(x0)        // load byte 5 into x9
    
    // Branch test
    blt x2, x1, loop    // 5 < 10, so it should branch
    j end               // should be skipped

loop:
    addi x2, x2, 1      // increment x2
    bne x2, x1, loop    // loop until x2 == 10

end:
    jalr x0, 0(ra)      // Return / loop infinitely or end simulation (we'll just use RET)
    ret
