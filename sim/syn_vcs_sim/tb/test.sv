program test(vortex_wrapper_if intf);
  
  //declaring environment instance
  environment env;
  
  initial begin
    //creating environment
    env = new(intf);
    
    env.run();
  end
endprogram