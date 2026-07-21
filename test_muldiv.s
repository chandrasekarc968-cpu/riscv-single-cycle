// Test for M-Extension (mul, div, rem)

.text
main:
    li s10, 0x80000000  // UART TX
    li s11, 0x80000010  // Simulation Finish MMIO
    
    // 1. Test MUL
    li t0, 5
    li t1, 6
    mul t2, t0, t1      // t2 = 30
    
    // Print result (should be 30, let's just print char if it fits, or assume success if it doesn't crash)
    // Actually, let's write a small print_num routine.
    mv a0, t2
    call print_num
    
    la a0, msg_newline
    call print_str

    // 2. Test DIV
    li t0, 100
    li t1, 3
    div t2, t0, t1      // t2 = 33
    
    mv a0, t2
    call print_num
    
    la a0, msg_newline
    call print_str
    
    // 3. Test REM
    rem t2, t0, t1      // t2 = 1
    
    mv a0, t2
    call print_num
    
    la a0, msg_newline
    call print_str

    // Finish simulation
    sw zero, 0(s11)
inf:
    j inf

// ---------------------------------------------------------
// Subroutines
// ---------------------------------------------------------

// print_str(a0: string address)
print_str:
    mv t0, a0
print_str_loop:
    lb t1, 0(t0)
    beqz t1, print_str_done
    sb t1, 0(s10)       // write TX
    addi t0, t0, 1
    j print_str_loop
print_str_done:
    ret

// print_num(a0: positive number up to 99)
print_num:
    bgez a0, print_num_start
    li a0, 0
print_num_start:
    li t0, 10
    li t2, 0 // tens count
tens_loop:
    blt a0, t0, tens_done
    sub a0, a0, t0
    addi t2, t2, 1
    j tens_loop
tens_done:

    beqz t2, print_ones
    addi t3, t2, 48
    sb t3, 0(s10)
    
print_ones:
    addi t3, a0, 48
    sb t3, 0(s10)
    ret

.data
msg_newline:
    .string "\n"
