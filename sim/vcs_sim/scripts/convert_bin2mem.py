import sys

def bin_to_mem(bin_file, mem_file):
    try:
        with open(bin_file, "rb") as bf, open(mem_file, "w") as mf:
            data = bf.read()
            for i in range(0, len(data), 4):  # Assuming 32-bit words
                word = data[i:i+4]
                hex_word = ''.join(f"{byte:02X}" for byte in reversed(word))
                mf.write(hex_word + "\n")
        print(f"Conversion successful! {mem_file} created.")
    except FileNotFoundError:
        print("Error: Input file not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python bin_to_mem.py <input.bin> <output.mem>")
    else:
        bin_to_mem(sys.argv[1], sys.argv[2])
