module scan_cell (
    input  logic scan_in,
    input  logic phi,
    input  logic phi_bar,
    input  logic capture,
    input  logic update,
    input  logic chip_data_out,
    output logic chip_data_in,
    output logic scan_out
);

    logic int_data;

    always_latch begin
        if (update) chip_data_in = int_data;
        else chip_data_in = chip_data_in;
    end

    always_latch begin
        if (phi) int_data = scan_in;
        else int_data = int_data;
    end

    always_latch begin
        if (phi_bar) scan_out = (capture) ? chip_data_out : int_data;
        else scan_out = scan_out;
    end
endmodule // scan_cell
