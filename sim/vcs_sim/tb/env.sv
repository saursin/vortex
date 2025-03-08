
`define LOG2DATA_WIDTH $clog2(`VX_MEM_DATA_WIDTH/8);

class environment;
  
  //virtual interface
  virtual vortex_wrapper_if vtx_if;

  string program_file;
  logic [`VX_MEM_DATA_WIDTH-1:0] init_data [0:(1024*1024*8/`VX_MEM_DATA_WIDTH)-1];
  //constructor
  function new(virtual vortex_wrapper_if vtx_vif);
    //get the interface from test
    this.vtx_if = vtx_vif;
  endfunction 

  //run task
  task run;
    $display("Time: %t | ENV run task", $time);
    $display("Slave driver run");
    //dcr_write(`VX_DCR_BASE_STARTUP_ADDR0,`STARTUP_ADDR);
    dcr_write(`VX_DCR_BASE_STARTUP_ADDR0,'h11000);
    $display("DCR write");
    dcr_write(`VX_DCR_BASE_MPM_CLASS, 0);
    if (!$value$plusargs("program=%s", program_file)) begin
      $display("Error: No program file specified!");
      $finish;
    end
    //load_program(program_file, `STARTUP_ADDR);
    load_program(program_file, 'h11000);
    vtx_if.clk_rst_intf.rst <= 1'b1;
    repeat (`RESET_DELAY) @(posedge vtx_if.clk_rst_intf.clk);
    $display("Time: %t | ENV run reset done", $time);
    vtx_if.clk_rst_intf.rst <= 1'b0;
    // fork
    //   begin
            $display("Waiting for busy to get 1");
            wait(vtx_if.busy == 1);
            $display("Waiting for busy to get 0");
            wait(vtx_if.busy == 0);
    //   end
    //   begin
    //        #20000;
    //        $finish;
    //   end
      
    // join_any
  endtask
  
  task load_program(string program_file, int unsigned startup_addr);
    string program_ext;
    
    // Extract file extension
    program_ext = file_extension(program_file);
    
    if (program_ext == "bin") begin
       loadBinImage(program_file, startup_addr);
       //$readmemb(program_file, tb_top.VX_wrapper_top.mem_inst.ram , startup_addr);
    end else if (program_ext == "hex") begin
        loadHexImage(program_file);
    end else begin
        $display("*** error: only *.bin or *.hex images supported.");
        return;
    end
  endtask

  task loadBinImage(string filename, int unsigned start_addr);
    int file, i;
    bit [7:0] data;

    file = $fopen(filename, "rb"); // Open binary file
    if (file == 0) begin
        $display("*** error: Failed to open %s", filename);
        return;
    end

    i = 0;
    while (!$feof(file)) begin
        // Step 1: Calculate the address offset
        int bit_select_offset = ((start_addr + i) % (`VX_MEM_DATA_WIDTH / 8)) * 8;
        int address_offset = ((start_addr + i)) / (`VX_MEM_DATA_WIDTH/ 8);
        //address_offset = address_offset << `LOG2DATA_WIDTH;

        void'($fread(data, file)); // Read one byte 
        $display("Writing to RAM: Addr=%h | Offset=%h | Data=%h", address_offset, bit_select_offset, data);
        // Step 3: Perform the memory write
       
       $root.tb_top.VX_wrapper_top.mem_inst.ram[address_offset][bit_select_offset +: 8] = data; 

            $display("Start address %h address %h data %h", start_addr, start_addr + i, $root.tb_top.VX_wrapper_top.mem_inst.ram[address_offset]);  
        
        i++;
    end
    //tb_top.VX_wrapper_top.mem_inst.initialize_ram(init_data);
    $fclose(file);
    $display("Binary image %s loaded successfully at address %h", filename, start_addr);
  endtask

  task loadHexImage(string filename);
    int file, addr, byteCount, recordType, offset;
    string line;
    bit [7:0] data;
    
    file = $fopen(filename, "r"); // Open hex file
    if (file == 0) begin
        $display("error: %s not found", filename);
        $finish;
    end

    offset = 0;

    while (!$feof(file)) begin
        void'($fgets(line, file)); // Read a line

        // Ignore empty lines and ensure it starts with ':'
        if (line.len() == 0 || line[0] != ":") continue; 

        // Extract byte count, address, record type
        void'($sscanf(line.substr(1,2), "%h", byteCount));
        void'($sscanf(line.substr(3,6), "%h", addr));
        void'($sscanf(line.substr(7,8), "%h", recordType));

        // Process record types
        case (recordType)
        8'h00: begin // Data record
            for (int i = 0; i < byteCount; i++) begin
            void'($sscanf(line.substr(9 + (i * 2), 10 + (i * 2)), "%h", data));
           // axi_slave_driver.mem_handle[addr + offset + i] = data;
            end
        end
        8'h02: begin // Extended segment address record
            void'($sscanf(line.substr(9,12), "%h", offset));
            offset = offset << 4;
        end
        8'h04: begin // Extended linear address record
            void'($sscanf(line.substr(9,12), "%h", offset));
            offset = offset << 16;
        end
        endcase
    end

    $fclose(file);
    $display("Hex image %s loaded successfully into memory", filename);
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
        $display("Inside DCR write");
        vtx_if.dcr_intf.dcr_wr_valid <= 1'b1;
        vtx_if.dcr_intf.dcr_wr_addr <= addr;
        vtx_if.dcr_intf.dcr_wr_data <= value;
        $display("Waiting for clk");
        @(posedge vtx_if.clk_rst_intf.clk);
        vtx_if.dcr_intf.dcr_wr_valid <= 1'b0;        
  endtask

endclass