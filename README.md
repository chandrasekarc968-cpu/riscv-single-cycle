# Single-Cycle RISC-V Processor

A 32-bit single-cycle RISC-V processor (RV32I) implemented in Verilog, with a write-through data cache, MMIO peripherals, and a custom Rust-based assembler.

## Architecture Overview

```
                          ┌─────────────────────────────────────────────────────────┐
                          │                    RISC-V Core (riscv.v)                │
                          │                                                         │
  ┌──────────┐   instr    │  ┌──────────┐    ┌────────────┐    ┌─────┐             │
  │  IMEM    │───────────►│  │Controller │───►│  Datapath   │───►│ ALU │             │
  │ (16 KB)  │            │  │          │    │  (regfile,  │◄───│     │             │
  │ imem.v   │◄───────────│  │controller│    │   extend,   │    └─────┘             │
  └──────────┘    PC      │  │   .v     │    │    pc)      │                        │
                          │  └──────────┘    └──────┬──────┘                        │
                          │                         │ addr / data                   │
                          └─────────────────────────┼───────────────────────────────┘
                                                    │
                                    ┌───────────────┼───────────────┐
                                    │               │               │
                              ┌─────▼─────┐   ┌────▼────┐   ┌──────▼──────┐
                              │   MMIO    │   │  Data   │   │ Main Memory │
                              │ (top.v)   │   │  Cache  │──►│   (10 MB)   │
                              │           │   │ (1 KB)  │◄──│main_memory.v│
                              │ UART TX/RX│   │dcache.v │   └─────────────┘
                              │ Timer     │   └─────────┘
                              │ Finish    │
                              └───────────┘
```

## Supported Instructions (RV32I)

| Category | Instructions |
|---|---|
| **Memory** | `lw`, `sw`, `lb`, `lh`, `lbu`, `lhu`, `sb`, `sh` |
| **ALU (R/I-Type)** | `add`, `addi`, `sub`, `and`, `andi`, `or`, `ori`, `xor`, `xori`, `slt`, `slti`, `sltu`, `sltiu` |
| **Shifts** | `sll`, `slli`, `srl`, `srli`, `sra`, `srai` |
| **Branches** | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| **Jumps** | `jal`, `jalr` |
| **Upper Immediate** | `lui`, `auipc` |
| **System** | `fence`, `ecall`, `ebreak` (treated as NOPs) |

## Memory Map

| Address | Size | Access | Description |
|---|---|---|---|
| `0x00000000` – `0x009FFFFF` | 10 MB | R/W | Main RAM (data + program storage) |
| `0x80000000` | 1 byte | W | UART TX — write a byte to output |
| `0x80000004` | 1 byte | R | UART RX — read a byte (stalls until input ready) |
| `0x80000008` | 4 bytes | R | Timer — cycle counter (read-only) |
| `0x8000000C` | 4 bytes | R | Cycle counter (alias of timer) |
| `0x80000010` | 4 bytes | W | Simulation finish — write any value to halt |

## Core Components

| File | Description |
|---|---|
| `riscv.v` | Core datapath — branch evaluation, memory interface (sign-extension & alignment), register file connections |
| `controller.v` | Instruction decoder: main decoder + ALU decoder, orchestrates datapath muxes |
| `alu.v` | Arithmetic and logic operations, branch condition evaluation |
| `regfile.v` | 32×32-bit register file with async read, sync write, hardwired x0=0 |
| `extend.v` | Immediate sign-extension for I/S/B/J/U-type formats |
| `pc.v` | Program counter with enable (for stalls) and async reset |
| `imem.v` | 16 KB instruction memory, loaded from `program.hex` via `$readmemh` |
| `dcache.v` | 1 KB direct-mapped write-through data cache (64 lines × 16B), with write-allocate |
| `main_memory.v` | 10 MB main RAM with configurable latency (default 4 cycles) |
| `top.v` | Top-level integration: CPU + IMEM + Cache + Main Memory + MMIO |
| `tb.v` | Testbench: clock generation, reset, timeout, VCD waveform dump |

## RISC-V Assembler (Rust)

The `riscv-asm/` directory contains a custom, zero-dependency RV32I assembler written in Rust. It compiles `.s` assembly files into `program.hex` files compatible with the Verilog `$readmemh` system task.

### Assembler Features

- **2-pass assembly** with automatic label address resolution
- **Escape sequences** in `.string` directives (`\n`, `\t`, `\\`, `\"`, `\0`)
- **Error messages** with line numbers and source context
- **Data directives**: `.word`, `.string`, `.byte`
- **Comment styles**: `//`, `#`, `;`

### Supported Pseudo-Instructions

| Pseudo | Expansion |
|---|---|
| `li rd, imm` | `addi` or `lui` + `addi` |
| `mv rd, rs` | `addi rd, rs, 0` |
| `la rd, label` | `lui` + `addi` (address load) |
| `nop` | `addi x0, x0, 0` |
| `neg rd, rs` | `sub rd, x0, rs` |
| `not rd, rs` | `xori rd, rs, -1` |
| `seqz rd, rs` | `sltiu rd, rs, 1` |
| `snez rd, rs` | `sltu rd, x0, rs` |
| `beqz rs, label` | `beq rs, x0, label` |
| `bnez rs, label` | `bne rs, x0, label` |
| `blez rs, label` | `bge x0, rs, label` |
| `bgtz rs, label` | `blt x0, rs, label` |
| `bgez rs, label` | `bge rs, x0, label` |
| `bltz rs, label` | `blt rs, x0, label` |
| `j label` | `jal x0, label` |
| `ret` | `jalr x0, ra, 0` |
| `call label` | `jal ra, label` |
| `tail label` | `jal x0, label` |

## Getting Started

### Prerequisites

- **Verilog simulator**: [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` + `vvp`)
- **Waveform viewer**: [GTKWave](http://gtkwave.sourceforge.net/) (optional, for `.vcd` files)
- **Rust toolchain**: [rustup.rs](https://rustup.rs/) (for the assembler)

### Build & Run

```bash
# 1. Assemble your program
cd riscv-asm
cargo run -- ../test.s ../program.hex

# 2. Compile the Verilog design
cd ..
iverilog -o sim.vvp tb.v top.v riscv.v controller.v alu.v extend.v regfile.v pc.v imem.v dcache.v main_memory.v

# 3. Run the simulation
vvp sim.vvp

# 4. (Optional) View waveforms
gtkwave wave.vcd
```

### Running the "Guess the Number" Game

```bash
cd riscv-asm
cargo run -- ../game.s ../program.hex
cd ..
iverilog -o sim.vvp tb.v top.v riscv.v controller.v alu.v extend.v regfile.v pc.v imem.v dcache.v main_memory.v
vvp sim.vvp
```

<<<<<<< HEAD
The game uses UART MMIO for I/O — type a digit (1-9) and press Enter when prompted.

## Design Notes

- **Single-cycle**: Each instruction completes in one clock cycle (plus cache/memory stalls).
- **Cache stalls**: The data cache introduces multi-cycle stalls on read misses and all writes (write-through policy). Write-allocate ensures the cache stays coherent.
- **Memory latency**: Main memory has a configurable latency parameter (default: 4 cycles) to simulate realistic DRAM timing.
- **JALR bit-0 clear**: Per RISC-V spec §2.5, the JALR target address has bit 0 forced to zero.
=======
This will assemble the instructions from `test.s` into `program.hex`, which will automatically be loaded by `imem.v` during your next processor simulation.cakl
>>>>>>> bbe8cd3b30370da037abba74bfc39191533ca252
