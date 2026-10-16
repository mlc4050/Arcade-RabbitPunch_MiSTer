`timescale 1ns/1ps
module irq_tb;
    reg clk=0,initialize=1,configure=0,twice=0,vblank=0,half_frame=0,ack=0;
    always #5 clk=~clk;
    wire pending;
    rabbitpunch_irq dut(.i_clk(clk),.i_initialize(initialize),.i_configure(configure),
        .i_twice_per_frame(twice),.i_vblank_start(vblank),.i_half_frame(half_frame),
        .i_acknowledge(ack),.o_level1_pending(pending));
    task tick(input bit conf,two,vb,hf,acknowledge,expected);
        @(negedge clk);configure=conf;twice=two;vblank=vb;half_frame=hf;ack=acknowledge;
        @(posedge clk);#1;
        if(pending!==expected) $fatal(1,"IRQ state mismatch conf=%b two=%b vb=%b half=%b ack=%b got=%b",conf,two,vb,hf,acknowledge,pending);
    endtask
    initial begin
        repeat(3) @(negedge clk);initialize=0;
        tick(0,0,1,1,0,0); // Disabled until GGA configuration.
        tick(1,1,0,0,0,0);
        tick(0,0,0,1,0,0); // First interrupt waits for vblank.
        tick(0,0,1,0,0,1);
        tick(0,0,0,0,0,1); // HOLD_LINE semantics, not a one-cycle IRQ.
        tick(0,0,0,0,1,0);
        tick(0,0,0,1,0,1);
        tick(0,0,0,0,1,0);
        tick(1,0,0,1,0,0); // Rearm supersedes half-frame event.
        tick(0,0,0,1,0,0);
        tick(0,0,1,0,0,1);
        tick(0,0,0,0,1,0);
        tick(0,0,0,1,0,0); // Single-per-frame mode.
        tick(0,0,1,0,1,1); // New event wins over simultaneous acknowledge.
        tick(1,1,0,0,0,1); // Reconfigure does not clear held CPU IRQ.
        tick(0,0,0,0,1,0);
        tick(0,0,0,1,0,0);
        tick(0,0,1,0,0,1);
        @(negedge clk);initialize=1;
        @(posedge clk);#1;if(pending) $fatal(1,"IRQ initialization");
        $display("IRQ_PASS: first-vblank arming, one/two per frame, hold/ack, rearm and coincident event");
        $finish;
    end
endmodule
