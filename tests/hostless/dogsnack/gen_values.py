#!/usr/bin/env python3
"""
Generate golden reference values for dogsnack test.
Uses random input data and computes expected outputs using Python's math library.
"""

import argparse
import random
import math
import sys

def generate_values(seed, test_size):
    """Generate test inputs and compute expected outputs."""
    random.seed(seed)
    
    # Generate random input data
    src0_i = [random.randint(-100, 100) for _ in range(test_size)]
    src1_i = [random.randint(1, 50) for _ in range(test_size)]  # Avoid div by zero
    src0_f = [random.uniform(0.5, 10.0) for _ in range(test_size)]
    src1_f = [random.uniform(0.5, 5.0) for _ in range(test_size)]  # Avoid div by zero
    
    # Compute expected outputs
    expected_iadd = [src0_i[i] + src1_i[i] for i in range(test_size)]
    expected_imul = [src0_i[i] * src1_i[i] for i in range(test_size)]
    # C division truncates toward zero, not floor division
    expected_idiv = [int(src0_i[i] / src1_i[i]) for i in range(test_size)]
    
    expected_fadd = [src0_f[i] + src1_f[i] for i in range(test_size)]
    expected_fsub = [src0_f[i] - src1_f[i] for i in range(test_size)]
    expected_fmul = [src0_f[i] * src1_f[i] for i in range(test_size)]
    expected_fdiv = [src0_f[i] / src1_f[i] for i in range(test_size)]
    
    expected_fmadd = [src0_f[i] * src1_f[i] + src1_f[i] for i in range(test_size)]
    expected_fmsub = [src0_f[i] * src1_f[i] - src1_f[i] for i in range(test_size)]
    expected_fnmadd = [-src0_f[i] * src1_f[i] - src1_f[i] for i in range(test_size)]
    expected_fnmsub = [-src0_f[i] * src1_f[i] + src1_f[i] for i in range(test_size)]
    
    expected_fsqrt = [math.sqrt(src0_f[i] * src1_f[i]) for i in range(test_size)]
    
    expected_ftoi = [int(src0_f[i] + src1_f[i]) for i in range(test_size)]
    expected_ftou = [int(src0_f[i] + src1_f[i]) for i in range(test_size)]
    expected_itof = [float(src0_i[i] + src1_i[i]) for i in range(test_size)]
    
    expected_fminmax = [min(src0_f[i], src1_f[i]) + max(src0_f[i], src1_f[i]) 
                        for i in range(test_size)]
    
    # Trig: apply sin to all elements
    expected_trig = [math.sin(src0_f[i]) for i in range(test_size)]
    
    # Combined: should cancel to 0
    expected_combined = [0.0 for _ in range(test_size)]
    
    return {
        'src0_i': src0_i,
        'src1_i': src1_i,
        'src0_f': src0_f,
        'src1_f': src1_f,
        'expected_iadd': expected_iadd,
        'expected_imul': expected_imul,
        'expected_idiv': expected_idiv,
        'expected_fadd': expected_fadd,
        'expected_fsub': expected_fsub,
        'expected_fmul': expected_fmul,
        'expected_fdiv': expected_fdiv,
        'expected_fmadd': expected_fmadd,
        'expected_fmsub': expected_fmsub,
        'expected_fnmadd': expected_fnmadd,
        'expected_fnmsub': expected_fnmsub,
        'expected_fsqrt': expected_fsqrt,
        'expected_ftoi': expected_ftoi,
        'expected_ftou': expected_ftou,
        'expected_itof': expected_itof,
        'expected_fminmax': expected_fminmax,
        'expected_trig': expected_trig,
        'expected_combined': expected_combined,
    }

def format_array(name, ctype, values, items_per_line=8, fmt=None):
    """Format an array for C code."""
    if fmt is None:
        fmt = lambda v: f"{v:.8f}f" if isinstance(v, float) else str(v)
    
    lines = [f"static const {ctype} {name}[TEST_SIZE] = {{"]
    
    for i, val in enumerate(values):
        if i % items_per_line == 0:
            lines.append("    ")
        lines[-1] += fmt(val)
        if i < len(values) - 1:
            lines[-1] += ", "
    
    lines[-1] += "};"
    return "\n".join(lines)

def generate_header(values, test_size):
    """Generate C header file content."""
    header = [
        "#pragma once",
        "// Auto-generated golden reference values for dogsnack test",
        "// DO NOT EDIT - regenerate using gen_values.py",
        "",
        f"#define TEST_SIZE {test_size}",
        "",
        "////////////////////////////////////////////////////////////////////////////////",
        "// Input Data",
        "",
        format_array("g_src0_i_init", "int32_t", values['src0_i']), 
        "",
        format_array("g_src1_i_init", "int32_t", values['src1_i']),
        "",
        format_array("g_src0_f_init", "float", values['src0_f'], 4),
        "",
        format_array("g_src1_f_init", "float", values['src1_f'], 4),
        "",
        "////////////////////////////////////////////////////////////////////////////////",
        "// Expected Outputs (computed offline using trusted reference)",
        "",
        format_array("g_expected_iadd", "int32_t", values['expected_iadd']),
        "",
        format_array("g_expected_imul", "int32_t", values['expected_imul']),
        "",
        format_array("g_expected_idiv", "int32_t", values['expected_idiv']),
        "",
        format_array("g_expected_fadd", "float", values['expected_fadd'], 4),
        "",
        format_array("g_expected_fsub", "float", values['expected_fsub'], 4),
        "",
        format_array("g_expected_fmul", "float", values['expected_fmul'], 4),
        "",
        format_array("g_expected_fdiv", "float", values['expected_fdiv'], 4),
        "",
        format_array("g_expected_fmadd", "float", values['expected_fmadd'], 4),
        "",
        format_array("g_expected_fmsub", "float", values['expected_fmsub'], 4),
        "",
        format_array("g_expected_fnmadd", "float", values['expected_fnmadd'], 4),
        "",
        format_array("g_expected_fnmsub", "float", values['expected_fnmsub'], 4),
        "",
        format_array("g_expected_fsqrt", "float", values['expected_fsqrt'], 4),
        "",
        format_array("g_expected_ftoi", "int32_t", values['expected_ftoi']),
        "",
        format_array("g_expected_ftou", "uint32_t", values['expected_ftou']),
        "",
        format_array("g_expected_itof", "float", values['expected_itof'], 4),
        "",
        format_array("g_expected_fminmax", "float", values['expected_fminmax'], 4),
        "",
        format_array("g_expected_trig", "float", values['expected_trig'], 4),
        "",
        format_array("g_expected_combined", "float", values['expected_combined'], 4),
        "",
        f"#define TEST_SIZE {test_size}",
    ]
    
    return "\n".join(header)

def main():
    parser = argparse.ArgumentParser(
        description="Generate golden reference values for dogsnack test"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1234,
        help="Random seed for reproducibility (default: 42)"
    )
    parser.add_argument(
        "--size",
        type=int,
        default=16,
        help="Number of test elements (default: 16)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="dogsnack_values.h",
        help="Output header file (default: dogsnack_values.h)"
    )
    
    args = parser.parse_args()
    
    print(f"Generating test values with seed={args.seed}, size={args.size}")
    print(f"Output: {args.output}")
    
    # Generate values
    values = generate_values(args.seed, args.size)
    
    # Generate header
    header = generate_header(values, args.size)
    
    # Write to file
    with open(args.output, 'w') as f:
        f.write(header)

if __name__ == "__main__":
    main()
