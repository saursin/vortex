`include "VX_define.vh"

module VX_wrapper (
    input  wire                             clk,
    input  wire                             reset,

    // DCR write request
    input  wire                             dcr_wr_valid,
    input  wire [`VX_DCR_ADDR_WIDTH-1:0]    dcr_wr_addr,
    input  wire [`VX_DCR_DATA_WIDTH-1:0]    dcr_wr_data,

    // Status
    output wire                             busy
);

    // Internal Memory Interface
    wire [`VX_MEM_PORTS]                             mem_req_valid ;
    wire [`VX_MEM_PORTS]                            mem_req_rw;
    wire [`VX_MEM_PORTS][`VX_MEM_BYTEEN_WIDTH-1:0]   mem_req_byteen;
    wire [`VX_MEM_PORTS][`VX_MEM_ADDR_WIDTH-1:0]    mem_req_addr;
    wire [`VX_MEM_PORTS][`VX_MEM_DATA_WIDTH-1:0]    mem_req_data;
    wire [`VX_MEM_PORTS][`VX_MEM_TAG_WIDTH-1:0]     mem_req_tag;
    wire [`VX_MEM_PORTS]                            mem_req_ready;

    wire [`VX_MEM_PORTS]                            mem_rsp_valid;
    wire [`VX_MEM_PORTS][`VX_MEM_DATA_WIDTH-1:0]    mem_rsp_data;
    wire [`VX_MEM_PORTS][`VX_MEM_TAG_WIDTH-1:0]     mem_rsp_tag;
    wire [`VX_MEM_PORTS]                            mem_rsp_ready;

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

endmodule
