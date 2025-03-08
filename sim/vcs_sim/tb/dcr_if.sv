`include "VX_define.vh"

interface dcr_if;
    logic                          dcr_wr_valid;
    logic [`VX_DCR_ADDR_WIDTH-1:0] dcr_wr_addr;
    logic [`VX_DCR_DATA_WIDTH-1:0] dcr_wr_data;
endinterface