import math

chain_vrlg = '''
assign chip_data_out[0:0] = dcr_wr_valid;
assign chip_data_out[12:1] = dcr_wr_addr;
assign chip_data_out[44:13] = dcr_wr_data;
assign chip_data_out[45:45] = mem_req_valid;
assign chip_data_out[46:46] = mem_req_rw;
assign chip_data_out[72:47] = mem_req_addr;
assign chip_data_out[584:73] = mem_req_data;
assign chip_data_out[648:585] = mem_req_byteen;
assign chip_data_out[698:649] = mem_req_tag;
assign chip_data_out[699:699] = mem_rsp_ready;
assign chip_data_out[700:700] = busy;
assign chip_data_out[701:701] = mem_req_ready;
assign chip_data_out[702:702] = mem_rsp_valid;
assign chip_data_out[1214:703] = mem_rsp_data;
assign chip_data_out[1264:1215] = mem_rsp_tag;
'''

def int2hex(value, length):
    hex_str = hex(value)[2:]
    
    # Adjust length to fit the specified length
    if len(hex_str) > length:
        hex_str = hex_str[-length:]
    else:
        hex_str = hex_str.zfill(length)  # Pad with zeros to the left
    
    return hex_str

def bin2hex(value, length):
    hex_str = ''
    
    # get 4 bit chunks starting fro last one, convert to hex and append
    for i in range(len(value), 0, -4):
        chunk = value[max(0, i-4):i]
        hex_digit = hex(int(chunk, 2))[2:]
        hex_str = hex_digit + hex_str

    # Adjust length to fit the specified length
    if len(hex_str) > length:
        hex_str = hex_str[-length:]
    else:
        hex_str = hex_str.zfill(length)
    
    return hex_str

def int2bin(value, length):
    bin_str = bin(value)[2:]  # Convert to binary and remove '0b'

    # Adjust length to fit the specified length
    if len(bin_str) > length:
        bin_str = bin_str[-length:]
    else:
        bin_str = bin_str.zfill(length)  # Pad with zeros to the left

    return bin_str

