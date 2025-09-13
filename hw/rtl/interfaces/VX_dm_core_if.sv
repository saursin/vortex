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

`include "VX_define.vh"

interface VX_dm_core_if #(
    parameter NUM_WARPS = `NUM_WARPS
);

    logic [NUM_WARPS-1:0]  warp_status;
    logic [NUM_WARPS-1:0]  warp_mask;
    logic                  halt_req;
    logic                  resume_req;

    logic [`CLOG2(NUM_WARPS)-1:0]   wsel_wid;   // Selected warp id

    logic                           step_req;   // step request for selected warp
    logic [1:0]                     step_state; // state of step request for selected warp

    logic [`PC_BITS-1:0]          dpc_rdat;   // current PC of the warp being debugged
    logic [`PC_BITS-1:0]          dpc_wdat;   // new PC to be written to the warp being debugged
    logic                         dpc_we;     // write enable for dpc_wdat

    // Debug CSRs (selected by wsel_wid)
    wire [`XLEN-1:0]              dscratch_rdat;    
    wire [`XLEN-1:0]              dscratch_wdat;
    wire                          dscratch_we;

    modport master (
        input  warp_status,
        output warp_mask,
        output halt_req,
        output resume_req,
        output wsel_wid,
        output step_req,
        input  step_state,
        input  dpc_rdat,
        output dpc_wdat,
        output dpc_we,
        input  dscratch_rdat,
        output dscratch_wdat,
        output dscratch_we
    );

    modport slave (
        output warp_status,
        input  warp_mask,
        input  halt_req,
        input  resume_req,
        input  wsel_wid,
        input  step_req,
        output step_state,
        output dpc_rdat,
        input  dpc_wdat,
        input  dpc_we,
        output dscratch_rdat,
        input  dscratch_wdat,
        input  dscratch_we
    );

endinterface
