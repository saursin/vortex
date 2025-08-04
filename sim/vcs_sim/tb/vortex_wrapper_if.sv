interface vortex_wrapper_if;
    clk_rst_if clk_rst_intf();
    dcr_if dcr_intf();
    scan_if scan_intf();
    logic busy; 
endinterface