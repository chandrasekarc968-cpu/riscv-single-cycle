// ---------------------------------------------------------
// DRAGON SLAYER RPG
// ---------------------------------------------------------
.text

main:
    li s10, 0x80000000  // UART TX
    li s11, 0x80000004  // UART RX
    li s9,  0x8000000C  // Cycle counter (for PRNG)
    
    // Player HP (s0) = 100
    li s0, 100
    // Dragon HP (s1) = 100
    li s1, 100

    // Print welcome
    la a0, msg_welcome
    call print_str
    
battle_loop:
    // Check win/loss
    blez s0, lose
    blez s1, win

    // Print Player HP
    la a0, msg_stats_p
    call print_str
    mv a0, s0
    call print_num
    
    // Print Dragon HP
    la a0, msg_stats_d
    call print_str
    mv a0, s1
    call print_num
    
    // Print menu
    la a0, msg_menu
    call print_str

wait_input:
    lw t0, 0(s11)       // read RX (blocking)
    
    li t1, 49           // '1'
    beq t0, t1, do_attack
    li t2, 50           // '2'
    beq t0, t2, do_heal
    j wait_input

do_attack:
    la a0, msg_newline
    call print_str
    la a0, msg_attack
    call print_str
    
    // Random damage 10-25
    lw t0, 0(s9)        // read cycle counter
    andi t0, t0, 15     // 0 to 15
    addi t0, t0, 10     // 10 to 25
    sub s1, s1, t0      // Dragon HP -= dmg
    
    // Print damage amount
    la a0, msg_dmg
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    
    j dragon_turn

do_heal:
    la a0, msg_newline
    call print_str
    la a0, msg_heal
    call print_str
    
    // Random heal 20-35
    lw t0, 0(s9)
    andi t0, t0, 15
    addi t0, t0, 20
    add s0, s0, t0
    
    // Max HP = 100
    li t1, 100
    bge t1, s0, print_heal_amt
    mv s0, t1

print_heal_amt:
    // Print heal amount
    la a0, msg_heal_amt
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    
    j dragon_turn

dragon_turn:
    // Check if dragon died before attacking
    blez s1, win

    la a0, msg_dragon_attack
    call print_str
    
    // Random damage 10-32
    lw t0, 0(s9)
    andi t0, t0, 15
    lw t1, 0(s9)
    srli t1, t1, 2
    andi t1, t1, 7
    add t0, t0, t1  // 0-15 + 0-7 = 0-22
    addi t0, t0, 10 // 10-32
    
    sub s0, s0, t0

    // Print damage amount
    la a0, msg_dmg
    call print_str
    mv a0, t0
    call print_num
    la a0, msg_bracket
    call print_str
    la a0, msg_newline
    call print_str
    la a0, msg_newline
    call print_str
    
    j battle_loop

win:
    la a0, msg_win
    call print_str
    j end_game

lose:
    la a0, msg_lose
    call print_str
    j end_game

end_game:
    // Halt
    li t0, 0x80000010
    sw zero, 0(t0)
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

// print_num(a0: positive number up to 999)
print_num:
    bgez a0, print_num_start
    li a0, 0
print_num_start:
    li t0, 100
    li t1, 0 // hundreds count
hundreds_loop:
    blt a0, t0, hundreds_done
    sub a0, a0, t0
    addi t1, t1, 1
    j hundreds_loop
hundreds_done:
    
    li t0, 10
    li t2, 0 // tens count
tens_loop:
    blt a0, t0, tens_done
    sub a0, a0, t0
    addi t2, t2, 1
    j tens_loop
tens_done:

    // print hundreds if > 0
    beqz t1, check_tens
    addi t3, t1, 48
    sb t3, 0(s10)
    j do_print_tens // if hundreds > 0, always print tens even if 0

check_tens:
    beqz t2, print_ones
do_print_tens:
    addi t3, t2, 48
    sb t3, 0(s10)
    
print_ones:
    addi t3, a0, 48
    sb t3, 0(s10)
    ret

// ---------------------------------------------------------
// Data
// ---------------------------------------------------------
msg_welcome:
    .string "================================\n||       DRAGON SLAYER        ||\n================================\n\nA fearsome dragon stands before you!\n\n"
msg_stats_p:
    .string "  [Player HP: "
msg_stats_d:
    .string "]      [Dragon HP: "
msg_menu:
    .string "]\n\nOptions:\n  1. Attack with Sword\n  2. Drink Health Potion\n\nCommand (1/2)> "
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
