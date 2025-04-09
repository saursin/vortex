# Unified function to extract RTL sources, include directories, and defines
proc parse_filelist {filelist_path} {
    set rtl_sources {}
    set incdirs {}
    set rtl_defines {}

    set fp [open $filelist_path r]
    while {[gets $fp line] != -1} {
        set line [string trim $line]
        if {$line eq ""} {
            continue
        }

        if {[string match "+incdir+*" $line]} {
            lappend incdirs [string range $line 8 end]
        } elseif {[string match "+define+*" $line]} {
            lappend rtl_defines [string range $line 8 end]
        } elseif {[string match "*.v" $line] || [string match "*.sv" $line]} {
            lappend rtl_sources $line
        }
    }
    close $fp

    return [list $rtl_sources $incdirs $rtl_defines]
}

# Function to preprocess RTL files to remove comments
proc preprocess_rtl {file_contents} {
    # Remove multi-line comments (block comments)
    set clean_contents [regsub -all {(?s)/\*.*?\*/} $file_contents ""]

    # Remove single-line comments (line comments)
    set clean_contents [regsub -all {\/\/[^\n]*} $clean_contents ""]
    return $clean_contents
}

# Function to check if a file contains a SystemVerilog package definition
proc has_package_definition {file_contents} {
    # Check for package definition
    if {[regexp {(?m)^\s*package\s+\w+} $file_contents]} {
        return 1
    } else {
        return 0
    }
}

# Function to reorder files in a list, 
# placing SystemVerilog package files first
proc reorder_files_package_first {file_list} {
    set package_files {}
    set other_files {}

    foreach file $file_list {
        if {[file exists $file] && ![file isdirectory $file]} {
            set f [open $file r]
            set contents [read $f]
            close $f

            set clean_contents [preprocess_rtl $contents]
            
            # Check if the file contains a package definition
            if {[has_package_definition $clean_contents]} {
                lappend package_files $file
            } else {
                lappend other_files $file
            }
        }
    }
    return [concat $package_files $other_files]
}
