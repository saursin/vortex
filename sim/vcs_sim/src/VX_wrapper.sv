`include "VX_define.vh"

module VX_wrapper (
    input  wire                             clk,
    input  wire                             reset,

    // Scan Chain
    input  logic scan_in,
    input  logic update,
    input  logic capture,
    input  logic phi,
    input  logic phi_bar,
    output logic scan_out,

    // Status
    output wire                             busy
);

    // Internal Memory Interface
    wire                             mem_req_valid [`VX_MEM_PORTS];
    wire                             mem_req_rw [`VX_MEM_PORTS];
    wire [`VX_MEM_BYTEEN_WIDTH-1:0]  mem_req_byteen [`VX_MEM_PORTS];
    wire [`VX_MEM_ADDR_WIDTH-1:0]    mem_req_addr [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    mem_req_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     mem_req_tag [`VX_MEM_PORTS];
    wire                             mem_req_ready [`VX_MEM_PORTS];

    wire                             mem_rsp_valid [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    mem_rsp_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     mem_rsp_tag [`VX_MEM_PORTS];
    wire                             mem_rsp_ready [`VX_MEM_PORTS];

    // Instantiate Vortex
    Vortex vortex_inst (
        .clk(clk),
        .reset(reset),
        .mem_req_valid(mem_req_valid),
        .mem_req_rw(mem_req_rw),
        .mem_req_byteen(mem_req_byteen),
        .mem_req_addr(mem_req_addr),
        .mem_req_data(mem_req_data),
        .mem_req_tag(mem_req_tag),
        .mem_req_ready(mem_req_ready),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_data(mem_rsp_data),
        .mem_rsp_tag(mem_rsp_tag),
        .mem_rsp_ready(mem_rsp_ready),
        .dcr_wr_valid(dcr_wr_valid),
        .dcr_wr_addr(dcr_wr_addr),
        .dcr_wr_data(dcr_wr_data),
        .busy(busy)
    );

    // Instantiate Memory
    memory mem_inst (
        .clk(clk),
        .rst(reset),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_rw(mem_req_rw),
        .mem_req_addr(mem_req_addr),
        .mem_req_data(mem_req_data),
        .mem_req_byteen(mem_req_byteen),
        .mem_req_tag(mem_req_tag),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_ready(mem_rsp_ready),
        .mem_rsp_data(mem_rsp_data),
        .mem_rsp_tag(mem_rsp_tag)
    );

    // Scan chain
    scan_module_vortex_sc_wrapper sc_wrappper (
        .scan_in        (scan_in),
        .update         (update),
        .capture        (capture),
        .phi            (phi),
        .phi_bar        (phi_bar),
        .scan_out       (scan_out),
	    .dcr_wr_valid   (dcr_wr_valid),
	    .dcr_wr_addr    (dcr_wr_addr),
	    .dcr_wr_data    (dcr_wr_data),
	    .mem_req_valid  (mem_req_valid),
	    .mem_req_rw     (mem_req_rw),
	    .mem_req_addr   (mem_req_addr),
	    .mem_req_data   (mem_req_data),
	    .mem_req_byteen (mem_req_byteen),
	    .mem_req_tag    (mem_req_tag),
	    .mem_rsp_ready  (mem_rsp_ready),
	    .busy           (busy),
	    .mem_req_ready  (mem_req_ready),
	    .mem_rsp_valid  (mem_rsp_valid),
	    .mem_rsp_data   (mem_rsp_data),
	    .mem_rsp_tag    (mem_rsp_tag)
    );

endmodule
