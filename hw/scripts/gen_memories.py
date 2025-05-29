import json, argparse, os, subprocess, pprint

def gen_mem_name(num_r_ports, num_w_ports, num_rw_ports, word_size, num_words):
    """Generate a unique memory module name based on ports, width, and depth."""
    port_string = ""
    # rw comes first, then r, then w
    if num_rw_ports > 0:
        port_string = f"_rw{num_rw_ports if num_rw_ports > 1 else ''}"
    if num_r_ports > 0:
        port_string += f"_r{num_r_ports if num_r_ports > 1 else ''}"
    if num_w_ports > 0:
        port_string += f"_w{num_w_ports if num_w_ports > 1 else ''}"
    return f"sram_{word_size}_{num_words}{port_string}"


def gen_mem(json_obj, out_dir):
    """Generate OpenRAM config and wrapper for the given memory spec."""
    params = json_obj.get("params", {})

    # Extract parameters
    word_size = int(params.get("DATAW", 0))
    depth     = int(params.get("SIZE", 0))

    # Check feasibility and adapt
    # 1. Depth should be atleast 16
    if depth < 16:
        print(f"[WARN] Depth {depth} is less than 16, setting to 16")
        depth = 16
    
    # Determine port counts from type
    mem_type = json_obj.get("type", "VX_dp_ram")
    if mem_type == "VX_dp_ram":
        num_rw_ports, num_r_ports, num_w_ports = 0, 1, 1
    elif mem_type == "VX_sp_ram":
        num_rw_ports, num_r_ports, num_w_ports = 1, 0, 0
    else:
        # default to DP
        num_rw_ports, num_r_ports, num_w_ports = 0, 1, 1
        print(f"[WARN] Unknown mem type '{mem_type}', assuming DP")

    mem_name = gen_mem_name(num_r_ports, num_w_ports, num_rw_ports, word_size, depth)

    if num_rw_ports + num_r_ports + num_w_ports > 2:
        print(f"[ERROR] Number of ports exceeds 2: {num_rw_ports}, {num_r_ports}, {num_w_ports}")
        return

    # Generate OpenRAM config
    cfg_path = f"{out_dir}/{mem_name}/config_{mem_name}.py"
    output_path = f"{out_dir}/{mem_name}/output"

    os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
    with open(cfg_path, "w") as f:
        f.write(f"""\
# Auto-generated OpenRAM config for {mem_name}
word_size    = {word_size}      # Number of bits per word
num_words    = {depth}          # Number of words (some people call this 'depth')

# Port configuration (1-2 ports allowed)
num_rw_ports = {num_rw_ports}
num_r_ports  = {num_r_ports}
num_w_ports  = {num_w_ports}

# The fabrication technology. This must match the PDK name in $OPENRAM_TECH.
tech_name = "freepdk45"

# Process corners, temperature and voltage to characterize
process_corners = ["TT"]
supply_voltages = [1.0]
temperatures = [25]

# Path and name for the output files
output_name = "{mem_name}"
output_path = "{output_path}"
""")
    print(f"[INFO] Generated OpenRAM config: {mem_name} ({cfg_path})")

    # Call openram to generate the memory
    if not os.getenv("OPENRAM_HOME"):
        print("[ERROR] OPENRAM_HOME environment variable not set")
        exit(1)

    cmd = [f"{os.getenv('OPENRAM_HOME')}/../sram_compiler.py", cfg_path]
    ret = subprocess.run(cmd)
    if ret.returncode != 0:
        print(f"[ERROR] OpenRAM failed for {mem_name}")
        exit(1)
    print(f"[INFO] OpenRAM generated memory: {mem_name}")


def parse_json(json_file, out_dir):
    """Parse the JSON file and generate memories."""
    with open(json_file, "r") as f:
        data = json.load(f)

    mems = []

    for entry in data:
        params = entry.get("params", {})
        word_size = int(params.get("DATAW", 0))
        depth     = int(params.get("SIZE", 0))
       
        # Determine port counts from type
        num_rw_ports, num_r_ports, num_w_ports = 0, 1, 1            # default to DP
        mem_type = entry.get("type", "VX_dp_ram")
        if mem_type == "VX_dp_ram":
            num_rw_ports, num_r_ports, num_w_ports = 0, 1, 1
        elif mem_type == "VX_sp_ram":
            num_rw_ports, num_r_ports, num_w_ports = 1, 0, 0
        else:           
            print(f"[WARN] Unknown mem type '{mem_type}', assuming DP")

        # Generate memory name
        mem_name = gen_mem_name(num_r_ports, num_w_ports, num_rw_ports, word_size, depth)

        mems+= [{
            "name": mem_name,
            "type": mem_type,
            "DATAW": word_size,
            "SIZE": depth,
            "rw_ports": num_rw_ports,
            "r_ports": num_r_ports,
            "w_ports": num_w_ports,
            # "metadata": entry
        }]

    return mems


    
def main():
    parser = argparse.ArgumentParser(description="Generate OpenRAM macros from JSON.")
    parser.add_argument("json", help="Input JSON file with memory specs")
    parser.add_argument("--out-dir", default="out", help="Output directory")
    args = parser.parse_args()
    
    mems = parse_json(args.json, args.out_dir)
    for mem in mems:
        pass # FIXME
        

if __name__ == "__main__":
    main()
