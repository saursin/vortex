// VX_debug_module.sv
// Version: 1.0
// Author: Saurabh Singh
// Email: saurabh.s@gatech.edu
//
// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*   
    Vortex Debug Module
    ===================
    Implements a simple debug module for controlling and monitoring the state of warps in the system.
    The debug module is accessed via a simple memory-mapped interface (VX debug bus).
    The debug module provides the following registers:
    
    Register Map:
    +------+----------+------------------+------------------------------------------------------------------------------+
    | Addr |   Name   |    Description   |                                   Subfields                                  |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  |     Name    | Range | Acc | Description                                      |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x0  | WSEL     | Warp select      | winsel      | 7:0   | RW  | select which 32-bit window of the warp           |
    |      |          |                  |             |       |     | status/mask registers to access.                 |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | warpsel     | 31:16 | RW  | select which warp's dscratch register            |
    |      |          |                  |             |       |     | to access and warp to step (global warp id)      |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x1  | WSTATUS  | Warp status      | wstatus     | 31:0  | R   | warp status for selected window:                 |
    |      |          |                  |             |       |     | [WSEL.winsel*32:+32]                             |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x2  | WMASK    | Warp Mask        | wmask       | 31:0  | RW  | Warp mask for selected window (bit[n]=1          |
    |      |          |                  |             |       |     | means warp n is selected for halt/resume)        |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x3  | WCTRL    | Warp Control     | haltreq     | 0     | W   | write 1 to halt all selected warps               |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | resumereq   | 1     | W   | write 1 to resume all selected warps             |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | stepreq     | 2     | W   | write 1 to step one instr in warp selected       |
    |      |          |                  |             |       |     | by `WSEL.warpsel`                                |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | stepstate   | 4:3   | W   | Shows status of step request                     |
    |      |          |                  |             |       |     | 2b00: NONE, 2b01: REQ, 2b10: INFLIGHT            |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | ndmreset    | 30    | RW  | write 1 to assert ndmreset output for            |
    |      |          |                  |             |       |     | NDMRESET_CYCLES cycles, Read returns 1           |
    |      |          |                  |             |       |     | if ndmreset is currently asserted                |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | dmactive    | 31    | RW  | write 1 to enable dm                             |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x4  | PLATFORM | Platform Info    | platformid  | 31:29 | R   | Platform ID: Vortex = 3'b001                     |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | numclusters | 28:24 | R   | Number of Clusters                               |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | numcores    | 23:16 | R   | Number of cores per cluster                      |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | numwarps    | 15:8  | R   | Number of warps per core                         |
    |      |          |                  +-------------+-------+-----+--------------------------------------------------+
    |      |          |                  | numthreads  | 7:0   | R   | Number of threads per warp                       |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    | 0x5  | DSCRATCH | Scratch Register | data        | 31:0  | RW  | Debug scratch data for the warp specified by     |
    |      |          |                  |             |       |     | `WSEL.warpsel`. Writing updates the dscratch CSR  |
    |      |          |                  |             |       |     | for the selected warp, Reading returns the       |
    |      |          |                  |             |       |     | dscratch CSR for the selected warp.              |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    |      |          |                  |             |       |     |                                                  |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    |      |          |                  |             |       |     |                                                  |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    |      |          |                  |             |       |     |                                                  |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    |      |          |                  |             |       |     |                                                  |
    +------+----------+------------------+-------------+-------+-----+--------------------------------------------------+
    Notes: 
    1.  If NUM_WARPS_TOTAL < 32, then WSEL.winsel is ignored and WSTATUS/WMASK directly reflect the status/mask of all 
        warps in the system. Else, WSEL.winsel selects which 32-bit window of WSTATUS/WMASK is accessed.

    2.  WSEL.warpsel is a global warp id (0 to NUM_WARPS_TOTAL-1). The debug module internally maps this to the appropriate
        core and local warp id within that core. 
    
    3. The debug module can control warps across all cores in the system. However, at any given time, only one warp can be 
       stepped. The warp to be stepped is selected using WSEL.warpsel. The step request is issued by writing 1 to WCTRL.stepreq.
       The step state can be monitored using WCTRL.stepstate field.
    
    4. The debug module must be enabled by writing 1 to WCTRL.dmactive before any other operation can be performed. When
       dmactive=0, all other registers (except PLATFORM) read as 0 and writes are ignored. dmactive can be set to 0
       to disable the debug module. Disabling the debug module also de-asserts any pending halt/resume/step requests and clears
       all internal state.
    
    5. Priority among halt, resume and step requests: halt > resume > step. 
