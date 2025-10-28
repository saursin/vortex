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
   
    Spec can be found at: saursin.github.io/projects/vortex_debug.html

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

    5. Priority among halt, resume, step and inject requests: halt > resume > step > inject.
*/


`include "VX_define.vh"

`define CEILDIV(num, denom)  (((num) + (denom) - 1) / (denom))

module VX_debug_module import VX_gpu_pkg::*; #(
    parameter PLATFORM_ID   = 4'b0001,           // Vortex platform ID

    parameter NUM_CLUSTERS  = `NUM_CLUSTERS,    // Number of clusters in the system
    parameter NUM_CORES     = `NUM_CORES,       // Number of cores per cluster
    parameter NUM_WARPS     = `NUM_WARPS,       // Number of warps per core
    parameter NUM_THREADS   = `NUM_THREADS,     // Number of threads per warp

    parameter DEFAULT_NDMRESET_LOG2CYC     = 4,    // Number of cycles to assert ndmreset (4 -> 16 cycles)
    parameter DEFAULT_RESETHALTREQ_LOG2CYC = 2,    // Number of cycles to assert resethaltreq (2 -> 4 cycles)
                                                    //  (Atleast num of cycles to propogate reset to all cores + 1
                                                    //  For vortex, 3 + 1, since reset is propogated to cores in 3 cycles)

    parameter NDMRESET_CTR_BITS     = 6,            //  Number of bits for ndmreset counter (max cycles = 2**NDMRESET_CTR_BITS)
    parameter RESETHALTREQ_CTR_BITS = 6,            //  Number of bits for resethaltreq counter (max cycles = 2**RESETHALTREQ_CTR_BITS)

    // -----------------
    parameter NUM_CORES_TOTAL   = NUM_CLUSTERS * NUM_CORES,     // Total number of cores in the system
    parameter NUM_WARPS_TOTAL   = NUM_CORES_TOTAL * NUM_WARPS,  // Total number of warps in the system
    
    parameter NT_BITS           = `LOG2UP(NUM_THREADS),         // Number of bits needed to select a thread within a warp

    parameter NW_BITS           = `LOG2UP(NUM_WARPS),           // Number of bits needed to select a warp within a core
    parameter NWT_BITS          = `LOG2UP(NUM_WARPS_TOTAL),     // Number of bits needed to select a warp within the system

    // parameter NC_BITS        = `LOG2UP(NUM_CORES);         // Number of bits needed to select a core within a cluster
    parameter NCT_BITS          = `LOG2UP(NUM_CORES_TOTAL),      // Number of bits needed to select a core within the system
    parameter NWINSEL_BITS      = (NUM_WARPS_TOTAL <= 32) ? 1 : $clog2(`CEILDIV(NUM_WARPS_TOTAL, 32)) // Number of bits needed to select 32-bit window of warps
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
    
    ////////////////////////////////////////////////////////////////////////////////
    // Local parameters and variables       

    // Register addresses
    localparam PLATFORM_ADDR    = 4'h0;
    localparam DCONFIG_ADDR     = 4'h1;
    localparam DSELECT_ADDR     = 4'h2;
    localparam WMASK_ADDR       = 4'h3;
    localparam WACTIVE_ADDR     = 4'h4;
    localparam WSTATUS_ADDR     = 4'h5;
    localparam DCTRL_ADDR       = 4'h6;
    localparam DPC_ADDR         = 4'h7;
    localparam INJECT_ADDR      = 4'h8;
    localparam DSCRATCH_ADDR    = 4'h9;

    logic dmactive;
    logic any_halted, all_halted, any_running, all_running;
    
    ////////////////////////////////////////
    // PLATFORM register [read-only]
    logic [31:0] platform_rdval;
    assign platform_rdval = {
        PLATFORM_ID[3:0],               // [31:28] Platform ID
        NUM_CLUSTERS[6:0],              // [27:21] Number of clusters
        NUM_CORES[8:0],                 // [20:12] Number of cores per cluster
        NUM_WARPS[8:0],                 // [11:3]  Number of warps per core
        NT_BITS[2:0]                    // [2:0]   Number of threads per warp
    };

    ////////////////////////////////////////
    // DCONFIG register
    logic dconfig_we;
    assign dconfig_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DCONFIG_ADDR));

    logic [31:0] dconfig_rdval;

    logic [2:0]   dconfig_ndmreset_log2cyc;
    logic [2:0]   dconfig_resethaltreq_log2cyc;
    logic         dconfig_ebreakh;
    
    always_ff @(posedge clk) begin
        if(reset || !dmactive) begin
            dconfig_ndmreset_log2cyc        <= DEFAULT_NDMRESET_LOG2CYC;
            dconfig_resethaltreq_log2cyc    <= DEFAULT_RESETHALTREQ_LOG2CYC;
            dconfig_ebreakh                 <= 1'b0;                // Default: ebreakh disabled
        end
        else begin
            if(dconfig_we) begin
                dconfig_ndmreset_log2cyc        <= vxdbg_wdata[31:29];
                dconfig_resethaltreq_log2cyc    <= vxdbg_wdata[28:26];
                dconfig_ebreakh                 <= vxdbg_wdata[0];
            end
        end
    end

    assign dconfig_rdval = {
        dconfig_ndmreset_log2cyc,        // [31:29] Ndmreset cycle log2
        dconfig_resethaltreq_log2cyc,    // [28:26] Resethaltreq cycle log2
        25'b0,                           // [25:1]  Reserved
        dconfig_ebreakh                  // [0]     Ebreakh enable
    };
   
    // Connect ebreakh enable to all cores
    for(genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin: g_ebreakh
        assign dm_core_if[cid].ebreak_halt = dconfig_ebreakh;
    end

    ////////////////////////////////////////
    // DSELECT register
    logic dselect_we;
    assign dselect_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DSELECT_ADDR));

    logic [NT_BITS-1:0]         dselect_threadsel;  // Selects the thread within the selected warp for debugging
    logic [NWT_BITS-1:0]        dselect_warpsel;    // Selects the warp globally for debugging
    logic [NWINSEL_BITS-1:0]    dselect_winsel;     // Selects which 32-bit window of WSTATUS/WMASK to access

    logic [31:0]    dselect_rdval;
    assign dselect_rdval = {
        {10-NWINSEL_BITS{1'b0}},    
        dselect_winsel,
        {15-NWT_BITS{1'b0}},
        dselect_warpsel,
        {7-NT_BITS{1'b0}},
        dselect_threadsel
    };

    always_ff @(posedge clk) begin
        if(reset || !dmactive) begin
            dselect_winsel      <= '0;
            dselect_warpsel     <= '0;
            dselect_threadsel   <= '0;
        end
        else begin
            if(dselect_we) begin
                dselect_winsel      <= vxdbg_wdata[22+:NWINSEL_BITS];
                dselect_warpsel     <= vxdbg_wdata[7+:NWT_BITS];
                dselect_threadsel   <= vxdbg_wdata[0+:NT_BITS];
            end
        end
    end

    // Determine which core the selected warp belongs to
    logic [NCT_BITS-1:0] selected_core_id;
    generate 
        if (NUM_CORES == 1) begin : g_single_core
            assign selected_core_id = '0;
        end else begin : g_multi_core
            assign selected_core_id = dselect_warpsel[NWT_BITS-1:NW_BITS];  // selected_core_id = dselect_warpsel / NUM_WARPS (assumes NUM_WARPS is power of 2)
        end
    endgenerate

    // Determine the local warp id within the selected core
    logic [NW_BITS-1:0] selected_core_local_wid;
    assign selected_core_local_wid = dselect_warpsel[NW_BITS-1:0];  // selected_core_local_wid = dselect_warpsel % NUM_WARPS (assumes NUM_WARPS is power of 2)

    // Connect dselect_warpsel & dselect_threadsel to core interface signals
    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin: g_warpsel_wid
        assign dm_core_if[cid].sel_wid = selected_core_local_wid;     // core local warp id
        assign dm_core_if[cid].sel_tid = dselect_threadsel;           // thread select within the warp
    end

    ////////////////////////////////////////
    // WMASK register
    logic wmask_we;
    assign wmask_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == WMASK_ADDR));

    // Warp mask array (all warps on all cores)
    logic [NUM_WARPS_TOTAL-1:0] warp_mask_arr;   // warp_mask[n] = 1 means warp n is selected for halt/resume

    logic [31:0] wmask_rdval;
    generate
        if(NUM_WARPS_TOTAL < 32) begin: g_rd_small_mask
            // If total warps < 32, then ignore wsel_warpsel and return mask of all warps
            assign wmask_rdval = { {(32-NUM_WARPS_TOTAL){1'b0}}, warp_mask_arr } ;
        end
        else begin: g_rd_large_mask
            // wsel_warpsel selects which 32-bit window of warp_mask to return
            assign wmask_rdval = warp_mask_arr[dselect_winsel*32 +: 32];
        end
    endgenerate

    generate
        if (NUM_WARPS_TOTAL < 32) begin : g_wr_small_mask
            // If total warps < 32, then ignore wsel_warpsel and update mask of all warps
            always_ff @(posedge clk) begin
                if (reset || !dmactive) begin
                    warp_mask_arr <= '0;
                end else if (wmask_we) begin
                    warp_mask_arr <= vxdbg_wdata[NUM_WARPS_TOTAL-1:0];
                end
            end
        end else begin : g_wr_large_mask
            // wsel_warpsel selects which 32-bit window of warp_mask to update
            always_ff @(posedge clk) begin
                if (reset || !dmactive) begin
                    warp_mask_arr <= '0;
                end else if (wmask_we) begin
                    warp_mask_arr[dselect_winsel*32 +: 32] <= vxdbg_wdata[31:0];
                end
            end
        end
    endgenerate

   // Connect warp_mask_arr to core interface signals
    for(genvar cid=0; cid < NUM_CORES_TOTAL; cid++) begin: g_debug_core_id
        assign dm_core_if[cid].warp_mask = warp_mask_arr[cid*NUM_WARPS +: NUM_WARPS];
    end


    ////////////////////////////////////////
    // WACTIVE register [read-only]
    // Warp active array (all warps on all cores)
    logic [NUM_WARPS_TOTAL-1:0] warp_active_arr;    // warp_active[n] = 1 means warp n is active
    for(genvar cid=0; cid < NUM_CORES_TOTAL; cid++) begin: g_debug_core_active
        assign warp_active_arr[cid*NUM_WARPS +: NUM_WARPS] = dm_core_if[cid].warp_active;
    end

    logic [31:0] wactive_rdval;
    generate
        if(NUM_WARPS_TOTAL < 32) begin: g_small_active
            // If total warps < 32, then ignore wsel_warpsel and return active status of all warps
            assign wactive_rdval = { {(32-NUM_WARPS_TOTAL){1'b0}}, warp_active_arr} ;
        end
        else begin: g_large_active
            // wsel_warpsel selects which 32-bit window of warp_active to return
            assign wactive_rdval = warp_active_arr[dselect_winsel*32 +: 32];
        end
    endgenerate


    ////////////////////////////////////////
    // WSTATUS register [read-only]

    // Warp status array (all warps on all cores)
    logic [NUM_WARPS_TOTAL-1:0] warp_status_arr;    // warp_status[n] = 1 means warp n is halted
    for(genvar cid=0; cid < NUM_CORES_TOTAL; cid++) begin: g_debug_core_status
        assign warp_status_arr[cid*NUM_WARPS +: NUM_WARPS] = dm_core_if[cid].warp_status;
    end

    logic [31:0] wstatus_rdval;
    generate
        if(NUM_WARPS_TOTAL < 32) begin: g_small_status
            // If total warps < 32, then ignore wsel_warpsel and return status of all warps
            assign wstatus_rdval = { {(32-NUM_WARPS_TOTAL){1'b0}}, warp_status_arr} ;
        end
        else begin: g_large_status
            // wsel_warpsel selects which 32-bit window of warp_status to return
            assign wstatus_rdval = warp_status_arr[dselect_winsel*32 +: 32];
        end
    endgenerate


    ////////////////////////////////////////
    // DCTRL register

    logic dctrl_we;
    assign dctrl_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DCTRL_ADDR));
    
    // Ungated version of dctrl_we for dmactive logic
    // When dmactive is low, only writes to dmactive bit should be considered
    logic dctrl_we_ungated;
    assign dctrl_we_ungated = (vxdbg_valid && vxdbg_we && (vxdbg_addr == DCTRL_ADDR));

    // dmactive logic
    always_ff @(posedge clk) begin
        if (reset) begin
            dmactive <= 1'b0;
        end else if (dctrl_we_ungated) begin
            dmactive <= vxdbg_wdata[31];
        end
    end

    logic dctrl_haltreq;
    logic dctrl_resumereq;
    logic dctrl_stepreq;
    logic dctrl_injreq;
    // enforce priority explictly
    assign dctrl_haltreq     = (dctrl_we && vxdbg_wdata[0]);
    assign dctrl_resumereq   = (dctrl_we && vxdbg_wdata[1]) && !dctrl_haltreq;
    assign dctrl_stepreq     = (dctrl_we && vxdbg_wdata[3]) && !dctrl_haltreq && !dctrl_resumereq;
    assign dctrl_injreq      = (dctrl_we && vxdbg_wdata[6]) && !dctrl_haltreq && !dctrl_resumereq && !dctrl_stepreq;
  
    // Ndmreset logic
    logic [NDMRESET_CTR_BITS-1:0] ndmreset_ctr;
    always_ff @(posedge clk) begin
        if (reset || !dmactive) begin
            ndmreset_ctr <= '0;
        end else if (dctrl_we && vxdbg_wdata[30]) begin
            ndmreset_ctr <= 1 << dconfig_ndmreset_log2cyc;
        end else if (ndmreset_ctr != 0) begin
            ndmreset_ctr <= ndmreset_ctr - 1'b1;
        end
    end
    assign ndmreset = dmactive && (ndmreset_ctr != 0);

    // resethaltreq logic
    logic                               resethaltreq_pending;
    logic [RESETHALTREQ_CTR_BITS-1:0]   resethaltreq_ctr;
    
    logic resethaltreq;
    assign resethaltreq = (resethaltreq_ctr != 0);
    always_ff @(posedge clk) begin
        if (reset || !dmactive) begin
            resethaltreq_pending <= 1'b0;
            resethaltreq_ctr <= '0;
        end 
        else begin
            if(resethaltreq_ctr != 0) begin
                resethaltreq_ctr <= resethaltreq_ctr - 1'b1;
            end
            if(resethaltreq_pending && ndmreset_ctr == 1) begin // next cycle ndmreset will go low
                resethaltreq_ctr <= 1 << dconfig_resethaltreq_log2cyc; // assert resethaltreq 
                resethaltreq_pending <= 1'b0;
            end
            else if(dctrl_we && vxdbg_wdata[2]) begin
                resethaltreq_pending <= 1'b1;
            end
        end
    end

    // Gather hacause from all cores
    logic [2:0] hacause_array [NUM_CORES_TOTAL];
    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin : g_hacause
        assign hacause_array[cid] = dm_core_if[cid].halt_cause;
    end

    // Gather step_state from all cores
    logic [1:0] step_state_array [NUM_CORES_TOTAL];
    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin : g_step
        assign step_state_array[cid] = dm_core_if[cid].step_state;
    end

    // Gather inject_state from all cores
    logic [1:0] inject_state_array [NUM_CORES_TOTAL];
    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin : g_inj_ack
        assign inject_state_array[cid] = dm_core_if[cid].inject_state;
    end

    // Selected core's hacause, step_state and inject_state
    logic [2:0] selected_hacause;
    logic [1:0] selected_inject_state;
    logic [1:0] selected_step_state;
    assign selected_hacause      = hacause_array[selected_core_id];
    assign selected_step_state   = step_state_array[selected_core_id];
    assign selected_inject_state = inject_state_array[selected_core_id];

    // Summary bits
    assign any_halted  = |warp_status_arr;
    assign all_halted  = &warp_status_arr;
    assign any_running = |(~warp_status_arr);
    assign all_running = &(~warp_status_arr);
    
    logic [31:0] dctrl_rdval;
    assign dctrl_rdval = {
        dmactive, 
        ndmreset,
        all_halted,
        any_halted,
        all_running,
        any_running,
        14'b0,
        selected_hacause,       // hacause of core to which warpsel_wid belongs
        selected_inject_state, // inject_state of core to which warpsel_wid belongs
        1'b0,
        selected_step_state,   // step_state of core to which warpsel_wid belongs
        1'b0,
        1'b0,
        1'b0,
        1'b0
    };

    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin: g_halt_resume
        // only assert halt_req/resume_req if any warp in this core is selected
        assign dm_core_if[cid].halt_req   = dmactive && (dctrl_haltreq || resethaltreq) && (|(warp_mask_arr[cid*NUM_WARPS +: NUM_WARPS]));
        assign dm_core_if[cid].resume_req = dmactive && dctrl_resumereq && (|(warp_mask_arr[cid*NUM_WARPS +: NUM_WARPS]));

        // Only assert step_req if the warpsel_wid belongs to this core
        assign dm_core_if[cid].step_req   = dmactive && dctrl_stepreq && (selected_core_id == cid);

        // Only assert inject_req if the warpsel_wid belongs to this core
        assign dm_core_if[cid].inject_req = dmactive && dctrl_injreq && (selected_core_id == cid);
    end


    /////////////////////////////////////////
    // DPC register (read-only)

    logic [`PC_BITS-1:0] dpc_array [NUM_CORES_TOTAL-1:0];
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dpc_rdmux
        assign dpc_array[i] = dm_core_if[i].dpc_rdat;
    end

    // DM: just pick the core, core will pick the warp internally
    logic [31:0] dpc_rdval;
    assign dpc_rdval = {dpc_array[selected_core_id], 1'b0};     // last bit is always 0 in RISC-V, vortex only stores PC[PC_BITS-1:1]

    logic dpc_we;
    assign dpc_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DPC_ADDR));
    for (genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin: g_dpc
        assign dm_core_if[cid].dpc_wdat = vxdbg_wdata[`PC_BITS:1];
        assign dm_core_if[cid].dpc_we   = dpc_we && (selected_core_id == cid);
    end


    /////////////////////////////////////////
    // DSCRATCH register

    logic [31:0] dscratch_array [NUM_CORES_TOTAL-1:0];
    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dscratch_rdmux
        assign dscratch_array[i] = dm_core_if[i].dscratch_rdat;
    end

    logic [31:0] dscratch_rdval;
    assign dscratch_rdval = dscratch_array[selected_core_id];

    logic dscratch_we;
    assign dscratch_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == DSCRATCH_ADDR));

    for (genvar i = 0; i < NUM_CORES_TOTAL; i++) begin: g_dscratch
        assign dm_core_if[i].dscratch_wdat = vxdbg_wdata;
        assign dm_core_if[i].dscratch_we   = dscratch_we && (selected_core_id == i);
    end


    ////////////////////////////////////////////////////////////////////////////////
    // Instruction Injection register
    logic inject_we;
    assign inject_we = dmactive && (vxdbg_valid && vxdbg_we && (vxdbg_addr == INJECT_ADDR));

    logic [`XLEN-1:0] inject_instr;

    logic [`XLEN-1:0] inject_rdval;
    assign inject_rdval = inject_instr;

    always_ff @(posedge clk) begin
        if (reset || !dmactive) begin
            inject_instr <= '0;
        end 
        else if(inject_we) begin
            inject_instr <= vxdbg_wdata;
        end
    end

    for(genvar cid = 0; cid < NUM_CORES_TOTAL; cid++) begin: g_inject_instr
        assign dm_core_if[cid].inject_instr = inject_instr;
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
                        PLATFORM_ADDR:  vxdbg_rdata <= platform_rdval;
                        DCONFIG_ADDR:   vxdbg_rdata <= dconfig_rdval;
                        DSELECT_ADDR:   vxdbg_rdata <= dselect_rdval;
                        WMASK_ADDR:     vxdbg_rdata <= wmask_rdval;
                        WACTIVE_ADDR:   vxdbg_rdata <= wactive_rdval;
                        WSTATUS_ADDR:   vxdbg_rdata <= wstatus_rdval;
                        DCTRL_ADDR:     vxdbg_rdata <= dctrl_rdval;
                        DPC_ADDR:       vxdbg_rdata <= dpc_rdval;
                        DSCRATCH_ADDR:  vxdbg_rdata <= dscratch_rdval;
                        INJECT_ADDR:    vxdbg_rdata <= inject_rdval;                       
                        default:        vxdbg_rdata <= 'd0;
                    endcase
                end
            end
        end
    end

    `UNUSED_VAR(vxdbg_wdata)

endmodule
