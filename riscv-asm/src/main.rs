use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Write};

fn parse_reg(reg: &str) -> u32 {
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
        _ => panic!("Unknown register: {}", reg),
    }
}

fn parse_imm(imm: &str) -> u32 {
    let imm = imm.trim();
    if let Some(stripped) = imm.strip_prefix("0x") {
        u32::from_str_radix(stripped, 16).expect("Invalid hex immediate")
    } else if let Some(stripped) = imm.strip_prefix("-0x") {
        let val = u32::from_str_radix(stripped, 16).expect("Invalid hex immediate");
        (0_u32).wrapping_sub(val)
    } else {
        imm.parse::<i32>().expect(&format!("Invalid immediate: {}", imm)) as u32
    }
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
    for line in reader.lines() {
        let line = line?;
        // Remove comments
        let line = line.split('#').next().unwrap().split("//").next().unwrap().trim();
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

        if instruction_part.is_empty() || instruction_part.starts_with('.') {
            continue;
        }

        // Tokenize instruction
        let mut parts = instruction_part.splitn(2, |c: char| c.is_whitespace());
        let mnemonic = parts.next().unwrap().to_lowercase();
        
        let args_str = parts.next().unwrap_or("");
        let mut args: Vec<String> = Vec::new();
        
        // Handle `lw x1, 4(x2)` format
        if args_str.contains('(') {
            let mut parts_comma = args_str.split(',');
            let rd = parts_comma.next().unwrap().trim();
            args.push(rd.to_string());
            
            let mut offset_reg = parts_comma.next().unwrap().trim().split('(');
            let offset = offset_reg.next().unwrap().trim();
            let mut reg = offset_reg.next().unwrap().trim().to_string();
            reg.pop(); // remove ')'
            args.push(reg);
            args.push(offset.to_string());
        } else {
            args = args_str.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
        }
        
        // Pseudo-instructions expansion
        let mut expanded = Vec::new();
        match mnemonic.as_str() {
            "li" => {
                let rd = &args[0];
                let imm = parse_imm(&args[1]);
                if (imm as i32) >= -2048 && (imm as i32) <= 2047 {
                    expanded.push(("addi".to_string(), vec![rd.clone(), "zero".to_string(), imm.to_string()]));
                } else {
                    let upper = (imm + 0x800) >> 12;
                    let lower = imm & 0xFFF;
                    expanded.push(("lui".to_string(), vec![rd.clone(), upper.to_string()]));
                    expanded.push(("addi".to_string(), vec![rd.clone(), rd.clone(), lower.to_string()]));
                }
            }
            "mv" => {
                expanded.push(("addi".to_string(), vec![args[0].clone(), args[1].clone(), "0".to_string()]));
            }
            "nop" => {
                expanded.push(("addi".to_string(), vec!["zero".to_string(), "zero".to_string(), "0".to_string()]));
            }
            _ => {
                expanded.push((mnemonic.clone(), args.clone()));
            }
        }

        for (m, a) in expanded {
            instructions.push(ParsedLine {
                address: current_addr,
                original: instruction_part.to_string(),
                mnemonic: m,
                args: a,
            });
            current_addr += 4;
        }
    }

    // Pass 2: Encode
    let mut out_file = File::create(output_path)?;
    for inst in instructions {
        let mut encoded: u32 = 0;
        
        // Resolve imm if it's a label
        let get_imm = |imm_str: &str, is_branch: bool| -> u32 {
            if let Some(&addr) = labels.get(imm_str) {
                if is_branch {
                    (addr as i32 - inst.address as i32) as u32
                } else {
                    addr
                }
            } else {
                parse_imm(imm_str)
            }
        };

        match inst.mnemonic.as_str() {
            // R-type
            "add"  => encoded = encode_r(0x33, 0x0, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "sub"  => encoded = encode_r(0x33, 0x0, 0x20, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "sll"  => encoded = encode_r(0x33, 0x1, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "slt"  => encoded = encode_r(0x33, 0x2, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "sltu" => encoded = encode_r(0x33, 0x3, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "xor"  => encoded = encode_r(0x33, 0x4, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "srl"  => encoded = encode_r(0x33, 0x5, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "sra"  => encoded = encode_r(0x33, 0x5, 0x20, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "or"   => encoded = encode_r(0x33, 0x6, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            "and"  => encoded = encode_r(0x33, 0x7, 0x00, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), parse_reg(&inst.args[2])),
            
            // I-type ALU
            "addi"  => encoded = encode_i(0x13, 0x0, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "slli"  => encoded = encode_i(0x13, 0x1, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false) & 0x3F),
            "slti"  => encoded = encode_i(0x13, 0x2, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "sltiu" => encoded = encode_i(0x13, 0x3, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "xori"  => encoded = encode_i(0x13, 0x4, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "srli"  => encoded = encode_i(0x13, 0x5, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false) & 0x3F),
            "srai"  => encoded = encode_i(0x13, 0x5, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), (get_imm(&inst.args[2], false) & 0x3F) | 0x400),
            "ori"   => encoded = encode_i(0x13, 0x6, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "andi"  => encoded = encode_i(0x13, 0x7, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            
            // Loads
            "lb"  => encoded = encode_i(0x03, 0x0, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "lh"  => encoded = encode_i(0x03, 0x1, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "lw"  => encoded = encode_i(0x03, 0x2, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "lbu" => encoded = encode_i(0x03, 0x4, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "lhu" => encoded = encode_i(0x03, 0x5, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),

            // Stores
            "sb" => encoded = encode_s(0x23, 0x0, parse_reg(&inst.args[1]), parse_reg(&inst.args[0]), get_imm(&inst.args[2], false)),
            "sh" => encoded = encode_s(0x23, 0x1, parse_reg(&inst.args[1]), parse_reg(&inst.args[0]), get_imm(&inst.args[2], false)),
            "sw" => encoded = encode_s(0x23, 0x2, parse_reg(&inst.args[1]), parse_reg(&inst.args[0]), get_imm(&inst.args[2], false)),

            // Branches
            "beq"  => encoded = encode_b(0x63, 0x0, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),
            "bne"  => encoded = encode_b(0x63, 0x1, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),
            "blt"  => encoded = encode_b(0x63, 0x4, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),
            "bge"  => encoded = encode_b(0x63, 0x5, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),
            "bltu" => encoded = encode_b(0x63, 0x6, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),
            "bgeu" => encoded = encode_b(0x63, 0x7, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], true)),

            // U-type
            "lui"   => encoded = encode_u(0x37, parse_reg(&inst.args[0]), get_imm(&inst.args[1], false) << 12),
            "auipc" => encoded = encode_u(0x17, parse_reg(&inst.args[0]), get_imm(&inst.args[1], false) << 12),

            // J-type
            "jal"  => encoded = encode_j(0x6F, parse_reg(&inst.args[0]), get_imm(&inst.args[1], true)),
            "jalr" => encoded = encode_i(0x67, 0x0, parse_reg(&inst.args[0]), parse_reg(&inst.args[1]), get_imm(&inst.args[2], false)),
            "j"    => encoded = encode_j(0x6F, 0, get_imm(&inst.args[0], true)),
            "ret"  => encoded = encode_i(0x67, 0x0, 0, parse_reg("ra"), 0),
            
            _ => panic!("Unknown instruction: {}", inst.mnemonic),
        }
        
        writeln!(out_file, "{:08x}", encoded)?;
    }

    println!("Successfully assembled to {}", output_path);
    Ok(())
}
