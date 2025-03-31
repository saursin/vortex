task scan_init();

    scan_in = 1'b0;
    update = 1'b0;
    capture = 1'b0;
    phi = 1'b0;
    phi_bar = 1'b0;

endtask

logic [1264:0] scanReg;
task scan_inputs();

    scanReg={50'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx, 512'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx, 1'bx, 1'bx, 1'bx, mem_rsp_ready, mem_req_tag, mem_req_byteen, mem_req_data, mem_req_addr, mem_req_rw, mem_req_valid, dcr_wr_data, dcr_wr_addr, dcr_wr_valid};

    for (int i = 0; i < 1265; i = i + 1) begin
        #1 scan_in = scanReg[i];
        #1 phi = 1'b1;
        #10 phi = 1'b0;
        #1 phi_bar = 1'b1;
        #10 phi_bar = 1'b0;
    end
    #1 update = 1'b1;
    #100 update = 1'b0;

endtask

logic [1264:0] scanOutReg;
task scan_outputs();

    capture = 1'b1; //Capture the signals
    #1 phi_bar = 1'b1; //Clock phi_bar to get the captured signals into the chain.
    #10 phi_bar = 1'b0;
    scanOutReg[0] = scan_out;
    #10 capture = 1'b0; //Return to regular scan mode

    for (int i = 1; i < 1265; i = i + 1) begin
        #1 phi = 1'b1;
        #10 phi = 1'b0;
        #1 phi_bar = 1'b1;
        #10 phi_bar = 1'b0;
        #1 scanOutReg[i] = scan_out;
    end

endtask

task get_scan_results();

	busy = scanOutReg[700:700];
	mem_req_ready = scanOutReg[701:701];
	mem_rsp_valid = scanOutReg[702:702];
	mem_rsp_data = scanOutReg[1214:703];
	mem_rsp_tag = scanOutReg[1264:1215];

endtask

function int report_scan_results(string file_path, mode, test_case_name="none");

    integer file;
    file = $fopen(file_path, mode);
    if (file === 0) begin
        $display("Failed to open file name : ", file_path);
        $finish;
    end
    else begin
        $display("Open file, name: ", file_path);
    end

	if (test_case_name !== "none") $fwrite(file, "Test case is %s\n", test_case_name);
    else $fwrite(file, "Time cursor is %d\n", $time);

	$fwrite(file, "input %s = %b\n", "dcr_wr_valid", scanOutReg[0:0]);
	$fwrite(file, "input %s = %b\n", "dcr_wr_addr", scanOutReg[12:1]);
	$fwrite(file, "input %s = %b\n", "dcr_wr_data", scanOutReg[44:13]);
	$fwrite(file, "input %s = %b\n", "mem_req_valid", scanOutReg[45:45]);
	$fwrite(file, "input %s = %b\n", "mem_req_rw", scanOutReg[46:46]);
	$fwrite(file, "input %s = %b\n", "mem_req_addr", scanOutReg[72:47]);
	$fwrite(file, "input %s = %b\n", "mem_req_data", scanOutReg[584:73]);
	$fwrite(file, "input %s = %b\n", "mem_req_byteen", scanOutReg[648:585]);
	$fwrite(file, "input %s = %b\n", "mem_req_tag", scanOutReg[698:649]);
	$fwrite(file, "input %s = %b\n", "mem_rsp_ready", scanOutReg[699:699]);
	$fwrite(file, "output %s = %b\n", "busy", scanOutReg[700:700]);
	$fwrite(file, "output %s = %b\n", "mem_req_ready", scanOutReg[701:701]);
	$fwrite(file, "output %s = %b\n", "mem_rsp_valid", scanOutReg[702:702]);
	$fwrite(file, "output %s = %b\n", "mem_rsp_data", scanOutReg[1214:703]);
	$fwrite(file, "output %s = %b\n", "mem_rsp_tag", scanOutReg[1264:1215]);
	$fclose(file);
	return file;

endfunction