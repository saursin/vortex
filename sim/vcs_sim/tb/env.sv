
`define LOG2DATA_WIDTH $clog2(`VX_MEM_DATA_WIDTH/8);

class environment;
  
    //virtual interface
    virtual vortex_wrapper_if vtx_if;
    logic [31:0] exitcode;
    string program_file;
    logic [`VX_MEM_DATA_WIDTH-1:0] init_data [0:(1024*1024*8/`VX_MEM_DATA_WIDTH)-1];
    int region1_size = 'h180 / (`VX_MEM_DATA_WIDTH / 8);
    int region3_size = ('h100000000 - 'hFFFD1FC0)/(`VX_MEM_DATA_WIDTH/8);
    int region3_start = 'hFFFD1FC0 / (`VX_MEM_DATA_WIDTH / 8);
    int startup_addr = `STARTUP_ADDR / (`VX_MEM_DATA_WIDTH / 8);
    int mem_depth = 1024*1024/(`VX_MEM_DATA_WIDTH/8);
    int region2_end = startup_addr + (mem_depth - region1_size - region3_size) - 1;

    //constructor
    function new(virtual vortex_wrapper_if vtx_vif);
        //get the interface from test
        this.vtx_if = vtx_vif;
    endfunction 

    //run task
    task run;
        string cmd = "";
        int return_code;
        $display("Time: %t | Start of simulation", $time);

        // Initially make the exit code as 1, to make sure we don't read the default value of 0 as success
        write_mem(`IO_MPM_ADDR + 8, 'h1);  
        exitcode = read_mem(`IO_MPM_ADDR + 8); 
        $display("Time: %t | Exit code value %d", $time, exitcode);
        
        // Initialize scan chain input
        vtx_if.scan_intf.scan_in <= 1'b0;
        vtx_if.scan_intf.update  <= 1'b0;
        vtx_if.scan_intf.capture <= 1'b0;
        vtx_if.scan_intf.phi     <= 1'b0;
        vtx_if.scan_intf.phi_bar <= 1'b0; 

        // Check if a program file is specified or not
        if (!$value$plusargs("program=%s", program_file)) begin
            $fatal("Error: No program file specified!");
        end
        
        //load the program using scan chain
        cmd = $sformatf("python3 ../gen_scan_seq.py %s  >> simulation.log", program_file);
        $display("Time: %t | File to be loaded %s", $time, program_file);
        // Python script to generate scanchain input data
        return_code = $system(cmd);
        if (return_code != 0) begin
            $fatal("Error: Execution of the command '%s' failed with return code %0d", cmd, return_code);
        end

        perform_scan_sequence("scan_sequence.hex");   // See this task below

        // Driving reset
        vtx_if.clk_rst_intf.rst <= 1'b1;
        repeat (`RESET_DELAY) @(posedge vtx_if.clk_rst_intf.clk);
        $display("Time: %t | Vortex reset done", $time);
        vtx_if.clk_rst_intf.rst <= 1'b0;

        // Wait for vortex busy to be driven as 1 and then wait for it to get 0.
        fork
        begin
            $display("Time: %t | Waiting for busy to get 1", $time);
            wait(vtx_if.busy == 1);
            $display("Time: %t | Waiting for busy to get 0", $time);
            wait(vtx_if.busy == 0);
            $display("Time: %t | Completed waiting for busy 0", $time);
        end
        begin
          #20000000;
            $finish;
        end
        join_any

        // Read exit code from memory 
        exitcode = read_mem(`IO_MPM_ADDR + 8);  
        if(exitcode == 0) begin
            $display("Time: %t | Program executed Successfully", $time);
        end else begin
            $error("Time: %t | Program has a failure exitcode %d",$time,exitcode);
        end
    endtask
    
    task load_program(string program_file, int unsigned program_startup_addr);
        string program_ext;
        
        // Extract file extension
        program_ext = file_extension(program_file);
        
        if (program_ext == "mem") begin
            loadmemImage(program_file, program_startup_addr); 
        end else begin
            $fatal("*** error: only *.mem images supported.");
            return;
        end
    endtask

    task loadmemImage(string filename, int unsigned start_addr);
        int file, i;
        bit [31:0] data;

        file = $fopen(filename, "rb"); // Open mem file
        if (file == 0) begin
            $fatal("*** error: Failed to open %s", filename);
            return;
        end

        i = 0;
        while (!$feof(file)) begin

            void'($fscanf(file, "%h\n", data));  
            write_mem(start_addr + i, data);
            i = i+4;

        end
        $fclose(file);
        $display("Time: %t | Mem image %s loaded successfully at address 0x%h", $time, filename, start_addr);
    endtask

    function string file_extension(string filename);
        int dot_pos;
        
        // Find the last occurrence of '.' in the filename
        dot_pos = filename.len() - 1;
        while (dot_pos >= 0 && filename[dot_pos] != ".")
            dot_pos--;

        if (dot_pos > 0)
            return filename.substr(dot_pos + 1, filename.len() - 1);
        else
            return "";
    endfunction

    task dcr_write(input logic [`VX_DCR_ADDR_WIDTH-1:0] addr, input logic [`VX_DCR_DATA_WIDTH-1:0] value);
            @(posedge vtx_if.clk_rst_intf.clk);
            vtx_if.dcr_intf.dcr_wr_valid <= 1'b1;
            vtx_if.dcr_intf.dcr_wr_addr <= addr;
            vtx_if.dcr_intf.dcr_wr_data <= value;
            @(posedge vtx_if.clk_rst_intf.clk);
            vtx_if.dcr_intf.dcr_wr_valid <= 1'b0;        
    endtask

    function logic [31:0] read_mem(int unsigned addr);
        int bit_select_offset;
        int address_offset;
        int translated_addr;
        
        int word_addr = addr / (`VX_MEM_DATA_WIDTH / 8);

        if (word_addr < region1_size) begin  // Region 1
            translated_addr = word_addr;
        end else if (word_addr >= region3_start) begin  // Region 3
            translated_addr = word_addr - region3_start + mem_depth - region3_size;
        end else if (word_addr >= startup_addr && word_addr <= region2_end) begin  // Region 2
            translated_addr = word_addr - startup_addr + region1_size;
        end else begin
            $display("ERROR: Address 0x%h is out of range!", addr);
            $fatal("Error: Address %h is out of range!", addr);
        end

        bit_select_offset = (addr % (`VX_MEM_DATA_WIDTH / 8)) * 8;
        
        return tb_top.VX_wrapper_top.mem_inst.ram[translated_addr][bit_select_offset +: 32];
    endfunction

    function void write_mem(int unsigned addr, logic [31:0] data);
        int bit_select_offset;
        int address_offset;
        int translated_addr;

        int word_addr = addr / (`VX_MEM_DATA_WIDTH / 8);

        if (word_addr < region1_size) begin  // Region 1
            translated_addr = word_addr;
        end else if (word_addr >= region3_start) begin  // Region 3
            translated_addr = word_addr - region3_start + mem_depth - region3_size;
        end else if (word_addr >= startup_addr && word_addr <= region2_end) begin  // Region 2
            translated_addr = word_addr - startup_addr + region1_size;
        end else begin
            $display("ERROR: Address 0x%h is out of range!", addr);
            $fatal("Error: Address %h is out of range!", addr);
        end

        bit_select_offset = (addr % (`VX_MEM_DATA_WIDTH / 8)) * 8;
        tb_top.VX_wrapper_top.mem_inst.ram[translated_addr][bit_select_offset +: 32] = data;
    endfunction

    task perform_scan_sequence(string filename);
         int file, i;
         logic [1264:0] scanReg;
         
         file = $fopen(filename, "r"); // Open mem file
         if (file == 0) begin
             $fatal("*** error: Failed to open %s", filename);
             return;
         end
 
         while (!$feof(file)) begin
             void'($fscanf(file, "%h\n", scanReg));
             scan_inputs(scanReg);
         end
         $fclose(file);
         $display("Time: %t | Scan complete", $time);
     endtask



    task scan_inputs(logic [1264:0] scanReg);
        for (int i = 0; i < 1265; i = i + 1) begin
            #1  vtx_if.scan_intf.scan_in = scanReg[i];
            #1  vtx_if.scan_intf.phi = 1'b1;
            #10 vtx_if.scan_intf.phi = 1'b0;
            #1  vtx_if.scan_intf.phi_bar = 1'b1;
            #10 vtx_if.scan_intf.phi_bar = 1'b0;
        end

        #1   vtx_if.scan_intf.update = 1'b1;
        #100 vtx_if.scan_intf.update = 1'b0;
    endtask
endclass