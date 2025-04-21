##################################
# File: sram_config.py
# Example OpenRAM configuration file
#####################################
# Number of bits per word
word_size = 8
# Number of 8-bit words (some people call this 'depth')
num_words = 4096

write_size = 1
# Port configuration (1-2 ports allowed)
num_rw_ports = 1
num_r_ports = 0
num_w_ports = 0

# The fabrication technology. This must match the PDK name in $OPENRAM_TECH.
tech_name = "freepdk45"

# Process corners, temperature and voltage to characterize
process_corners = ["TT"]
supply_voltages = [1.0]
temperatures = [25]

# Automatically generate name for the macro
def get_mem_name():
    port_string=""
    if num_rw_ports > 0:
        port_string = f"_rw{num_rw_ports if num_rw_ports > 1 else ''}"
    if num_r_ports > 0:
        port_string += f"_r{num_r_ports if num_r_ports > 1 else ''}"
    if num_w_ports > 0:
        port_string += f"_w{num_w_ports if num_w_ports > 1 else ''}"   
    return f'sram_{word_size}_{num_words}{port_string}_{tech_name}'

# Path and name for the output files
output_name = get_mem_name()
output_path = f"output/{output_name}"