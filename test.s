// Comprehensive test program for the RISC-V single-cycle processor
// Tests: ALU ops, shifts, memory (word/half/byte), branches, jumps, upper-immediate
.text

main:
    // ---------------------------------------------------------
    // 1. Basic ALU Tests
    // ---------------------------------------------------------
    li x1, 10           // x1 = 10
    li x2, 5            // x2 = 5
    
    add x3, x1, x2      // x3 = 15
    sub x4, x1, x2      // x4 = 5
    xor x5, x1, x2      // x5 = 10 ^ 5 = 15
    or  x6, x1, x2      // x6 = 10 | 5 = 15
    and x7, x1, x2      // x7 = 10 & 5 = 0
    slt x8, x2, x1      // x8 = 1 (5 < 10)
    sltu x9, x2, x1     // x9 = 1 (5u < 10u)
    
    // ---------------------------------------------------------
    // 2. Immediate ALU Tests
    // ---------------------------------------------------------
    addi x10, x1, -3    // x10 = 7
    xori x11, x1, 0xFF  // x11 = 10 ^ 255 = 245
    ori  x12, x0, 42    // x12 = 42
    andi x13, x1, 6     // x13 = 10 & 6 = 2
    slti x14, x2, 10    // x14 = 1 (5 < 10)
    
    // ---------------------------------------------------------
    // 3. Shift Tests
    // ---------------------------------------------------------
    slli x15, x2, 2     // x15 = 5 << 2 = 20
    srli x16, x1, 1     // x16 = 10 >> 1 = 5
    srai x17, x1, 1     // x17 = 10 >>> 1 = 5
    
    li x18, -16          // x18 = 0xFFFFFFF0
    srai x19, x18, 2    // x19 = -16 >>> 2 = -4 (arithmetic shift preserves sign)
    
    // ---------------------------------------------------------
    // 4. Upper Immediate Tests
    // ---------------------------------------------------------
    lui x20, 0x12345     // x20 = 0x12345000
    auipc x21, 0         // x21 = current PC

    // ---------------------------------------------------------
    // 5. Word Memory Tests
    // ---------------------------------------------------------
    li x22, 0x200        // Use address 0x200 as scratch space (avoids program area)
    sw x3, 0(x22)        // store 15 at mem[0x200]
    lw x23, 0(x22)       // load it back: x23 should be 15
    
    // ---------------------------------------------------------
    // 6. Sub-word Memory Tests (Byte)
    // ---------------------------------------------------------
    li x24, 0xAB
    sb x24, 4(x22)       // store byte 0xAB at mem[0x204]
    lb x25, 4(x22)       // load signed byte: x25 = 0xFFFFFFAB (sign-extended)
    lbu x26, 4(x22)      // load unsigned byte: x26 = 0x000000AB
    
    // ---------------------------------------------------------
    // 7. Sub-word Memory Tests (Halfword)
    // ---------------------------------------------------------
    li x27, 0x1234
    sh x27, 8(x22)       // store halfword at mem[0x208]
    lh x28, 8(x22)       // load signed halfword: x28 = 0x00001234
    lhu x29, 8(x22)      // load unsigned halfword: x29 = 0x00001234
    
    // ---------------------------------------------------------
    // 8. Branch Tests
    // ---------------------------------------------------------
    li x2, 5
    blt x2, x1, branch_ok  // 5 < 10, should branch
    j test_fail

branch_ok:
    beq x1, x1, branch_eq_ok  // always true
    j test_fail
    
branch_eq_ok:
    bne x1, x2, branch_ne_ok  // 10 != 5, should branch
    j test_fail

branch_ne_ok:
    bge x1, x2, branch_ge_ok  // 10 >= 5, should branch
    j test_fail

branch_ge_ok:
    // ---------------------------------------------------------
    // 9. Loop Test (BNE loop)
    // ---------------------------------------------------------
    li x2, 0
loop:
    addi x2, x2, 1
    li x30, 10
    bne x2, x30, loop    // loop until x2 == 10

    // ---------------------------------------------------------
    // 10. JAL/JALR Test (Function call)
    // ---------------------------------------------------------
    jal ra, test_func     // call test_func, ra = return address
    
    // If we reach here, all tests passed
    j test_pass

test_func:
    addi x31, x0, 99     // x31 = 99
    ret                   // return to caller

test_pass:
    // Signal success via MMIO finish
    li t0, 0x80000010
    sw x0, 0(t0)         // write to finish MMIO -> ends simulation
    
test_fail:
    // Signal failure (infinite loop — caught by testbench timeout)
    j test_fail
