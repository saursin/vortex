module scan_module_vortex_sc_wrapper (
    input  logic scan_in,
    input  logic update,
    input  logic capture,
    input  logic phi,
    input  logic phi_bar,
    output logic scan_out,
	output logic dcr_wr_valid,
	output logic [11:0] dcr_wr_addr,
	output logic [31:0] dcr_wr_data,
	output logic mem_req_valid,
	output logic mem_req_rw,
	output logic [25:0] mem_req_addr,
	output logic [511:0] mem_req_data,
	output logic [63:0] mem_req_byteen,
	output logic [49:0] mem_req_tag,
	output logic mem_rsp_ready,
	input  logic busy,
	input  logic mem_req_ready,
	input  logic mem_rsp_valid,
	input  logic [511:0] mem_rsp_data,
	input  logic [49:0] mem_rsp_tag

);
    logic [1264:0] scan_cell_out;
    logic [1264:0] chip_data_out;
    logic [1264:0] chip_data_in;

    scan_cell sc[1264:0] (
        .scan_in({scan_in,scan_cell_out[1264:1]}),
        .scan_out(scan_cell_out[1264:0]),
        .phi(phi),
        .phi_bar(phi_bar),
        .capture(capture),
        .update(update),
        .chip_data_out(chip_data_out),
        .chip_data_in(chip_data_in)
    );

    assign scan_out = scan_cell_out[0];

	//Autogen assignments
	//Make assignments for chip_data_in
	assign dcr_wr_valid = chip_data_in[0:0];
	assign dcr_wr_addr = chip_data_in[12:1];
	assign dcr_wr_data = chip_data_in[44:13];
	assign mem_req_valid = chip_data_in[45:45];
	assign mem_req_rw = chip_data_in[46:46];
	assign mem_req_addr = chip_data_in[72:47];
	assign mem_req_data = chip_data_in[584:73];
	assign mem_req_byteen = chip_data_in[648:585];
	assign mem_req_tag = chip_data_in[698:649];
	assign mem_rsp_ready = chip_data_in[699:699];

	//Make assignments for chip_data_out
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

endmodule //scan_module_vortex_sc_wrapper
