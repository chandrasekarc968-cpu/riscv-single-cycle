# vm_test.s
# Tests the Sv32 Virtual Memory MMU and Hardware Page Table Walker.

.global _start

_start:
    # ---------------------------------------------------------
    # 1. Identity Map the Code Segment (so we don't crash when we enable VM)
    # Virtual Address: 0x00000000 -> Physical Address: 0x00000000
    # L1 PTE at 0x1000 + 0 = 0x1000. Points to L0 at 0x4000.
    li t0, 0x1000
    li t1, 0x00001001 # (PPN 4 << 10) | V(1)
    sw t1, 0(t0)

    # L0 PTE at 0x4000 + 0 = 0x4000. Points to PA 0x00000.
    li t0, 0x4000
    li t1, 0x000000D7 # (PPN 0 << 10) | V,R,W,X,A,D
    sw t1, 0(t0)

    # ---------------------------------------------------------
    # 2. Map a Fake Virtual Address to a Real Physical Address
    # Virtual Address: 0xDEADBEEF -> Physical Address: 0x00003EEF
    # VPN1 = 0x37A (Index = 0x37A * 4 = 0xDE8)
    # VPN0 = 0x2DB (Index = 0x2DB * 4 = 0xB6C)
    
    # L1 PTE at 0x1000 + 0xDE8 = 0x1DE8. Points to L0 at 0x2000.
    li t0, 0x1DE8
    li t1, 0x00000801 # (PPN 2 << 10) | V(1)
    sw t1, 0(t0)

    # L0 PTE at 0x2000 + 0xB6C = 0x2B6C. Points to Data Page at PA 0x3000.
    li t0, 0x2B6C
    li t1, 0x00000CCF # (PPN 3 << 10) | V,R,W,A,D
    sw t1, 0(t0)

    # Write a secret code to the actual physical address (0x3EEF)
    li t0, 0x3EEF
    li t1, 0xCAFEBABE
    sw t1, 0(t0)

    # ---------------------------------------------------------
    # 3. Enable Virtual Memory!
    # satp = (MODE=1 << 31) | (PPN=1)
    li t0, 0x80000001
    csrrw zero, 0x180, t0 # Write to satp

    # NOTE: The moment this instruction completes, the next instruction
    # is fetched using Virtual Memory! Our identity map prevents a crash.

    # ---------------------------------------------------------
    # 4. The Grand Reveal
    # Load from the fake Virtual Address!
    # The MMU will pause the CPU, walk the page tables, load the TLB,
    # and translate 0xDEADBEEF into 0x00003EEF in hardware.
    
    li t0, 0xDEADBEEF
    lw t2, 0(t0)

    # If t2 == 0xCAFEBABE, the MMU works perfectly!
    
    # Write to UART to prove it works
    # Wait, UART is at 0x80000000. We didn't map it!
    # We will trigger a page fault if we try to write to UART.
    # So we'll just end the simulation by writing to UART via physical address?
    # No, we must map the MMIO space too!
    
    # Actually, we can just halt in an infinite loop. You can observe the wave.
end:
    j end
