
`define LOG2DATA_WIDTH $clog2(`VX_MEM_DATA_WIDTH/8);

class environment;
  
  //virtual interface
  virtual vortex_wrapper_if vtx_if;
  logic [31:0] exitcode;
  string program_file;
  logic [`VX_MEM_DATA_WIDTH-1:0] init_data [0:(1024*1024*8/`VX_MEM_DATA_WIDTH)-1];

  //constructor
  function new(virtual vortex_wrapper_if vtx_vif);
    //get the interface from test
    this.vtx_if = vtx_vif;
  endfunction 

  //run task
  task run;
     
    $display("Time: %t | Start of simulation", $time);

    // Initially make the exit code as 1, to make sure we don't read the default value of 0 as success
    write_mem(`IO_MPM_ADDR + 8, 'h1);  
    exitcode = read_mem(`IO_MPM_ADDR + 8); 
    $display("Time: %t | Exit code value %d", $time, exitcode);
    
    // Drive default 0's on dcr interface
    vtx_if.dcr_intf.dcr_wr_valid <= 1'b0;
    vtx_if.dcr_intf.dcr_wr_addr <= 'h0;
    vtx_if.dcr_intf.dcr_wr_data <= 'h0;

    // FIXME: initialize the scan interface
    
    // DCR write to set the start address
    @(posedge vtx_if.clk_rst_intf.clk);
    dcr_write(`VX_DCR_BASE_STARTUP_ADDR0,`STARTUP_ADDR);
    dcr_write(`VX_DCR_BASE_MPM_CLASS, 0);
    $display("Time: %t | Finished DCR writes", $time);

    // Check if a program file is specified or not
    if (!$value$plusargs("program=%s", program_file)) begin
      $fatal("Error: No program file specified!");
    end
    
    //load program at start address using backdoor access
    load_program(program_file, `STARTUP_ADDR);

    // FIXME: drive the scan chain before reset
    // Either use the scan chain or the memory initialization to load the program
    // perform_scan_sequence(scan_sequence.hex);   // See this task below
    
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
  
  task load_program(string program_file, int unsigned startup_addr);
    string program_ext;
    
    // Extract file extension
    program_ext = file_extension(program_file);
    
    if (program_ext == "mem") begin
        loadmemImage(program_file, startup_addr); 
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

      if (addr <= 'h17F) begin
          bit_select_offset = (addr % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = addr / (`VX_MEM_DATA_WIDTH / 8);
          return tb_top.VX_wrapper_top.mem_inst.ram1[address_offset][bit_select_offset +: 32];
      end else if (addr >= 'h80000000 && addr < ('h80000000 + 1024*1024)) begin
          bit_select_offset = ((addr - 'h80000000) % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = (addr - 'h80000000) / (`VX_MEM_DATA_WIDTH / 8);
          return tb_top.VX_wrapper_top.mem_inst.ram2[address_offset][bit_select_offset +: 32];
      end else if (addr >= 'hFFFD1FC0 && addr <= 'hFFFFFFFF) begin
          bit_select_offset = ((addr - 'hFFFD1FC0) % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = (addr - 'hFFFD1FC0) / (`VX_MEM_DATA_WIDTH / 8);
          return tb_top.VX_wrapper_top.mem_inst.ram2[address_offset][bit_select_offset +: 32];
      end else begin
          $fatal("Error: Address %h is out of range!", addr);
      end
  endfunction

  function void write_mem(int unsigned addr, logic [31:0] data);
      int bit_select_offset;
      int address_offset;

      if (addr <= 'h17F) begin
          bit_select_offset = (addr % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = addr / (`VX_MEM_DATA_WIDTH / 8);
          tb_top.VX_wrapper_top.mem_inst.ram1[address_offset][bit_select_offset +: 32] = data;
      end else if (addr >= 'h80000000 && addr < ('h80000000 + 1024*1024)) begin
          bit_select_offset = ((addr - 'h80000000) % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = (addr - 'h80000000) / (`VX_MEM_DATA_WIDTH / 8);
          tb_top.VX_wrapper_top.mem_inst.ram2[address_offset][bit_select_offset +: 32] = data;
      end else if (addr >= 'hFFFD1FC0 && addr <= 'hFFFFFFFF) begin
          bit_select_offset = ((addr - 'hFFFD1FC0) % (`VX_MEM_DATA_WIDTH / 8)) * 8;
          address_offset = (addr - 'hFFFD1FC0) / (`VX_MEM_DATA_WIDTH / 8);
          tb_top.VX_wrapper_top.mem_inst.ram3[address_offset][bit_select_offset +: 32] = data;
      end else begin
          $fatal("Error: Address %h is out of range!", addr);
      end
  endfunction

    // FIXME:  check if this is correct
    task perform_scan_sequence(string filename);
        int file, i;
        file = $fopen(filename, "rb"); // Open mem file
        if (file == 0) begin
            $fatal("*** error: Failed to open %s", filename);
            return;
        end

        while (!$feof(file)) begin
            void'($fscanf(file, "%h\n", scanReg));
            scan_inputs();
            report_scan_results();
        end
        $fclose(file);
        $display("Time: %t | Scan complete", $time);
    endtask

endclass