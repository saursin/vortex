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
    // Warp status bits
    logic [NUM_WARPS-1:0]  warp_active;     // Warp is active
    logic [NUM_WARPS-1:0]  warp_status;     // Current status of all warps
    logic [NUM_WARPS-1:0]  warp_mask;       // Warp mask for halt/resume operations
    logic                  halt_req;        // Request to halt selected warps
    logic                  resume_req;      // Request to resume selected warps

    // Selected warp and thread for debug operations
    logic [`NW_BITS-1:0]   sel_wid;         // Selected warp id
    logic [`NT_BITS-1:0]   sel_tid;         // Selected thread id

    logic                  step_req;        // step request for selected warp
    logic [1:0]            step_state;      // state of step request for selected warp
    logic [2:0]            halt_cause;      // halt cause for selected warp

    // Debug PC
    logic [`PC_BITS-1:0]   dpc_rdat;        // current PC of the warp being debugged
    logic [`PC_BITS-1:0]   dpc_wdat;        // new PC to be written to the warp being debugged
    logic                  dpc_we;          // write enable for dpc_wdat

    // Instruction injection
    logic                  inject_req;      // request to inject instruction in warp selected by sel_wid with thread mask generated from sel_tid
    logic [1:0]            inject_state;    // state of instruction injection
    logic [`XLEN-1:0]      inject_instr;    // instruction to be injected

    logic                  ebreak_halt;

    // Debug CSRs  for warp selected by sel_wid
    wire [`XLEN-1:0]       dscratch_rdat;   // read data from debug scratch register
    wire [`XLEN-1:0]       dscratch_wdat;   // write data to debug scratch register
    wire                   dscratch_we;     // write enable for debug scratch register

    modport master (
        input  warp_active,
        input  warp_status,
        output warp_mask,
        output halt_req,
        output resume_req,
        output sel_wid,
        output sel_tid,
        output step_req,
        input  step_state,
        input  halt_cause,
        input  dpc_rdat,
        output dpc_wdat,
        output dpc_we,
        output inject_req,
        input  inject_state,
        output inject_instr,
        output ebreak_halt,
        input  dscratch_rdat,
        output dscratch_wdat,
        output dscratch_we
    );

    modport slave (
        output warp_active,
        output warp_status,
        input  warp_mask,
        input  halt_req,
        input  resume_req,
        input  sel_wid,
        input  sel_tid,
        input  step_req,
        output step_state,
        output halt_cause,
        output dpc_rdat,
        input  dpc_wdat,
        input  dpc_we,
        input  inject_req,
        output inject_state,
        input  inject_instr,
        input  ebreak_halt,
        output dscratch_rdat,
        input  dscratch_wdat,
        input  dscratch_we
    );

endinterface
