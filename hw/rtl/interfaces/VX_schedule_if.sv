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

interface VX_schedule_if ();

    typedef struct packed {
        logic [`UUID_WIDTH-1:0]     uuid;
        logic [`NW_WIDTH-1:0]       wid;
        logic [`NUM_THREADS-1:0]    tmask;
        logic [`PC_BITS-1:0]        PC;
    } data_t;

    logic  valid;
    data_t data;
    logic  ready;

`ifdef EN_VXDBG
    logic                    inject_req;
    logic [`NW_WIDTH-1:0]    inject_wid;
    logic [`NT_WIDTH-1:0]    inject_tid;
    logic [`XLEN-1:0]        inject_instr;   
    logic [1:0]              inject_state;
    logic                    inject_committed;
`endif

    modport master (
        output valid,
        output data,
        input  ready
    
`ifdef EN_VXDBG
        ,
        output inject_req,
        output inject_wid,
        output inject_tid,
        output inject_instr,
        input  inject_state,
        output inject_committed
`endif
    );

    modport slave (
        input  valid,
        input  data,
        output ready

`ifdef EN_VXDBG
        ,
        input  inject_req,
        input  inject_wid,
        input  inject_tid,
        input  inject_instr,
        output inject_state,
        input  inject_committed
`endif
    );

endinterface
