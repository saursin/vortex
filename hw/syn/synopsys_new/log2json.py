################################################################################
# This script parses the ram_inst.log file and converts to JSON format
# 
# To generate ram_inst.log:
#   1. modify the VX_sp_ram and VX_dp_ram to add the following line:
#    initial begin
#        // Print all parameters
#            initial begin
#        $display("{'type': 'VX_dp_ram', 'hier': '%m', 'params': {'DATAW': %0d, 'SIZE': %0d, 'WRENW': %0d, 'OUT_REG': %0d, 'LUTRAM': %0d, 'RDW_MODE': '%s', 'RADDR_REG': %0d, 'RADDR_RESET': %0d, 'RDW_ASSERT': %0d, 'RESET_RAM': %0d, 'INIT_ENABLE': %0d, 'INIT_FILE': '%s', 'INIT_VALUE': %0d}}", 
#                                                                  DATAW,        SIZE,        WRENW,        OUT_REG,        LUTRAM,        RDW_MODE,         RADDR_REG,        RADDR_RESET,        RDW_ASSERT,        RESET_RAM,        INIT_ENABLE,        INIT_FILE,         INIT_VALUE);
#    end
#  2. run the simulation for any program and dump the output to a file
#     make run-rtlsim > $VORTEX_HOME/meminst.log
#  3. run this script to parse the file and generate the JSON file
################################################################################

if __name__ == "__main__":
    import sys
    import json
    import re

    if len(sys.argv) != 3:
        print("Usage: python ram_inst_parse.py <input_file> <output_json_file>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_json_file = sys.argv[2]
    ram_configs = []

    # Read the input file
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    # Parse the lines to extract RAM configurations
    for line in lines:
        if not line.startswith('{"type"'):
            continue
        ram_configs += [line.strip()]

    # Convert to json objects
    json_data = []
    for ram_cfg in ram_configs:
        try:
            json_data.append(json.loads(ram_cfg))
        except json.JSONDecodeError as e:
            print(f"Error decoding JSON: {e}")
            continue

    # Write json
    print(f'Found {len(json_data)} ram configurations')
    print(f'Writing to {output_json_file}')
    with open(output_json_file, 'w') as f:
        json.dump(json_data, f, indent=4)