*/


`include "VX_define.vh"

module VX_debug_module import VX_gpu_pkg::*; #(
    parameter PLATFORM_ID  = 3'b001,        // Vortex platform ID

    parameter NUM_CLUSTERS = `NUM_CLUSTERS, // Number of clusters in the system
    parameter NUM_CORES = `NUM_CORES,       // Number of cores per cluster
    parameter NUM_WARPS = `NUM_WARPS,       // Number of warps per core
    parameter NUM_THREADS = `NUM_THREADS,   // Number of threads per warp

    parameter NDMRESET_CYCLES = 16,         // Number of cycles to assert ndmreset output
    
    parameter NUM_CORES_TOTAL = NUM_CLUSTERS * NUM_CORES,   // Total number of cores in the system
    parameter NUM_WARPS_TOTAL = NUM_CORES_TOTAL * NUM_WARPS, // Total number of warps in the system
    parameter NDMRESET_CNTW = (NDMRESET_CYCLES > 0) ? $clog2(NDMRESET_CYCLES+1) : 1
) (
    input  wire                             clk,
    input  wire                             reset,

    // VX debug bus
    input  wire [`VXDBGBUS_ADDRW-1:0]       vxdbg_addr,
    output reg  [`VXDBGBUS_DATAW-1:0]       vxdbg_rdata,
    input  wire [`VXDBGBUS_DATAW-1:0]       vxdbg_wdata,
    input  wire                             vxdbg_we,
    input  wire                             vxdbg_valid,
    output reg                              vxdbg_ack,

    // Core interface
    VX_dm_core_if.master dm_core_if  [NUM_CORES_TOTAL-1:0],

    output wire                             ndmreset    // Non-debug module reset (active high)
);

    localparam WSEL_ADDR     = 4'h0;
    localparam WSTATUS_ADDR  = 4'h1;
    localparam WMASK_ADDR    = 4'h2;
    localparam WCTRL_ADDR    = 4'h3;
    localparam PLATFORM_ADDR = 4'h4;
    localparam DSCRATCH_ADDR = 4'h5;
    localparam DPC_ADDR      = 4'h6;

    logic dmactive;

    ////////////////////////////////////////
    // WSEL register
    logic [7:0]     wsel_winsel;    // Each value n selects warps [n*32 .. n*32+31]
    logic [15:0]    wsel_warpselwid;   // Global warp id whose dscratch register is accessed and which is stepped

    logic [31:0]    wsel_rdval;
    assign wsel_rdval = {wsel_warpselwid, 8'b0, wsel_winsel};

    always_ff @(posedge clk) begin
        if(reset || !dmactive) begin
            wsel_winsel  <= 8'h0;
            wsel_warpselwid <= 16'h0;
        end
        else begin
            if(vxdbg_valid && vxdbg_we && (vxdbg_addr == WSEL_ADDR)) begin
                wsel_winsel     <= vxdbg_wdata[7:0];
                wsel_warpselwid <= vxdbg_wdata[31:16];
            end
        end
    end

    // Connect wsel_warpselwid to core interface signals
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_warpsel_wid
        wire [15:0] warpsel_wid_local = wsel_warpselwid % NUM_WARPS;
        `UNUSED_VAR(warpsel_wid_local);
        assign dm_core_if[i].wsel_wid   = warpsel_wid_local[`CLOG2(NUM_WARPS)-1:0]; // Selected warp
    end


    ////////////////////////////////////////
    // WSTATUS register [read-only]

    // Warp status array (all warps on all cores)
    logic [NUM_WARPS_TOTAL-1:0] warp_status;    // warp_status[n] = 1 means warp n is halted
    for(genvar i = 0; i < NUM_WARPS_TOTAL; i++) begin: g_warp_status
        assign warp_status[i] = dm_core_if[i/NUM_WARPS].warp_status[i%NUM_WARPS];
    end

    logic [31:0] wstatus_rdval;
    generate
        if(NUM_WARPS_TOTAL < 32) begin: g_small_status
            // If total warps < 32, then ignore wsel_warpsel and return status of all warps
            assign wstatus_rdval = { {(32-NUM_WARPS_TOTAL){1'b0}}, warp_status} ;
        end
        else begin: g_large_status
            // wsel_warpsel selects which 32-bit window of warp_status to return
            assign wstatus_rdval = warp_status[wsel_winsel*32 +: 32];
        end
    endgenerate


    ////////////////////////////////////////
    // WMASK register

    // Warp mask array (all warps on all cores)
    logic [NUM_WARPS_TOTAL-1:0] warp_mask;   // warp_mask[n] = 1 means warp n is selected for halt/resume

    logic [31:0] wmask_rdval;
    generate
        if(NUM_WARPS_TOTAL < 32) begin: g_rd_small_mask
            // If total warps < 32, then ignore wsel_warpsel and return mask of all warps
            assign wmask_rdval = { {(32-NUM_WARPS_TOTAL){1'b0}}, warp_mask } ;
        end
        else begin: g_rd_large_mask
            // wsel_warpsel selects which 32-bit window of warp_mask to return
            assign wmask_rdval = warp_mask[wsel_winsel*32 +: 32];
        end
    endgenerate

    generate
        if (NUM_WARPS_TOTAL < 32) begin : g_wr_small_mask
            // If total warps < 32, then ignore wsel_warpsel and update mask of all warps
            always_ff @(posedge clk) begin
                if (reset || !dmactive) begin
                    warp_mask <= '0;
                end else if (vxdbg_valid && vxdbg_we && (vxdbg_addr == WMASK_ADDR)) begin
                    warp_mask <= vxdbg_wdata[NUM_WARPS_TOTAL-1:0];
                end
            end
        end else begin : g_wr_large_mask
            // wsel_warpsel selects which 32-bit window of warp_mask to update
            always_ff @(posedge clk) begin
                if (reset || !dmactive) begin
                    warp_mask <= '0;
                end else if (vxdbg_valid && vxdbg_we && (vxdbg_addr == WMASK_ADDR)) begin
                    warp_mask[wsel_winsel*32 +: 32] <= vxdbg_wdata[31:0];
                end
            end
        end
    endgenerate

    for(genvar i = 0; i < NUM_WARPS_TOTAL; i++) begin: g_warp_mask
        assign dm_core_if[i/NUM_WARPS].warp_mask[i%NUM_WARPS] = warp_mask[i];
    end


    ////////////////////////////////////////
    // WCTRL register

    always_ff @(posedge clk) begin
        if (reset) begin
            dmactive <= 1'b0;
        end else if (vxdbg_valid && vxdbg_we && (vxdbg_addr == WCTRL_ADDR)) begin
            dmactive <= vxdbg_wdata[31];
        end
    end

    logic wctrl_haltreq;
    logic wctrl_resumereq;
    logic wctrl_stepreq;
    assign wctrl_haltreq     = (vxdbg_valid && vxdbg_we && (vxdbg_addr == WCTRL_ADDR) && vxdbg_wdata[0]);
    assign wctrl_resumereq   = (vxdbg_valid && vxdbg_we && (vxdbg_addr == WCTRL_ADDR) && vxdbg_wdata[1]);
    assign wctrl_stepreq     = (vxdbg_valid && vxdbg_we && (vxdbg_addr == WCTRL_ADDR) && vxdbg_wdata[2]);

    // Ndmreset logic
    logic wctrl_ndmreset;
    assign wctrl_ndmreset = (vxdbg_valid && vxdbg_we && (vxdbg_addr == WCTRL_ADDR) && vxdbg_wdata[30]);

    logic [NDMRESET_CNTW-1:0] ndmreset_ctr;
    always_ff @(posedge clk) begin
        if (reset || !dmactive) begin
            ndmreset_ctr <= '0;
        end else if (wctrl_ndmreset) begin
            ndmreset_ctr <= NDMRESET_CYCLES[NDMRESET_CNTW-1:0];
        end else if (ndmreset_ctr != 0) begin
            ndmreset_ctr <= ndmreset_ctr - 1'b1;
        end
    end
    assign ndmreset = dmactive && (ndmreset_ctr != 0);

    // select step_state from the core to which the warpsel_wid belongs
    logic [1:0] step_state_array [NUM_CORES_TOTAL];
    generate
        for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin : g_step
            assign step_state_array[i] = dm_core_if[i].step_state;
        end
    endgenerate

    logic [31:0] wctrl_rdval;
    assign wctrl_rdval = {dmactive, ndmreset, 25'b0, step_state_array[wsel_warpselwid / NUM_WARPS], 1'b0, 1'b0, 1'b0};

    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_halt_resume
        // only assert halt_req/resume_req if any warp in this core is selected
        assign dm_core_if[i].halt_req   = dmactive && wctrl_haltreq   && (|(warp_mask[i*NUM_WARPS +: NUM_WARPS]));
        assign dm_core_if[i].resume_req = dmactive && wctrl_resumereq && (|(warp_mask[i*NUM_WARPS +: NUM_WARPS]));

        // Only assert step_req if the warpsel_wid belongs to this core
        assign dm_core_if[i].step_req = dmactive && wctrl_stepreq && (wsel_warpselwid/NUM_WARPS == i);
    end


    ////////////////////////////////////////
    // PLATFORM register [read-only]

    logic [31:0] platform_rdval;
    assign platform_rdval = {
        PLATFORM_ID[2:0],              // [31:29] Platform ID
        NUM_CLUSTERS[4:0],             // [28:24] Number of clusters
        NUM_CORES[7:0],                // [23:16] Number of cores per cluster
        NUM_WARPS[7:0],                // [15:8]  Number of warps per core
        NUM_THREADS[7:0]               // [7:0]   Number of threads per warp
    };


    /////////////////////////////////////////
    // DSCRATCH register

    logic [31:0] dscratch_array [NUM_CORES_TOTAL-1:0];
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dscratch_rdmux
        assign dscratch_array[i] = dm_core_if[i].dscratch_rdat;
    end

    logic [31:0] dscratch_rdval;
    assign dscratch_rdval = dscratch_array[wsel_warpselwid/NUM_WARPS];

    logic dscratch_we;
    assign dscratch_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DSCRATCH_ADDR));

    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dscratch
        assign dm_core_if[i].dscratch_wdat = vxdbg_wdata;
        assign dm_core_if[i].dscratch_we   = dscratch_we && (wsel_warpselwid/NUM_WARPS == i);
    end

    /////////////////////////////////////////
    // DPC register (read-only)

    logic [`PC_BITS-1:0] dpc_array [NUM_CORES_TOTAL-1:0];
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dpc_rdmux
        assign dpc_array[i] = dm_core_if[i].dpc_rdat;
    end

    // DM: just pick the core, core will pick the warp internally
    logic [31:0] dpc_rdval;
    assign dpc_rdval = {dpc_array[wsel_warpselwid/NUM_WARPS], 1'b0};

    logic dpc_we;
    assign dpc_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DPC_ADDR));
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dpc
        assign dm_core_if[i].dpc_wdat = vxdbg_wdata[`PC_BITS:1];
        assign dm_core_if[i].dpc_we   = dpc_we && (wsel_warpselwid/NUM_WARPS == i);
    end


    ////////////////////////////////////////////////////////////////////////////////
    // Debug bus interface logic

    always_ff @(posedge clk) begin
        if(reset) begin
            vxdbg_rdata <= '0;
            vxdbg_ack <= 1'b0;
        end
        else begin
            vxdbg_ack <= 1'b0;
            if(vxdbg_valid && !vxdbg_ack) begin
                vxdbg_ack <= 1'b1;

                if(!vxdbg_we) begin
                    // Read operation
                    case(vxdbg_addr)
                        WSEL_ADDR:      vxdbg_rdata <= wsel_rdval;
                        WSTATUS_ADDR:   vxdbg_rdata <= wstatus_rdval;
                        WMASK_ADDR:     vxdbg_rdata <= wmask_rdval;
                        WCTRL_ADDR:     vxdbg_rdata <= wctrl_rdval;
                        PLATFORM_ADDR:  vxdbg_rdata <= platform_rdval;
                        DSCRATCH_ADDR:  vxdbg_rdata <= dscratch_rdval;
                        DPC_ADDR:       vxdbg_rdata <= dpc_rdval;
                        default:        vxdbg_rdata <= 'd0;
                    endcase
                end
            end
        end
    end

    `UNUSED_VAR(vxdbg_wdata)

endmodule
