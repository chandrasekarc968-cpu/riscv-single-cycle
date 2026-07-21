use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Write};

fn parse_reg(reg: &str, line_num: usize, line_text: &str) -> u32 {
    let reg = reg.trim();
    match reg {
        "x0" | "zero" => 0,
        "x1" | "ra" => 1,
        "x2" | "sp" => 2,
        "x3" | "gp" => 3,
        "x4" | "tp" => 4,
        "x5" | "t0" => 5,
        "x6" | "t1" => 6,
        "x7" | "t2" => 7,
        "x8" | "s0" | "fp" => 8,
        "x9" | "s1" => 9,
        "x10" | "a0" => 10,
        "x11" | "a1" => 11,
        "x12" | "a2" => 12,
        "x13" | "a3" => 13,
        "x14" | "a4" => 14,
        "x15" | "a5" => 15,
        "x16" | "a6" => 16,
        "x17" | "a7" => 17,
        "x18" | "s2" => 18,
        "x19" | "s3" => 19,
        "x20" | "s4" => 20,
        "x21" | "s5" => 21,
        "x22" | "s6" => 22,
        "x23" | "s7" => 23,
        "x24" | "s8" => 24,
        "x25" | "s9" => 25,
        "x26" | "s10" => 26,
        "x27" | "s11" => 27,
        "x28" | "t3" => 28,
        "x29" | "t4" => 29,
        "x30" | "t5" => 30,
        "x31" | "t6" => 31,
        _ => {
            eprintln!("Error on line {}: Unknown register '{}'\n  --> {}", line_num, reg, line_text);
            std::process::exit(1);
        }
    }
}

fn parse_imm(imm: &str) -> u32 {
    let imm = imm.trim();
    if let Some(stripped) = imm.strip_prefix("0x") {
        u32::from_str_radix(stripped, 16).expect("Invalid hex immediate")
    } else if let Some(stripped) = imm.strip_prefix("-0x") {
        let val = u32::from_str_radix(stripped, 16).expect("Invalid hex immediate");
        (0_u32).wrapping_sub(val)
    } else if let Some(stripped) = imm.strip_prefix("0b") {
        u32::from_str_radix(stripped, 2).expect("Invalid binary immediate")
    } else {
        imm.parse::<i32>().unwrap_or_else(|_| {
            eprintln!("Error: Invalid immediate value '{}'", imm);
            std::process::exit(1);
        }) as u32
    }
}

/// Process escape sequences in a string literal
fn process_escapes(s: &str) -> Vec<u8> {
    let mut result = Vec::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('n') => result.push(0x0A),  // newline
                Some('r') => result.push(0x0D),  // carriage return
                Some('t') => result.push(0x09),  // tab
                Some('0') => result.push(0x00),   // null
                Some('\\') => result.push(0x5C),  // backslash
                Some('"') => result.push(0x22),   // double quote
                Some('\'') => result.push(0x27),  // single quote
                Some(other) => {
                    // Unknown escape: emit literally
                    result.push(b'\\');
                    result.push(other as u8);
                }
                None => result.push(b'\\'),
            }
        } else {
            result.push(c as u8);
        }
    }
    result
}

