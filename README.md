# 🚀 Dual-Core RV32IM Processor with Advanced Memory & CSRs

[![RISC-V](https://img.shields.io/badge/ISA-RV32IM-blue.svg)](https://riscv.org/)
[![Hardware](https://img.shields.io/badge/Hardware-Verilog-orange.svg)]()
[![Assembler](https://img.shields.io/badge/Assembler-Rust-red.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

A 32-bit **Dual-Core** RISC-V processor implemented in Verilog from the ground up. What started as a basic RV32I educational core has been heavily escalated into a powerful **Symmetric Multiprocessing (SMP)** architecture featuring the **RV32IM instruction set**, a unified 10MB main memory with an advanced **Instruction & Data Cache hierarchy**, **hardware interrupts (CSRs)**, a **Hardware Mutex**, and a custom Rust-based assembler.

---

## 🏗️ Architecture Overview

The system utilizes a dual-core Von Neumann architecture with unified main memory. Each core possesses its own private L1 cache hierarchy, and a bus arbiter safely multiplexes their requests to the shared RAM.

```text
       CORE 0                                              CORE 1
 ┌────────────────┐                                  ┌────────────────┐
 │  RISC-V Core   │                                  │  RISC-V Core   │
 │   (riscv.v)    │                                  │   (riscv.v)    │
 │ (hartid = 0)   │                                  │ (hartid = 1)   │
 └─┬────────────┬─┘                                  └─┬────────────┬─┘
   │ instr      │ data                                 │ instr      │ data
 ┌─▼─────┐  ┌───▼───┐                              ┌───▼───┐  ┌─────▼─┐
 │I-Cache│  │D-Cache│                              │D-Cache│  │I-Cache│
 │(1 KB) │  │(1 KB) │                              │(1 KB) │  │(1 KB) │
 └─┬─────┘  └───┬───┘                              └───┬───┘  └─────┬─┘
   │            │                                      │            │
 ┌─▼────────────▼─┐                                  ┌─▼────────────▼─┐
 │ Memory Arbiter │                                  │ Memory Arbiter │
 │  (arbiter.v)   │                                  │  (arbiter.v)   │
 └────────┬───────┘                                  └───────┬────────┘
          │                                                  │
          └───────────────────────┐  ┌───────────────────────┘
                                ┌─▼──▼─┐
                                │ Bus  │
                                │Arbit.│
                                └──┬───┘
                                   │
                         ┌─────────▼────────┐
                         │   Main Memory    │
                         │      (10MB)      │
                         └──────────────────┘
```

---

## ⚡ Key Features

### 1. Dual-Core SMP & Hardware Mutex
The system runs two identical RISC-V cores concurrently! To prevent race conditions and overlapping I/O (like both cores writing to the screen simultaneously), we've implemented a **Hardware Mutex** mapped to the MMIO space. Cores can utilize a simple Read-to-Lock paradigm to synchronize their execution.

### 2. Hardware Math (M-Extension)
A dedicated `muldiv.v` unit implements multi-cycle state machines for precise, hardware-accelerated integer multiplication and division. The pipeline automatically stalls until the math operation yields a result.

### 3. Advanced Unified Memory Hierarchy
Say goodbye to instantaneous split memory. This core features:
- **10MB Unified Main Memory** with realistic, configurable access latency.
- **Private 2-Way Set Associative D-Caches** (1KB) with LRU replacement and write-allocate policies for each core.
- **Private Direct-Mapped I-Caches** (1KB) for high-speed instruction fetching.
- **Bus Arbiter** to seamlessly route parallel I-Cache and D-Cache requests from *both* cores to the slower main RAM without deadlocks.

### 4. OS-Level Privilege & Interrupts (CSRs)
The `csr_file.v` module introduces Machine-Mode Control and Status Registers:
- Tracks `mstatus`, `mtvec`, `mepc`, `mcause`, and `mhartid` (Hardware Thread ID).
- Fully supports `ecall`, `mret`, and timer interrupts.
- A built-in hardware timer interrupt fires automatically every 4,096 cycles, allowing for preemptive multitasking experiments!

---

## 📚 Supported Instructions (RV32IM + System)

| Category | Instructions |
|---|---|
| **Memory** | `lw`, `sw`, `lb`, `lh`, `lbu`, `lhu`, `sb`, `sh` |
| **ALU (R/I-Type)** | `add`, `addi`, `sub`, `and`, `andi`, `or`, `ori`, `xor`, `xori`, `slt`, `slti`, `sltu`, `sltiu` |
| **Shifts** | `sll`, `slli`, `srl`, `srli`, `sra`, `srai` |
| **Branches** | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| **Jumps** | `jal`, `jalr` |
| **Upper Immediate** | `lui`, `auipc` |
| **Multiply/Divide (M)**| `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, `remu` |
| **System / CSRs** | `csrrw`, `csrr`, `csrw`, `ecall`, `ebreak`, `mret`, `fence` |

---

## 🗺️ Memory Map

| Address | Size | Access | Description |
|---|---|---|---|
| `0x00000000` – `0x009FFFFF` | 10 MB | R/W | Unified Main RAM (Instructions + Data) |
| `0x80000000` | 1 byte | W | UART TX — write a byte to output |
| `0x80000004` | 1 byte | R | UART RX — read a byte (stalls until input ready) |
| `0x80000008` | 4 bytes | R | Timer — cycle counter (read-only) |
| `0x8000000C` | 4 bytes | R | Cycle counter (alias of timer) |
| `0x80000010` | 4 bytes | W | Simulation finish — write any value to halt |
| `0x80000014` | 4 bytes | R/W | **Hardware Mutex** — Read 0 to lock (returns 1 if already locked), Write 0 to unlock |

---

## 🧩 Core Components

| File | Description |
|---|---|
| `riscv.v` | Core datapath — branch evaluation, memory interface, hardware trap logic |
| `controller.v` | Instruction decoder: main decoder + ALU decoder, orchestrates datapath and pipeline stalls |
| `alu.v` | Arithmetic and logic operations, branch condition evaluation |
| `muldiv.v` | Hardware multiplier and restoring divider (multi-cycle state machine) |
| `csr_file.v` | Control and Status Registers (`mstatus`, `mtvec`, `mepc`, `mcause`, `mhartid`) and interrupt handling |
| `regfile.v` | 32×32-bit register file with async read, sync write, hardwired x0=0 |
| `dcache.v` | 1 KB 2-Way Set Associative data cache with LRU replacement and write-allocate |
| `icache.v` | 1 KB Direct-Mapped instruction cache |
| `arbiter.v` | Local Memory Arbiter to resolve requests between a single core's I-Cache and D-Cache |
| `bus_arbiter.v` | Global Bus Arbiter to multiplex memory requests from both cores to Main Memory |
| `main_memory.v` | 10 MB unified RAM with configurable latency (default 4 cycles) |
| `top.v` | Top-level integration: Dual CPUs + 4 Caches + 3 Arbiters + Main Memory + MMIO & Mutex |
| `tb.v` | Testbench: clock generation, reset, timeout, VCD waveform dump |

---

## 🛠️ RISC-V Assembler (Rust)

The `riscv-asm/` directory contains a custom, zero-dependency **RV32IM assembler** written in Rust. It compiles `.s` assembly files directly into `program.hex` files compatible with the Verilog `$readmemh` system task.

<details>
<summary><b>View Supported Pseudo-Instructions</b></summary>

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
| `csrr rd, csr` | `csrrw rd, csr, x0` |
| `csrw csr, rs` | `csrrw x0, csr, rs` |

</details>

---

## 🚀 Getting Started

### Prerequisites

- **Verilog simulator**: [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` + `vvp`)
- **Waveform viewer**: [GTKWave](http://gtkwave.sourceforge.net/) (optional, for `.vcd` files)
- **Rust toolchain**: [rustup.rs](https://rustup.rs/) (for the assembler)

### Build & Run Dual-Core Diagnostics

```bash
# 1. Assemble the Multicore Mutex test program
cd riscv-asm
cargo run -- ../multicore_test.s ../program.hex

# 2. Compile the Dual-Core Verilog design
cd ..
iverilog -o sim.vvp tb.v top.v riscv.v controller.v alu.v extend.v regfile.v pc.v icache.v dcache.v arbiter.v bus_arbiter.v main_memory.v muldiv.v csr_file.v

# 3. Run the simulation
vvp sim.vvp
```

### 🐉 Running the "Dragon Slayer" RPG

Experience the processor running a fully interactive MMIO game!

```bash
cd riscv-asm
cargo run -- ../game.s ../program.hex
cd ..
iverilog -o sim.vvp tb.v top.v riscv.v controller.v alu.v extend.v regfile.v pc.v icache.v dcache.v arbiter.v bus_arbiter.v main_memory.v muldiv.v csr_file.v
vvp sim.vvp
```

The game uses UART MMIO for I/O — you'll see a text-based RPG interface right in your terminal. Type '1' or '2' and press Enter to fight the dragon!

---

## 📝 Design Notes

- **Multi-cycle Extensions**: While mostly single-cycle, the processor asserts hardware stall requests during multi-cycle operations like M-extension math (`mul`, `div`), cache misses, and timer interrupts.
- **Cache Architecture**: The data cache utilizes a 2-way set associative organization with an LRU tracking bit per set. The instruction cache is direct-mapped. Both caches route to unified main memory via an arbiter.
- **Hardware Traps**: Basic machine-mode privileges are implemented. Setting `mstatus.MIE` enables a hardware timer interrupt that fires every 4096 cycles, trapping to the vector loaded in `mtvec`. Return via `mret`.
- **SMP Interconnects**: Due to both cores sharing memory, `bus_arbiter.v` sits upstream of the main memory. It prioritizes `core0` if both cores suffer a cache miss on the exact same cycle, preventing bus starvation.
