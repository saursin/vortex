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
    wire                             vortex_inst_mem_req_valid [`VX_MEM_PORTS];
    wire                             vortex_inst_mem_req_rw [`VX_MEM_PORTS];
    wire [`VX_MEM_BYTEEN_WIDTH-1:0]  vortex_inst_mem_req_byteen [`VX_MEM_PORTS];
    wire [`VX_MEM_ADDR_WIDTH-1:0]    vortex_inst_mem_req_addr [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    vortex_inst_mem_req_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     vortex_inst_mem_req_tag [`VX_MEM_PORTS];
    wire                             vortex_inst_mem_req_ready [`VX_MEM_PORTS];

    wire                             vortex_inst_mem_rsp_valid [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    vortex_inst_mem_rsp_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     vortex_inst_mem_rsp_tag [`VX_MEM_PORTS];
    wire                             vortex_inst_mem_rsp_ready [`VX_MEM_PORTS];

    wire                             sc_wrapper_mem_req_valid [`VX_MEM_PORTS];
    wire                             sc_wrapper_mem_req_rw [`VX_MEM_PORTS];
    wire [`VX_MEM_BYTEEN_WIDTH-1:0]  sc_wrapper_mem_req_byteen [`VX_MEM_PORTS];
    wire [`VX_MEM_ADDR_WIDTH-1:0]    sc_wrapper_mem_req_addr [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    sc_wrapper_mem_req_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     sc_wrapper_mem_req_tag [`VX_MEM_PORTS];

    wire                             dcr_wr_valid;
    wire [`VX_DCR_ADDR_WIDTH-1:0]    dcr_wr_addr;
    wire [`VX_DCR_DATA_WIDTH-1:0]    dcr_wr_data;

    // MUX Logic: Select between vortex_inst and sc_wrapper based on `update` signal
    wire                             mem_req_valid [`VX_MEM_PORTS];
    wire                             mem_req_rw [`VX_MEM_PORTS];
    wire [`VX_MEM_BYTEEN_WIDTH-1:0]  mem_req_byteen [`VX_MEM_PORTS];
    wire [`VX_MEM_ADDR_WIDTH-1:0]    mem_req_addr [`VX_MEM_PORTS];
    wire [`VX_MEM_DATA_WIDTH-1:0]    mem_req_data [`VX_MEM_PORTS];
    wire [`VX_MEM_TAG_WIDTH-1:0]     mem_req_tag [`VX_MEM_PORTS];

    genvar i;
    generate
        for (i = 0; i < `VX_MEM_PORTS; i++) begin
            assign mem_req_valid[i]  = update ? sc_wrapper_mem_req_valid[i]  : vortex_inst_mem_req_valid[i];
            assign mem_req_rw[i]     = update ? sc_wrapper_mem_req_rw[i]     : vortex_inst_mem_req_rw[i];
            assign mem_req_addr[i]   = update ? sc_wrapper_mem_req_addr[i]   : vortex_inst_mem_req_addr[i];
            assign mem_req_data[i]   = update ? sc_wrapper_mem_req_data[i]   : vortex_inst_mem_req_data[i];
            assign mem_req_byteen[i] = update ? sc_wrapper_mem_req_byteen[i] : vortex_inst_mem_req_byteen[i];
            assign mem_req_tag[i]    = update ? sc_wrapper_mem_req_tag[i]    : vortex_inst_mem_req_tag[i];
        end
    endgenerate


    // Instantiate Vortex
    Vortex vortex_inst (
        .clk(clk),
        .reset(reset),
        .mem_req_valid(vortex_inst_mem_req_valid),
        .mem_req_rw(vortex_inst_mem_req_rw),
        .mem_req_byteen(vortex_inst_mem_req_byteen),
        .mem_req_addr(vortex_inst_mem_req_addr),
        .mem_req_data(vortex_inst_mem_req_data),
        .mem_req_tag(vortex_inst_mem_req_tag),
        .mem_req_ready(vortex_inst_mem_req_ready),
        .mem_rsp_valid(vortex_inst_mem_rsp_valid),
        .mem_rsp_data(vortex_inst_mem_rsp_data),
        .mem_rsp_tag(vortex_inst_mem_rsp_tag),
        .mem_rsp_ready(vortex_inst_mem_rsp_ready),
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
        .mem_req_ready(vortex_inst_mem_req_ready), // Connected to Vortex output
        .mem_req_rw(mem_req_rw),
        .mem_req_addr(mem_req_addr),
        .mem_req_data(mem_req_data),
        .mem_req_byteen(mem_req_byteen),
        .mem_req_tag(mem_req_tag),
        .mem_rsp_valid(vortex_inst_mem_rsp_valid),
        .mem_rsp_ready(vortex_inst_mem_rsp_ready),
        .mem_rsp_data(vortex_inst_mem_rsp_data),
        .mem_rsp_tag(vortex_inst_mem_rsp_tag)
    );

    // Scan chain
    scan_module_vortex_sc_wrapper sc_wrapper (
        .scan_in        (scan_in),
        .update         (update),
        .capture        (capture),
        .phi            (phi),
        .phi_bar        (phi_bar),
        .scan_out       (scan_out),
        .dcr_wr_valid   (dcr_wr_valid),
        .dcr_wr_addr    (dcr_wr_addr),
        .dcr_wr_data    (dcr_wr_data),
        .mem_req_valid  (sc_wrapper_mem_req_valid),
        .mem_req_rw     (sc_wrapper_mem_req_rw),
        .mem_req_addr   (sc_wrapper_mem_req_addr),
        .mem_req_data   (sc_wrapper_mem_req_data),
        .mem_req_byteen (sc_wrapper_mem_req_byteen),
        .mem_req_tag    (sc_wrapper_mem_req_tag),
        .mem_rsp_ready  (vortex_inst_mem_rsp_ready),  // Allow response from Vortex
        .busy           (busy),
        .mem_req_ready  (vortex_inst_mem_req_ready),
        .mem_rsp_valid  (vortex_inst_mem_rsp_valid),
        .mem_rsp_data   (vortex_inst_mem_rsp_data),
        .mem_rsp_tag    (vortex_inst_mem_rsp_tag)
    );

endmodule