fn encode_r(opcode: u32, funct3: u32, funct7: u32, rd: u32, rs1: u32, rs2: u32) -> u32 {
    (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
}

fn encode_i(opcode: u32, funct3: u32, rd: u32, rs1: u32, imm: u32) -> u32 {
    ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
}

fn encode_s(opcode: u32, funct3: u32, rs1: u32, rs2: u32, imm: u32) -> u32 {
    let imm11_5 = (imm >> 5) & 0x7F;
    let imm4_0 = imm & 0x1F;
    (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode
}

fn encode_b(opcode: u32, funct3: u32, rs1: u32, rs2: u32, imm: u32) -> u32 {
    let imm12 = (imm >> 12) & 0x1;
    let imm11_5 = (imm >> 5) & 0x3F;
    let imm4_1 = (imm >> 1) & 0xF;
    let imm11 = (imm >> 11) & 0x1;
    (imm12 << 31) | (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | opcode
}

fn encode_u(opcode: u32, rd: u32, imm: u32) -> u32 {
    (imm & 0xFFFFF000) | (rd << 7) | opcode
}

fn encode_j(opcode: u32, rd: u32, imm: u32) -> u32 {
    let imm20 = (imm >> 20) & 0x1;
    let imm10_1 = (imm >> 1) & 0x3FF;
    let imm11 = (imm >> 11) & 0x1;
    let imm19_12 = (imm >> 12) & 0xFF;
    (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode
}

#[derive(Debug, Clone)]
struct ParsedLine {
    address: u32,
    original: String,
    line_num: usize,
    mnemonic: String,
    args: Vec<String>,
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <input.s> <output.hex>", args[0]);
        std::process::exit(1);
    }
    
    let input_path = &args[1];
    let output_path = &args[2];

    let file = File::open(input_path)?;
    let reader = io::BufReader::new(file);

    let mut instructions = Vec::new();
    let mut labels = HashMap::new();
    
    let mut current_addr = 0;

    // Pass 1: Parse and collect labels
    for (line_idx, line) in reader.lines().enumerate() {
        let raw_line = line?;
        let line_num = line_idx + 1;
        // Remove comments (supports //, #, and ;)
        let line = raw_line
            .split('#').next().unwrap()
            .split("//").next().unwrap()
            .split(';').next().unwrap()
            .trim();
        if line.is_empty() {
            continue;
        }

        // Check for label
        let mut instruction_part = line;
        if let Some(idx) = line.find(':') {
            let label = line[..idx].trim();
            labels.insert(label.to_string(), current_addr);
            instruction_part = line[idx + 1..].trim();
        }

        // Skip empty lines and non-emitting directives
        if instruction_part.is_empty() {
            continue;
        }
        // Recognized but ignored directives
        if instruction_part == ".text" || instruction_part == ".data"
            || instruction_part == ".globl" || instruction_part.starts_with(".global")
            || instruction_part.starts_with(".align") || instruction_part.starts_with(".section")
        {
            continue;
        }
        // Skip unknown directives (except .word, .string, .byte which emit data)
        if instruction_part.starts_with('.')
            && !instruction_part.starts_with(".word")
            && !instruction_part.starts_with(".string")
            && !instruction_part.starts_with(".byte")
        {
            continue;
        }

        // Tokenize instruction
        let mut parts = instruction_part.splitn(2, |c: char| c.is_whitespace());
        let mnemonic = parts.next().unwrap().to_lowercase();
        
        let args_str = parts.next().unwrap_or("").trim();
        let mut inst_args: Vec<String> = Vec::new();
        
        if mnemonic == ".string" {
            // Extract the content between quotes, preserving escape sequences
            let s = args_str.trim_matches('"');
            inst_args.push(s.to_string());
        } else if args_str.contains('(') {
            let mut parts_comma = args_str.split(',');
            let rd = parts_comma.next().unwrap().trim();
            inst_args.push(rd.to_string());
            
            let mut offset_reg = parts_comma.next().unwrap().trim().split('(');
            let offset = offset_reg.next().unwrap().trim();
            let mut reg = offset_reg.next().unwrap().trim().to_string();
            reg.pop(); // remove ')'
            inst_args.push(reg);
            inst_args.push(offset.to_string());
        } else {
            inst_args = args_str.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
        }
        
        // Pseudo-instructions expansion
        let mut expanded = Vec::new();
        match mnemonic.as_str() {
            "li" => {
                let rd = &inst_args[0];
                let imm = parse_imm(&inst_args[1]);
                if (imm as i32) >= -2048 && (imm as i32) <= 2047 {
                    // Use hex format to ensure u32 values survive round-trip through parse_imm
                    expanded.push(("addi".to_string(), vec![rd.clone(), "zero".to_string(), format!("0x{:x}", imm)]));
                } else {
                    let upper = (imm + 0x800) >> 12;
                    let lower = imm & 0xFFF;
                    expanded.push(("lui".to_string(), vec![rd.clone(), format!("0x{:x}", upper)]));
                    expanded.push(("addi".to_string(), vec![rd.clone(), rd.clone(), format!("0x{:x}", lower)]));
                }
            }
            "mv" => {
                expanded.push(("addi".to_string(), vec![inst_args[0].clone(), inst_args[1].clone(), "0".to_string()]));
            }
            "la" => {
                let rd = &inst_args[0];
                let label = &inst_args[1];
                expanded.push(("lui".to_string(), vec![rd.clone(), format!("{}_hi", label)]));
                expanded.push(("addi".to_string(), vec![rd.clone(), rd.clone(), format!("{}_lo", label)]));
            }
            "nop" => {
                expanded.push(("addi".to_string(), vec!["zero".to_string(), "zero".to_string(), "0".to_string()]));
            }
            // Branch pseudo-instructions
            "beqz" => {
                // beqz rs, label -> beq rs, x0, label
                expanded.push(("beq".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            "bnez" => {
                // bnez rs, label -> bne rs, x0, label
                expanded.push(("bne".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            "blez" => {
                // blez rs, label -> bge x0, rs, label
                expanded.push(("bge".to_string(), vec!["zero".to_string(), inst_args[0].clone(), inst_args[1].clone()]));
            }
            "bgtz" => {
                // bgtz rs, label -> blt x0, rs, label
                expanded.push(("blt".to_string(), vec!["zero".to_string(), inst_args[0].clone(), inst_args[1].clone()]));
            }
            "bgez" => {
                // bgez rs, label -> bge rs, x0, label
                expanded.push(("bge".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            "bltz" => {
                // bltz rs, label -> blt rs, x0, label
                expanded.push(("blt".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            // ALU pseudo-instructions
            "seqz" => {
                // seqz rd, rs -> sltiu rd, rs, 1
                expanded.push(("sltiu".to_string(), vec![inst_args[0].clone(), inst_args[1].clone(), "1".to_string()]));
            }
            "snez" => {
                // snez rd, rs -> sltu rd, x0, rs
                expanded.push(("sltu".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            "neg" => {
                // neg rd, rs -> sub rd, x0, rs
                expanded.push(("sub".to_string(), vec![inst_args[0].clone(), "zero".to_string(), inst_args[1].clone()]));
            }
            "not" => {
                // not rd, rs -> xori rd, rs, -1
                expanded.push(("xori".to_string(), vec![inst_args[0].clone(), inst_args[1].clone(), "-1".to_string()]));
            }
            // Jump pseudo-instructions
            "call" => {
                // call label -> jal ra, label
                expanded.push(("jal".to_string(), vec!["ra".to_string(), inst_args[0].clone()]));
            }
            "tail" => {
                // tail label -> jal x0, label
                expanded.push(("jal".to_string(), vec!["zero".to_string(), inst_args[0].clone()]));
            }
            // Data directives
            ".word" => {
                expanded.push((".word".to_string(), vec![inst_args[0].clone()]));
            }
            ".byte" => {
                // Pack bytes into words (little-endian, like .string but for raw data)
                let mut bytes: Vec<u8> = Vec::new();
                for arg in &inst_args {
                    bytes.push(parse_imm(arg) as u8);
                }
                for chunk in bytes.chunks(4) {
                    let mut w = 0u32;
                    for (i, &b) in chunk.iter().enumerate() {
                        w |= (b as u32) << (i * 8);
                    }
                    expanded.push((".word".to_string(), vec![format!("0x{:x}", w)]));
                }
            }
            ".string" => {
                let s = &inst_args[0];
                let mut bytes = process_escapes(s);
                bytes.push(0); // null terminator
                
                for chunk in bytes.chunks(4) {
                    let mut w = 0u32;
                    for (i, &b) in chunk.iter().enumerate() {
                        w |= (b as u32) << (i * 8);
                    }
                    expanded.push((".word".to_string(), vec![format!("0x{:x}", w)]));
                }
            }
            _ => {
                expanded.push((mnemonic.clone(), inst_args.clone()));
            }
        }

        for (m, a) in expanded {
            instructions.push(ParsedLine {
                address: current_addr,
                original: instruction_part.to_string(),
                line_num,
                mnemonic: m,
                args: a,
            });
            current_addr += 4;
        }
    }

    // Pass 2: Encode
    let mut out_file = File::create(output_path)?;
    for inst in &instructions {
        let encoded: u32;
        
        // Resolve imm if it's a label
        let get_imm = |imm_str: &str, is_branch: bool| -> u32 {
            if let Some(&addr) = labels.get(imm_str) {
                if is_branch {
                    (addr as i32 - inst.address as i32) as u32
                } else {
                    addr
                }
            } else if let Some(base_label) = imm_str.strip_suffix("_hi") {
                if let Some(&addr) = labels.get(base_label) {
                    (addr + 0x800) >> 12
                } else {
                    parse_imm(imm_str)
                }
            } else if let Some(base_label) = imm_str.strip_suffix("_lo") {
                if let Some(&addr) = labels.get(base_label) {
                    addr & 0xFFF
                } else {
                    parse_imm(imm_str)
                }
            } else {
                parse_imm(imm_str)
            }
        };

        let ln = inst.line_num;
        let lt = &inst.original;

        match inst.mnemonic.as_str() {
            // R-type
            "add"  => encoded = encode_r(0x33, 0x0, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "sub"  => encoded = encode_r(0x33, 0x0, 0x20, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "sll"  => encoded = encode_r(0x33, 0x1, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "slt"  => encoded = encode_r(0x33, 0x2, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "sltu" => encoded = encode_r(0x33, 0x3, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "xor"  => encoded = encode_r(0x33, 0x4, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "srl"  => encoded = encode_r(0x33, 0x5, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "sra"  => encoded = encode_r(0x33, 0x5, 0x20, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "or"   => encoded = encode_r(0x33, 0x6, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            "and"  => encoded = encode_r(0x33, 0x7, 0x00, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[2], ln, lt)),
            
            // I-type ALU
            "addi"  => encoded = encode_i(0x13, 0x0, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "slli"  => encoded = encode_i(0x13, 0x1, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false) & 0x3F),
            "slti"  => encoded = encode_i(0x13, 0x2, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "sltiu" => encoded = encode_i(0x13, 0x3, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "xori"  => encoded = encode_i(0x13, 0x4, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "srli"  => encoded = encode_i(0x13, 0x5, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false) & 0x3F),
            "srai"  => encoded = encode_i(0x13, 0x5, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), (get_imm(&inst.args[2], false) & 0x3F) | 0x400),
            "ori"   => encoded = encode_i(0x13, 0x6, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "andi"  => encoded = encode_i(0x13, 0x7, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            
            // Loads
            "lb"  => encoded = encode_i(0x03, 0x0, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "lh"  => encoded = encode_i(0x03, 0x1, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "lw"  => encoded = encode_i(0x03, 0x2, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "lbu" => encoded = encode_i(0x03, 0x4, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "lhu" => encoded = encode_i(0x03, 0x5, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),

            // Stores
            "sb" => encoded = encode_s(0x23, 0x0, parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[2], false)),
            "sh" => encoded = encode_s(0x23, 0x1, parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[2], false)),
            "sw" => encoded = encode_s(0x23, 0x2, parse_reg(&inst.args[1], ln, lt), parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[2], false)),

            // Branches
            "beq"  => encoded = encode_b(0x63, 0x0, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),
            "bne"  => encoded = encode_b(0x63, 0x1, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),
            "blt"  => encoded = encode_b(0x63, 0x4, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),
            "bge"  => encoded = encode_b(0x63, 0x5, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),
            "bltu" => encoded = encode_b(0x63, 0x6, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),
            "bgeu" => encoded = encode_b(0x63, 0x7, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], true)),

            // U-type
            "lui"   => encoded = encode_u(0x37, parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[1], false) << 12),
            "auipc" => encoded = encode_u(0x17, parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[1], false) << 12),

            // J-type
            "jal"  => encoded = encode_j(0x6F, parse_reg(&inst.args[0], ln, lt), get_imm(&inst.args[1], true)),
            "jalr" => encoded = encode_i(0x67, 0x0, parse_reg(&inst.args[0], ln, lt), parse_reg(&inst.args[1], ln, lt), get_imm(&inst.args[2], false)),
            "j"    => encoded = encode_j(0x6F, 0, get_imm(&inst.args[0], true)),
            "ret"  => encoded = encode_i(0x67, 0x0, 0, parse_reg("ra", ln, lt), 0),

            // SYSTEM instructions (encode as proper ECALL/EBREAK)
            "ecall"  => encoded = encode_i(0x73, 0x0, 0, 0, 0),
            "ebreak" => encoded = encode_i(0x73, 0x0, 0, 0, 1),
            // FENCE (encode as FENCE with default pred/succ)
            "fence"  => encoded = encode_i(0x0F, 0x0, 0, 0, 0x0FF),
            
            ".word" => encoded = get_imm(&inst.args[0], false),
            
            _ => {
                eprintln!("Error on line {}: Unknown instruction '{}'\n  --> {}", inst.line_num, inst.mnemonic, inst.original);
                std::process::exit(1);
            }
        }
        
        writeln!(out_file, "{:08x}", encoded)?;
    }

    let num_instructions = instructions.len();
    let num_bytes = num_instructions * 4;
    println!("Successfully assembled {} instructions ({} bytes) to {}", num_instructions, num_bytes, output_path);
    Ok(())
}