class Chain:
    def __init__(self, chain_vrlg):
        self.chain = []             # Chain configuration extracted from the VRLG
        self.chain_len = 0          # Length of the chain
        self.chain_sequence = []    # Sequence of operations for the chain

        # Parse the VRLG to extract chain configuration
        for line in chain_vrlg.splitlines():
            line = line.strip()
            if line.startswith('assign'):
                # Extract the assignment
                parts = line.split('=')
                if len(parts) == 2:
                    lhs = parts[0].strip()
                    rhs = parts[1].strip()
                    lhs = lhs.replace('assign chip_data_out', '').strip()
                    lhs = lhs.replace('[', '').replace(']', '').strip()
                    hi = lhs.split(':')[0]
                    lo = lhs.split(':')[1]
                    rhs = rhs.replace(';', '').strip()

                    self.chain += [{
                        'name': rhs,
                        'lo': int(lo),
                        'hi': int(hi),
                        'width': int(hi) - int(lo) + 1, 
                        'data': 0
                    }]
                    self.chain_len = max(self.chain_len, int(hi) + 1)
        
        print(f"Chain length: {self.chain_len}")

    def find_seg(self, name):
        # Get the index of a specific segment in the chain
        for idx, segment in enumerate(self.chain):
            if segment['name'] == name:
                return idx
        return None

    def print_chain(self, print_chain_str=True):
        # Print the chain configuration & data
        print('-' * 150)
        print(f" {'Name':15s} {'Range':15s} {'Width':3s} {'Data'}")
        print('-' * 150)
        for segment in self.chain:
            range_str = f'[{segment["hi"]}:{segment["lo"]}]'
            segment_width = segment['hi'] - segment['lo'] + 1
            hex_length = math.ceil(segment_width / 4)
            print(f" {segment['name']:15s} {range_str:15} {segment_width:<5d} {int2hex(segment['data'], hex_length)}")

        if(print_chain_str):
            # print('-' * 150)
            print("\nChain:")
            chain_str = self.get_chain_string()
            chunk_size = 128
            for i in range(0, len(chain_str), chunk_size):
                chunk = chain_str[i:i + chunk_size]
                print(f" - {chunk}")
        
        print('=' * 150)
        
    
    def set_segment_data(self, name, data):
        # Set the data for a specific segment in the chain
        idx = self.find_seg(name)
        if idx is None:
            raise ValueError(f"Segment '{name}' not found in chain.")

        # Check if the data fits in the segment width
        width = self.chain[idx]['width']
        if data >> width != 0:
            raise ValueError(f"Data {data} exceeds the width of segment '{name}' ({width} bits).")
        
        # Set the data for the segment
        self.chain[idx]['data'] = data
       

    def set_segment_in_chain_binstr(self, chain_val, seg_name, seg_value):
        # Set the value of a specific segment in the binary chain string
        hi = self.chain[self.find_seg(seg_name)]['hi']
        lo = self.chain[self.find_seg(seg_name)]['lo']
        width = self.chain[self.find_seg(seg_name)]['width']

        seg_binstr = int2bin(seg_value, width)

        # Convert verilog hi, lo to python hi, lo
        str_hi = self.chain_len - hi - 1
        str_lo = self.chain_len - lo - 1

        # Set the segment value in the chain string
        chain_val = chain_val[:str_hi] + seg_binstr + chain_val[str_lo + 1:]
        return chain_val


    def get_chain_string(self):
        # Start with a string of zeros
        chain_str = '0' * self.chain_len

        # Iterate through the chain segments and set the values
        for segment in self.chain:
            chain_str = self.set_segment_in_chain_binstr(chain_str, segment['name'], segment['data'])

        return chain_str


    def perform_dcr_write(self, addr, data):
        print(f"[+] DCR write: addr=0x{addr:X}, data=0x{data:X}")
        self.set_segment_data('dcr_wr_valid',1)
        self.set_segment_data('dcr_wr_addr',addr)
        self.set_segment_data('dcr_wr_data',data)
        
        self.print_chain()
        self.chain_sequence.append(self.get_chain_string())

        # Reset the segments after the write
        self.set_segment_data('dcr_wr_valid', 0)
        self.set_segment_data('dcr_wr_addr', 0)
        self.set_segment_data('dcr_wr_data', 0)
    

    def perform_axi_write(self, addr, data, byteen, tag):
        print(f"[+] AXI write: addr=0x{addr:X}, data=0x{data:X}, byteen=0x{byteen:X}, tag=0x{tag:X}")
        self.set_segment_data('mem_req_valid', 1)
        self.set_segment_data('mem_req_rw', 1)
        self.set_segment_data('mem_req_addr', addr)
        self.set_segment_data('mem_req_data', data)
        self.set_segment_data('mem_req_byteen', byteen)
        self.set_segment_data('mem_req_tag', tag)
        self.set_segment_data('mem_rsp_ready', 1)

        self.print_chain()
        self.chain_sequence.append(self.get_chain_string())

        # Reset the segments after the write
        self.set_segment_data('mem_req_valid', 0)
        self.set_segment_data('mem_req_rw', 0)
        self.set_segment_data('mem_req_addr', 0)
        self.set_segment_data('mem_req_data', 0)
        self.set_segment_data('mem_req_byteen', 0)
        self.set_segment_data('mem_req_tag', 0)
        self.set_segment_data('mem_rsp_ready', 0)
        

    def write_chain_sequence(self, filename, fmt='hex'):
        print(f"[+] Writing chain sequence to {filename} ({fmt})")
        # Write the chain sequence to a file in the specified format
        with open(filename, 'w') as f:
            for chain_str in self.chain_sequence:
                if fmt == 'hex':
                    hex_width = math.ceil(self.chain_len / 4)
                    chain_str = bin2hex(chain_str, hex_width)
                    f.write(chain_str + '\n')
                elif fmt == 'bin':
                    f.write(chain_str + '\n')
                else:
                    raise ValueError(f"Unsupported format: {fmt}")


################################################################################        
chain = Chain(chain_vrlg)
chain.print_chain()

# Example usage
chain.perform_dcr_write(0x123, 0xdeadbeef)
chain.perform_axi_write(0x456, 0xdeadbeef, 0xf, 0x1)
chain.perform_axi_write(0x456, 0xdeadbeef, 0xf, 0x2)

chain.write_chain_sequence('scan_sequence.hex')


# Example: Generating the scan chain sequence for vortex initialization
# chain.perform_dcr_write(start address register, start adddress)
# addr = 0x00000000
# with open('memory_init.txt', 'w') as f:
#     line = f.readline()
#     data_hex = int2hex(line, ?)
#     chain.perform_axi_write(addr, data_hex, ?, ?)
# chain.write_chain_sequence('scan_sequence.hex')    