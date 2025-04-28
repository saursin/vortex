module sram_wrapper_512x16384 (
`ifdef USE_POWER_PINS
    vdd,
    gnd,
`endif
    clk,
    csb,
    web,
    wmask,
    addr,
    din,
    dout
);

parameter WRAPPER_DATA_WIDTH = 512;
parameter WRAPPER_ADDR_WIDTH = 14;
parameter WRAPPER_NUM_BYTES = WRAPPER_DATA_WIDTH / 8;  // 64 bytes
parameter NUM_BANKS = 4;
parameter BANK_SEL_WIDTH = 2;
parameter TOTAL_SRAMS = NUM_BANKS * WRAPPER_NUM_BYTES; 

`ifdef USE_POWER_PINS
    inout vdd;
    inout gnd;
`endif
input                       clk;
input                       csb;
input                       web;
input [WRAPPER_NUM_BYTES-1:0] wmask;
input [WRAPPER_ADDR_WIDTH-1:0] addr;
input [WRAPPER_DATA_WIDTH-1:0] din;
output [WRAPPER_DATA_WIDTH-1:0] dout;

wire [BANK_SEL_WIDTH-1:0] bank_sel = addr[13:12];
wire [11:0] bank_addr = addr[11:0];

// Bank chip select signals
wire [NUM_BANKS-1:0] bank_csb;
assign bank_csb[0] = csb || (bank_sel != 2'b00);
assign bank_csb[1] = csb || (bank_sel != 2'b01);
assign bank_csb[2] = csb || (bank_sel != 2'b10);
assign bank_csb[3] = csb || (bank_sel != 2'b11);

// Array to collect outputs from each bank
wire [7:0] bank_byte_dout [NUM_BANKS-1:0][WRAPPER_NUM_BYTES-1:0];
wire [WRAPPER_DATA_WIDTH-1:0] bank_dout [NUM_BANKS-1:0];

sram_8_4096_rw_freepdk45 #(.VERBOSE(0)) sram_array [TOTAL_SRAMS-1:0] ();

generate
    // Iterate over banks and bytes using genvars
    for (genvar bank = 0; bank < NUM_BANKS; bank++) begin : bank_gen
        for (genvar byte_idx = 0; byte_idx < WRAPPER_NUM_BYTES; byte_idx++) begin : byte_gen
            // Calculate SRAM index from bank and byte
            localparam sram_idx = bank * WRAPPER_NUM_BYTES + byte_idx;
            
            // Individual port connections
            assign sram_array[sram_idx].clk0   = clk;
            assign sram_array[sram_idx].csb0   = bank_csb[bank];
            assign sram_array[sram_idx].web0   = web;
            assign sram_array[sram_idx].wmask0 = {8{wmask[byte_idx]}};
            assign sram_array[sram_idx].addr0  = bank_addr;
            assign sram_array[sram_idx].din0   = din[byte_idx*8 +: 8];
            assign bank_byte_dout[bank][byte_idx] = sram_array[sram_idx].dout0;

            `ifdef USE_POWER_PINS
                assign sram_array[sram_idx].vdd = vdd;
                assign sram_array[sram_idx].gnd = gnd;
            `endif
        end

        // Build final bank output
        for (genvar byte_idx = 0; byte_idx < WRAPPER_NUM_BYTES; byte_idx++) begin : bank_out
            assign bank_dout[bank][byte_idx*8 +: 8] = bank_byte_dout[bank][byte_idx];
        end
    end
endgenerate

// Output multiplexer based on bank selection
assign dout = bank_dout[bank_sel];

endmodule