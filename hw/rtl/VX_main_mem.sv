`include "VX_define.vh"

module VX_main_mem import VX_gpu_pkg::* ; #(
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

    // Internal RAM storage 1 MB
    localparam MEM_DEPTH = 1024*1024/(`VX_MEM_DATA_WIDTH/8);

    // Define memory regions
    localparam REGION1_SIZE = 'h180 / (`VX_MEM_DATA_WIDTH / 8);
    localparam REGION3_SIZE = ('h100000000 - 'hFFFD1FC0) / (`VX_MEM_DATA_WIDTH / 8);
    localparam REGION2_SIZE = MEM_DEPTH - REGION1_SIZE - REGION3_SIZE;
    localparam REGION2_END = `STARTUP_ADDR/ (`VX_MEM_DATA_WIDTH / 8) + REGION2_SIZE - 1;

    initial begin
        $display("STARTUP_ADDR = 0x%h", `STARTUP_ADDR);
        $display("MEM_DEPTH = 0x%h", MEM_DEPTH);
        $display("REGION1_SIZE = 0x%h", REGION1_SIZE);
        $display("REGION3_SIZE = 0x%h", REGION3_SIZE);
        $display("REGION2_SIZE = 0x%h", REGION2_SIZE);
        $display("REGION2_END = 0x%h", REGION2_END);
    end

    logic [`VX_MEM_ADDR_WIDTH-1:0] AA, mem_index;
    logic [`VX_MEM_DATA_WIDTH-1:0] DA, write_data, read_data, BWEBA;
    logic WEBA, CEBA;

    main_mem_sram ram (
        .AA (mem_index[13:0]),
        .DA (write_data),
        .BWEBA (BWEBA),             // Bit-write enable bar
        .WEBA (~mem_req_rw[0]),     // Active low write enable
        .CEBA (~mem_req_valid[0]),  // Active low chip enable
        .CLK (clk),
        .QA (read_data),
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_rsp_valid[0] <= 1'b0;
            mem_req_ready[0] <= 1'b0; 
            mem_rsp_tag[0] <= '0;// Always ready to accept new requests
        end else begin
            mem_req_ready[0] <= 1'b1;
            // Response handling
            if (mem_req_valid[0] && mem_req_ready[0]) begin
                if (mem_req_rw[0]) //Write
                    mem_rsp_valid[0] <= 1'b0; // No response for write operations
                else begin //Read
                    mem_rsp_valid[0] <= 1'b1;
                    mem_rsp_tag[0] <= mem_req_tag[0];
                end
            end 
            else if (mem_rsp_valid[0] && mem_rsp_ready[0]) begin
                mem_rsp_valid[0] <= 1'b0; // Clear response when it is accepted
            end
        end
    end

    always_comb begin
        BWEBA = '1;
        mem_rsp_data[0] = read_data;

        for (int i = 0; i < `VX_MEM_BYTEEN_WIDTH; i++) begin
            BWEBA[i*8 +: 8] = {{8}{~mem_req_byteen[0][i]}};
        end
        write_data = mem_req_data[0];

        if (mem_req_valid[0] && mem_req_ready[0]) begin
            if (mem_req_addr[0] < ('h180 / (`VX_MEM_DATA_WIDTH/8))) begin  // Region 1
                `ifdef DEBUG_MEM
                    $display("Region 1");
                `endif
                mem_index = mem_req_addr[0];
            end else if (mem_req_addr[0] >= (('hFFFD1FC0)/(`VX_MEM_DATA_WIDTH/8))) begin  // Upper Region (ram3)
                `ifdef DEBUG_MEM
                    $display("Region 3");
                `endif
                mem_index = mem_req_addr[0] - ('hFFFD1FC0)/(`VX_MEM_DATA_WIDTH/8) + MEM_DEPTH - REGION3_SIZE ;
            end else if ( mem_req_addr[0] >= (`STARTUP_ADDR /(`VX_MEM_DATA_WIDTH/8)) && mem_req_addr[0] <= REGION2_END) begin  // Middle Region (ram2)
                `ifdef DEBUG_MEM
                    $display("Region 2");
                `endif
                mem_index = mem_req_addr[0] - (`STARTUP_ADDR /(`VX_MEM_DATA_WIDTH/8)) + ('h180 / (`VX_MEM_DATA_WIDTH/8));
            end else begin
                $display("Time: %t | Error: Invalid memory request at address 0x%h region 2 end 0x%h", $time, mem_req_addr[0], REGION2_END);
                mem_index = '0;
                //mem_rsp_valid[0] = 1'b0;
            end
            if (mem_index >= MEM_DEPTH) begin
                $display("Time: %t | Error: out of bound mem index", $time);
            end
            if (mem_req_rw[0]) begin
                // Write Operation
                
                // for (int i = 0; i < `VX_MEM_BYTEEN_WIDTH; i++) begin
                //         BWEBA[i*8 +: 8] = {{8}{~mem_req_byteen[0][i]}};
                // end
                // write_data = mem_req_data[0];
                `ifdef DEBUG_MEM
                    $display("Time: %t | Writing 0x%h to address 0x%h", $time, write_data, mem_index);
                    $display("Mask = 0x%h", BWEBA);
                `endif
            end else begin
                // Read Operation
                //mem_rsp_data[0] = read_data;
                `ifdef DEBUG_MEM
                    $display("Time: %t | Reading at address 0x%h", $time, mem_index);
                `endif
            end
        end else begin
            mem_index = '0;
        end
    end

    `ifdef DEBUG_MEM
        always_ff @(posedge clk) begin
            if (mem_req_valid[0] && mem_req_ready[0] && !mem_req_rw[0]) 
                $display("Time: %t | Data read: 0x%h", $time, read_data);
        end
    `endif

    // always @(negedge clk) begin
    //     if (rst) begin
    //         AA      <= '0;
    //         DA      <= '0;
    //         BWEBA   <= '0;
    //         WEBA    <= '0;
    //         CEBA    <= '0;
    //     end else begin
    //         AA <= mem_index;
    //         DA <= write_data;
    //         for (int i = 0; i < `VX_MEM_DATA_WIDTH/8; i++) begin
    //                 BWEBA[i*8 +: 8] <= ~mem_req_byteen[0][i];
    //         end
    //         WEBA <= ~mem_req_rw[0];
    //         CEBA <= ~mem_req_valid[0];
    //     end
    // end


endmodule
