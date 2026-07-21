// ---------------------------------------------------------
// ASYNCHRONOUS DRAGON SLAYER RPG (DUAL CORE)
// ---------------------------------------------------------
.text
main:
    li s10, 0x80000000  // UART TX
    li s11, 0x80000004  // UART RX
    li s9,  0x8000000C  // Cycle counter (for PRNG)
    li s8,  0x80000014  // Hardware Mutex
    li s6,  0x2000      // Shared: Player HP Address
    li s5,  0x2004      // Shared: Dragon HP Address
    li s7,  0x2008      // Shared: Game Status Address
    
    // Read mhartid
    csrr a0, 0xF14
    li t0, 1
    beq a0, t0, core1_main

// =========================================================
// CORE 0: PLAYER LOOP
// =========================================================
core0_main:
    // Initialize Shared State
    li t0, 100
    sw t0, 0(s6)
    sw t0, 0(s5)
    sw zero, 0(s7)

    // Acquire Mutex & Print Welcome
    call lock_mutex
    la a0, msg_welcome
    call print_str
    call unlock_mutex

core0_loop:
    // Check game over
    lw t0, 0(s7)
    bnez t0, end_game

    // Check win/loss
    lw t1, 0(s6)
    blez t1, do_lose
    lw t2, 0(s5)
    blez t2, do_win

    // Print Stats & Menu
    call lock_mutex
    la a0, msg_stats_p
    call print_str
    lw a0, 0(s6)
    call print_num
    la a0, msg_stats_d
    call print_str
    lw a0, 0(s5)
    call print_num
    la a0, msg_menu
    call print_str
    call unlock_mutex

core0_wait_input:
    // Check if game ended while waiting
    lw t0, 0(s7)
    bnez t0, end_game

    lw t0, 0(s11)       // read RX (blocking)
    li t1, 49           // '1'
    beq t0, t1, core0_attack
    li t2, 50           // '2'
    beq t0, t2, core0_heal
    j core0_wait_input

core0_attack:
    call lock_mutex
    la a0, msg_newline
    call print_str
    la a0, msg_attack
    call print_str
    
    // Damage Dragon
    lw t0, 0(s9)
    andi t0, t0, 15
    addi t0, t0, 10
    
    lw t1, 0(s5)
    sub t1, t1, t0
    sw t1, 0(s5)
    
    // Print damage amount
    la a0, msg_dmg
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    
    call unlock_mutex
    j core0_loop

core0_heal:
    call lock_mutex
    la a0, msg_newline
    call print_str
    la a0, msg_heal
    call print_str
    
    // Heal Player
    lw t0, 0(s9)
    andi t0, t0, 15
    addi t0, t0, 20
    
    lw t1, 0(s6)
    add t1, t1, t0
    li t2, 100
    bge t2, t1, c0_write_hp
    mv t1, t2 // cap at 100
c0_write_hp:
    sw t1, 0(s6)
    
    la a0, msg_heal_amt
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    
    call unlock_mutex
    j core0_loop

do_win:
    li t0, 1
    sw t0, 0(s7)
    call lock_mutex
    la a0, msg_win
    call print_str
    call unlock_mutex
    j end_game

do_lose:
    li t0, 2
    sw t0, 0(s7)
    call lock_mutex
    la a0, msg_lose
    call print_str
    call unlock_mutex
    j end_game

// =========================================================
// CORE 1: ASYNCHRONOUS DRAGON AI
// =========================================================
core1_main:
    // Wait briefly to allow Core 0 to initialize the game state
    li t0, 100
core1_init_delay:
    addi t0, t0, -1
    bnez t0, core1_init_delay

core1_loop:
    // Check if game over
    lw t0, 0(s7)
    bnez t0, end_game

    // Long Delay (Dragon Cooldown)
    li t0, 1500
