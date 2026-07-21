// Guess the Number - RISC-V Assembly Game

// Constants
li s10, 0x80000000  // UART TX
li s11, 0x80000004  // UART RX
li s9,  0x80000008  // Timer

// ---------------------------------------------------------
// Main Entry
// ---------------------------------------------------------
_start:
    // Print welcome
    lui a0, 0           // We assume strings are loaded at small addresses if after code
    // Wait, the assembler resolves labels for lui/addi if we use them, but our assembler
    // only resolves branches/jumps correctly. 
    // To load a data address:
    // la a0, msg_welcome is pseudo.
    // Our assembler doesn't have `la`. 
    // It has `lui` and `addi` but doesn't resolve labels for them automatically yet!
    // Wait... look at riscv-asm/src/main.rs: `get_imm(&inst.args[X], false)` returns the label's address!
    // So we can do:
    // li a0, msg_welcome  -> expanded to lui + addi!
    
    la a0, msg_welcome
    jal ra, print_str
    
    // Generate Random number
    lw t0, 0(s9)        // read timer
mod_loop:
    li t1, 9
    blt t0, t1, mod_done
    addi t0, t0, -9
    j mod_loop
mod_done:
    addi t0, t0, 49     // add '1' (ASCII 49)
    mv s0, t0           // s0 holds the target char
    
game_loop:
    la a0, msg_prompt
    jal ra, print_str
    
    // Read char
    lw a0, 0(s11)       // blocking read from UART RX
    
    // Print newline after input (or just the char itself then newline)
    sb a0, 0(s10)       // echo
    li t1, 10           // '\n'
    sb t1, 0(s10)
    
    // Check win
    beq a0, s0, win
    
    // Check bounds
    li t1, 49           // '1'
    blt a0, t1, game_loop
    li t1, 57           // '9'
    blt t1, a0, game_loop
    
    // Too low or too high?
    blt a0, s0, too_low
    
too_high:
    la a0, msg_high
    jal ra, print_str
    j game_loop
    
too_low:
    la a0, msg_low
    jal ra, print_str
    j game_loop
    
win:
    la a0, msg_win
    jal ra, print_str
    
halt:
    j halt

// ---------------------------------------------------------
// Subroutine: print_str
// a0 = address of null-terminated string
// ---------------------------------------------------------
print_str:
    mv t0, a0
print_loop:
    lb t1, 0(t0)
    beq t1, zero, print_done
    sb t1, 0(s10)       // Write to UART TX
    addi t0, t0, 1
    j print_loop
print_done:
    ret

// ---------------------------------------------------------
// Data Section
// ---------------------------------------------------------
msg_welcome:
    .string "Guess the Number (1-9)!\n"
msg_prompt:
    .string "Guess> "
msg_high:
    .string "Too high!\n"
msg_low:
    .string "Too low!\n"
msg_win:
    .string "You WIN!\n"
