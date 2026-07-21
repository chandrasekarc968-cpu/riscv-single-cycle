// Test for CSRs and Interrupts

.text
main:
    li s10, 0x80000000  // UART TX
    
    // Set mtvec to the trap handler address
    la t0, trap_handler
    csrw 0x305, t0      // mtvec = 0x305
    
    // Enable Machine Interrupts (MIE = bit 3)
    li t0, 8            // bit 3 = 8
    csrw 0x300, t0      // mstatus = 0x300
    
    // Print "A" repeatedly, interrupts will print "*"
loop:
    li t1, 65
    sb t1, 0(s10)
    
    // Tiny delay
    li t2, 10
delay_loop:
    addi t2, t2, -1
    bnez t2, delay_loop
    
    j loop


// ---------------------------------------------------------
// Trap Handler
// ---------------------------------------------------------
trap_handler:
    // We are not saving registers for this simple test,
    // assuming it won't crash if t1/t2 get overwritten since it's just a test.
    // In a real handler we would save registers to stack.
    
    li t5, 42           // '*'
    sb t5, 0(s10)       // Print '*'
    
    // MRET returns to the interrupted instruction
    mret
