import VX_gpu_pkg::* ;
module memory #(
    parameter ADDR_WIDTH = `VX_MEM_ADDR_WIDTH,
    parameter DATA_WIDTH = `VX_MEM_DATA_WIDTH,
    parameter NUM_BANKS = `VX_MEM_PORTS
)(
    input  logic                         clk,
    input  logic                         rst,

    // Memory Request Interface
    input  logic                                 mem_req_valid [`VX_MEM_PORTS],
    output logic                                 mem_req_ready [`VX_MEM_PORTS],
    input  logic                                 mem_req_rw    [`VX_MEM_PORTS],  // 0: Read, 1: Write
    input  logic [`VX_MEM_ADDR_WIDTH-1:0]        mem_req_addr  [`VX_MEM_PORTS],
    input  logic [`VX_MEM_DATA_WIDTH-1:0]        mem_req_data  [`VX_MEM_PORTS],
    input  logic [`VX_MEM_BYTEEN_WIDTH-1:0]      mem_req_byteen[`VX_MEM_PORTS],
    input  logic [`VX_MEM_TAG_WIDTH-1:0]         mem_req_tag   [`VX_MEM_PORTS],

    // Memory Response Interface
    output logic                                 mem_rsp_valid[`VX_MEM_PORTS],
    input  logic                                 mem_rsp_ready[`VX_MEM_PORTS],
    output logic [`VX_MEM_DATA_WIDTH-1:0]        mem_rsp_data [`VX_MEM_PORTS],
    output logic [`VX_MEM_TAG_WIDTH-1:0]         mem_rsp_tag  [`VX_MEM_PORTS]
);

    // Internal RAM storage
    localparam MEM_DEPTH = 1024*1024*8/`VX_MEM_DATA_WIDTH;
    //localparam MEM_DEPTH = 805306368;
   // logic [`VX_MEM_DATA_WIDTH-1:0] ram [0:MEM_DEPTH-1] = '{default: '0};
    logic [`VX_MEM_DATA_WIDTH-1:0] ram [0:MEM_DEPTH-1] = '{default: '0};

    genvar b;
    generate
        for (b = 0; b < `VX_MEM_PORTS; b++) begin : mem_port
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    mem_rsp_valid[b] <= 1'b0;
                    mem_req_ready[b] <= 1'b1; // Always ready to accept new requests
                end else begin
                    if (mem_req_valid[b] && mem_req_ready[b]) begin
                        if (mem_req_rw[b]) begin
                            // Write Operation
                            for (int i = 0; i < `VX_MEM_DATA_WIDTH/8; i++) begin
                                if (mem_req_byteen[b][i])
                                    ram[mem_req_addr[b]][i*8 +: 8] <= mem_req_data[b][i*8 +: 8];
                            end
                            mem_rsp_valid[b] <= 1'b0; // No response for write operations
                        end else begin
                            // Read Operation
                            mem_rsp_valid[b] <= 1'b1;
                            mem_rsp_data[b]  <= ram[mem_req_addr[b]];
                            mem_rsp_tag[b]   <= mem_req_tag[b];
                        end
                    end
                    
                    // Response handling
                    if (mem_rsp_valid[b] && mem_rsp_ready[b]) begin
                        mem_rsp_valid[b] <= 1'b0; // Clear response when it is accepted
                    end
                end
            end
        end
    endgenerate

endmodule
