// Top level testbench contains the interface, DUT and test handles which
// can be used to start test components once the DUT comes out of reset. Or
// the reset can also be a part of the test class in which case all you need
// to do is start the test's run method.
module tb_top;
  
  vortex_wrapper_if vtx_intf();

  initial begin 
	vtx_intf.clk_rst_intf.clk = 0;
	vtx_intf.clk_rst_intf.rst = 0;
  end

  always #5 vtx_intf.clk_rst_intf.clk = ~vtx_intf.clk_rst_intf.clk;

  test basic_test(vtx_intf);
  
  VX_wrapper VX_wrapper_top (
		`SCOPE_IO_BIND  (1)

		.clk			(vtx_intf.clk_rst_intf.clk),
		.reset			(vtx_intf.clk_rst_intf.rst),

		.dcr_wr_valid	(vtx_intf.dcr_intf.dcr_wr_valid),
		.dcr_wr_addr	(vtx_intf.dcr_intf.dcr_wr_addr),
		.dcr_wr_data	(vtx_intf.dcr_intf.dcr_wr_data),

		.busy			(vtx_intf.busy)
	);
  
  //enabling the wave dump
  initial begin 
	$vcdpluson; 
	$vcdplusmemon;
    $dumpfile("dump.vcd"); 
	$dumpvars;
  end
endmodule
