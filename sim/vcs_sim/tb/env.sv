
`define LOG2DATA_WIDTH $clog2(`VX_MEM_DATA_WIDTH/8);
import uvm_pkg::*;
`include "uvm_macros.svh"
class environment;
  
    //virtual interface
    virtual vortex_wrapper_if vtx_if;
    logic [31:0] exitcode;
    string program_file;
    int region1_size = 'h500 / (`VX_MEM_DATA_WIDTH / 8);
    int region3_size = ('h100000000 - 'hFFEF0000)/(`VX_MEM_DATA_WIDTH/8);
    int region3_start = 'hFFEF0000 / (`VX_MEM_DATA_WIDTH / 8);
    int startup_addr = `STARTUP_ADDR / (`VX_MEM_DATA_WIDTH / 8);
    int mem_depth = 2*1024*1024/(`VX_MEM_DATA_WIDTH/8);
    int region2_end = startup_addr + (mem_depth - region1_size - region3_size) - 1;

    //constructor
    function new(virtual vortex_wrapper_if vtx_vif);
        //get the interface from test
        this.vtx_if = vtx_vif;
    endfunction 

    //run task
    task run;
        handle_all_mem_requests();
        $display("Time: %t | Start of simulation", $time);

        // Initially make the exit code as 1, to make sure we don't read the default value of 0 as success
        write_mem(`IO_MPM_ADDR + 8, 'h1);  
        exitcode = read_mem(`IO_MPM_ADDR + 8); 
        $display("Time: %t | Exit code value %d", $time, exitcode);
        
        // Drive default 0's on dcr interface
        vtx_if.dcr_intf.dcr_wr_valid <= 1'b0;
        vtx_if.dcr_intf.dcr_wr_addr <= 'h0;
        vtx_if.dcr_intf.dcr_wr_data <= 'h0;
        
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
            #2000000;
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

    // Testbench Memory Access Functions using UVM HDL string access
    function automatic logic [31:0] read_mem(
        int unsigned addr
    );
        int translated_addr, bank, sram_addr, byte_offset;
        logic [7:0] bytes[4];
        logic [31:0] rdata = '0;
        string hdl_path;
        
        // Calculate word address and translation
        int word_addr = addr / (`VX_MEM_DATA_WIDTH/8);
        
        // Original address translation logic
        if (word_addr < region1_size) begin
            translated_addr = word_addr;
        end else if (word_addr >= region3_start) begin
            translated_addr = word_addr - region3_start + mem_depth - region3_size;
        end else if (word_addr >= startup_addr && word_addr <= region2_end) begin
            translated_addr = word_addr - startup_addr + region1_size;
        end else begin
            `uvm_fatal("MEM_ACCESS", $sformatf("Address 0x%0h out of bounds!", addr))
            return 0;
        end

        // Bank selection (upper 2 bits)
        bank = translated_addr[13:12];
        
        // SRAM address within bank (12-bit)
        sram_addr = translated_addr[11:0];
        
        // Byte offset within 512-bit word
        byte_offset = addr % (`VX_MEM_DATA_WIDTH/8);

        // Boundary check
        if ((byte_offset + 3) >= 64) begin
            `uvm_fatal("MEM_ACCESS", 
                    $sformatf("32-bit access crosses boundary at 0x%0h", addr))
            return 0;
        end

        // Read 4 consecutive bytes using UVM HDL access
        foreach (bytes[i]) begin
            int byte_lane = byte_offset + i;
            int sram_idx = (bank * 64) + byte_lane;
            hdl_path = $sformatf("tb_top.VX_wrapper_top.mem_inst.memory_core.sram_array[%0d].mem[%0d]", sram_idx, sram_addr);
            
            if (!uvm_hdl_read(hdl_path, bytes[i])) begin
                `uvm_fatal("MEM_ACCESS", $sformatf("Failed to read %s", hdl_path))
                return 0;
            end
        end

        return {bytes[3], bytes[2], bytes[1], bytes[0]};
    endfunction

    function automatic void write_mem(
        int unsigned addr, 
        logic [31:0] data
    );
        int translated_addr, bank, sram_addr, byte_offset;
        logic [7:0] byte_data,test_byte_data;
        string hdl_path;
        
        // Same address translation as read_mem
        int word_addr = addr / (`VX_MEM_DATA_WIDTH/8);
        $display("Time: %t | write_mem addr %h data %h", $time, addr, data);
        if (word_addr < region1_size) begin
            translated_addr = word_addr;
        end else if (word_addr >= region3_start) begin
            translated_addr = word_addr - region3_start + mem_depth - region3_size;
        end else if (word_addr >= startup_addr && word_addr <= region2_end) begin
            translated_addr = word_addr - startup_addr + region1_size;
        end else begin
            `uvm_fatal("MEM_ACCESS", $sformatf("Address 0x%0h out of bounds!", addr))
            return;
        end

        bank = translated_addr[13:12];
        sram_addr = translated_addr[11:0];
        byte_offset = addr % (`VX_MEM_DATA_WIDTH/8);

        if ((byte_offset + 3) >= 64) begin
            `uvm_fatal("MEM_ACCESS", 
                    $sformatf("32-bit write crosses boundary at 0x%0h", addr))
            return;
        end

        // Write 4 consecutive bytes using UVM HDL access
        for (int i = 0; i < 4; i++) begin
            int byte_lane = byte_offset + i;
            int sram_idx = (bank * 64) + byte_lane;
            hdl_path = $sformatf("tb_top.VX_wrapper_top.mem_inst.memory_core.sram_array[%0d].mem[%0d]", sram_idx, sram_addr);
            byte_data = (data >> (i*8)) & 8'hFF;
            
            if (!uvm_hdl_deposit(hdl_path, byte_data)) begin
                `uvm_fatal("MEM_ACCESS", $sformatf("Failed to write %s", hdl_path))
                return;
            end
            if (!uvm_hdl_read(hdl_path, test_byte_data)) begin
                `uvm_fatal("MEM_ACCESS", $sformatf("Failed to read %s", hdl_path))
            end
            $display("Time: %t | write_mem addr %h read data %h write data %h", $time, addr, test_byte_data,byte_data);

        end
        
    endfunction

    task automatic handle_all_mem_requests();
        for (int b = 0; b < `NUM_CORES; b++) begin
            automatic int core_idx = b; 
            fork 
                begin 
                    handle_mem_request_bank(core_idx);
                end
            join_none
        end
    endtask

    task automatic handle_mem_request_bank(input int c);
        logic [63:0] byte_addr;
        int cout_file;
        string file_name;
        $sformat(file_name, "console_output_%0d.txt", c);
        cout_file = $fopen(file_name, "a");
        if (cout_file == 0) begin
            $fatal("Failed to open output file!");
        end

        forever begin
            wait (tb_top.VX_wrapper_top.mem_req_valid[0] && tb_top.VX_wrapper_top.mem_req_ready[0] && tb_top.VX_wrapper_top.mem_req_rw[0]);

            byte_addr = tb_top.VX_wrapper_top.mem_req_addr[0] * `PLATFORM_MEMORY_DATA_SIZE;
            if (tb_top.VX_wrapper_top.mem_req_byteen[0][(`NUM_WARPS*`NUM_THREADS*c)%64]) begin
                if (byte_addr >= `IO_COUT_ADDR && byte_addr < (`IO_COUT_ADDR + `IO_COUT_SIZE)) begin
                    // Console output to file
                    $fwrite(cout_file, "%s",tb_top.VX_wrapper_top.mem_req_data[0][((`NUM_WARPS*`NUM_THREADS*c)%64)*8 +: 8]);
                    if (tb_top.VX_wrapper_top.mem_req_data[0][(`NUM_WARPS*`NUM_THREADS*c)%64] == 8'd10) begin
                        $fwrite(cout_file, "\n");
                    end
                end
            end
            @(posedge vtx_if.clk_rst_intf.clk);
        end
    endtask

endclass