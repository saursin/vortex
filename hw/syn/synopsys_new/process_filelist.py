import sys, re

# Function to remove comments from RTL file content
def preprocess_rtl(file_contents):
    # Remove /* ... */ block comments (non-greedy with DOTALL)
    clean_contents = re.sub(r'/\*.*?\*/', '', file_contents, flags=re.DOTALL)
    # Remove // ... single-line comments
    clean_contents = re.sub(r'//[^\n]*', '', clean_contents)
    return clean_contents

# Function to check if RTL content has a SystemVerilog package
def has_package_definition(file_contents):
    return bool(re.search(r'^\s*package\s+\w+', file_contents, flags=re.MULTILINE))

def extract_package_files(files):
    # Sort files to have package files first
    package_files = []
    other_files = []
    for file in files:
        with open(file, 'r') as f:
            contents = f.read()

        clean_contents = preprocess_rtl(contents)
        if has_package_definition(clean_contents):
            package_files.append(file)
        else:
            other_files.append(file)
    
    return package_files, other_files


def process_filelist(input_file, output_file, tool='verilator'):
    defines = []
    includes = []
    files = []

    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('+define+'):
                defines.append(line[8:])
            elif line.startswith('+incdir+'):
                includes.append(line[8:])
            elif line.endswith('.v') or line.endswith('.sv'):
                files.append(line)
            else:
                raise ValueError(f"Unknown line format: {line}")
    
    # Extract package files and other files
    package_files, other_files = extract_package_files(files)
    files = package_files + other_files
    print(f'Found {len(defines)} defines')
    print(f'Found {len(includes)} includes')
    print(f'Found {len(files)} files (package files: {len(package_files)}, other files: {len(other_files)})')
   
    # Write the output to the specified file
    print(f'Writing to {output_file}')
    with open(output_file, 'w') as f:
        for define in defines:
            f.write(f'+define+{define}\n')
        for include in includes:
            f.write(f'+incdir+{include}\n')
        for file in package_files + other_files:
            f.write(file + '\n')


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python process_filelist.py <input_file> <output_file>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    process_filelist(input_file, output_file)