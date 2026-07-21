// Dual-Core Mutex Test Program
// Core 0 will print "0" repeatedly, Core 1 will print "1".
// They use a Hardware Mutex (0x80000014) to prevent their prints from interleaving chaotically.

.text
main:
    li s10, 0x80000000  // UART TX
    li s11, 0x80000014  // Hardware Mutex

    // Read mhartid to determine which core this is
    csrr a0, 0xF14
    
    // If hartid == 1, jump to core1_loop
    li t0, 1
    beq a0, t0, core1_loop

// ---------------------------------------------------------
// Core 0 Code
// ---------------------------------------------------------
core0_loop:
    // 1. Acquire Mutex
    // Read from 0x80000014. If it returns 0, we got the lock. If 1, someone else has it.
core0_spin:
    lw t0, 0(s11)
    bnez t0, core0_spin // Loop until lock is acquired

    // 2. Critical Section
    // Print "Core 0\n"
    li t1, 67 // 'C'
    sb t1, 0(s10)
    li t1, 111 // 'o'
    sb t1, 0(s10)
    li t1, 114 // 'r'
    sb t1, 0(s10)
    li t1, 101 // 'e'
    sb t1, 0(s10)
    li t1, 32 // ' '
    sb t1, 0(s10)
    li t1, 48 // '0'
    sb t1, 0(s10)
    li t1, 10 // '\n'
    sb t1, 0(s10)

    // 3. Release Mutex (write 0)
    sw x0, 0(s11)
    
    // Delay to let the other core get a chance
    li t2, 50
core0_delay:
    addi t2, t2, -1
    bnez t2, core0_delay
    
    j core0_loop

// ---------------------------------------------------------
// Core 1 Code
// ---------------------------------------------------------
core1_loop:
    // 1. Acquire Mutex
core1_spin:
    lw t0, 0(s11)
    bnez t0, core1_spin

    // 2. Critical Section
    // Print "Core 1\n"
    li t1, 67 // 'C'
    sb t1, 0(s10)
    li t1, 111 // 'o'
    sb t1, 0(s10)
    li t1, 114 // 'r'
    sb t1, 0(s10)
    li t1, 101 // 'e'
    sb t1, 0(s10)
    li t1, 32 // ' '
    sb t1, 0(s10)
    li t1, 49 // '1'
    sb t1, 0(s10)
    li t1, 10 // '\n'
    sb t1, 0(s10)

    // 3. Release Mutex (write 0)
    sw x0, 0(s11)

    // Delay
    li t2, 50
core1_delay:
    addi t2, t2, -1
    bnez t2, core1_delay
    
    j core1_loop
