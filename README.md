# Single-Cycle RISC-V Processor

This repository contains a 32-bit single-cycle RISC-V processor core implemented in Verilog, along with a custom Rust-based assembler.

## Processor Architecture

The processor implements a significant portion of the RV32I base integer instruction set. 

### Supported Instructions
- **Memory**: `lw`, `sw`, `lb`, `lh`, `lbu`, `lhu`, `sb`, `sh` (Includes sub-word byte and halfword accesses)
- **ALU (R-Type/I-Type)**: `add`, `addi`, `sub`, `and`, `andi`, `or`, `ori`, `xor`, `xori`, `slt`, `slti`, `sltu`, `sltiu`
- **Shifts**: `sll`, `slli`, `srl`, `srli`, `sra`, `srai`
- **Branches (B-Type)**: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`
- **Jumps**: `jal`, `jalr`
- **Upper Immediate (U-Type)**: `lui`, `auipc`

### Core Components
- `alu.v`: Performs arithmetic and logic operations, and evaluates branch conditions.
- `controller.v` / `aludec.v`: Decodes instructions and orchestrates the datapath multiplexers.
- `dmem.v`: Data memory with byte-enables (`we` is a 4-bit mask) for precise sub-word memory stores.
- `riscv.v`: The core datapath, containing branch evaluation, memory interface adapter (for sign-extensions and alignment), and register file connections.

## RISC-V Assembler (Rust)

Included in the `riscv-asm/` directory is a custom, zero-dependency RV32I assembler written in Rust. It compiles standard RISC-V assembly (`.s` files) directly into 32-bit hexadecimal machine code (`program.hex`) compatible with the Verilog `$readmemh` system task.

### Features
- Support for labels (e.g., `loop:`) with automatic address calculation (2-pass parser).
- Expands common pseudo-instructions (`li`, `mv`, `nop`).
- Resolves all supported core instructions.

### Usage

Ensure you have Rust installed, then run the assembler on your assembly file:

```bash
cd riscv-asm
cargo run -- ../test.s ../program.hex
```

This will assemble the instructions from `test.s` into `program.hex`, which will automatically be loaded by `imem.v` during your next processor simulation.