core1_delay:
    lw t1, 0(s7)
    bnez t1, end_game
    addi t0, t0, -1
    bnez t0, core1_delay

    // Check again before attacking
    lw t0, 0(s7)
    bnez t0, end_game
    lw t0, 0(s5)
    blez t0, end_game
    
    // Dragon attacks asynchronously!
    call lock_mutex
    la a0, msg_newline
    call print_str
    la a0, msg_dragon_attack
    call print_str
    
    // Damage Player
    lw t0, 0(s9)
    andi t0, t0, 15
    lw t1, 0(s9)
    srli t1, t1, 2
    andi t1, t1, 7
    add t0, t0, t1
    addi t0, t0, 10
    
    lw t1, 0(s6)
    sub t1, t1, t0
    sw t1, 0(s6)
    
    la a0, msg_dmg
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    
    // Re-print prompt since we just interrupted the player
    la a0, msg_prompt
    call print_str

    call unlock_mutex
    j core1_loop

// =========================================================
// COMMON
// =========================================================
end_game:
    // Halt Simulation
    li t0, 0x80000010
    sw zero, 0(t0)
inf:
    j inf

// ---------------------------------------------------------
// Mutex Subroutines
// ---------------------------------------------------------
lock_mutex:
lock_spin:
    lw t6, 0(s8)
    bnez t6, lock_spin
    ret

unlock_mutex:
    sw zero, 0(s8)
    ret

// ---------------------------------------------------------
// Print Subroutines
// ---------------------------------------------------------
print_str:
    mv t3, a0 // use t3 to avoid clobbering by print_num
print_str_loop:
    lb t4, 0(t3)
    beqz t4, print_str_done
    sb t4, 0(s10)
    addi t3, t3, 1
    j print_str_loop
print_str_done:
    ret

print_num:
    bgez a0, print_num_start
    li a0, 0
print_num_start:
    li t3, 100
    li t4, 0
hundreds_loop:
    blt a0, t3, hundreds_done
    sub a0, a0, t3
    addi t4, t4, 1
    j hundreds_loop
hundreds_done:
    
    li t3, 10
    li t5, 0
tens_loop:
    blt a0, t3, tens_done
    sub a0, a0, t3
    addi t5, t5, 1
    j tens_loop
tens_done:

    beqz t4, check_tens
    addi t6, t4, 48
    sb t6, 0(s10)
    j do_print_tens

check_tens:
    beqz t5, print_ones
do_print_tens:
    addi t6, t5, 48
    sb t6, 0(s10)
    
print_ones:
    addi t6, a0, 48
    sb t6, 0(s10)
    ret

// ---------------------------------------------------------
// Data
// ---------------------------------------------------------
msg_welcome:
    .string "================================\n||   DUAL-CORE DRAGON SLAYER  ||\n================================\n\nA fearsome dragon stands before you!\nIt moves in real-time... don't wait too long!\n\n"
msg_stats_p:
    .string "\n  [Player HP: "
msg_stats_d:
    .string "]      [Dragon HP: "
msg_menu:
    .string "]\n\nOptions:\n  1. Attack with Sword\n  2. Drink Health Potion\n\nCommand (1/2)> "
msg_prompt:
    .string "\nCommand (1/2)> "
msg_attack:
    .string ">> You swing your mighty sword at the dragon!"
msg_heal:
    .string ">> You drink a glowing red potion."
msg_dragon_attack:
    .string ">> The Dragon breathes a column of scorching fire!"
msg_dmg:
    .string " (Damage: "
msg_heal_amt:
    .string " (Healed: "
msg_bracket:
    .string ")"
msg_newline:
    .string "\n"
msg_win:
    .string "\n================================\n|| THE DRAGON IS DEFEATED!    ||\n|| YOU ARE THE TRUE SLAYER!   ||\n================================\n"
msg_lose:
    .string "\n================================\n|| YOU HAVE BEEN ROASTED...   ||\n||        GAME OVER           ||\n================================\n"
