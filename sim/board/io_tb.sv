`timescale 1ns/1ps
module io_tb;
    reg clk=0, initialize=1, request=0, writing=0, sound_read=0;
    always #5 clk=~clk;
    reg [23:0] address=0;
    reg [15:0] data=0;
    reg [1:0] bytes=3;
    wire valid, sound_write, pending, gga_write, configure, twice;
    wire [15:0] reply, flags;
    wire [8:0] y0,x0,y1,x1;
    wire [5:0] count, priority_point;
    wire [7:0] command, gga_data, gga_view;
    wire [3:0] selected,gga_address;
    reg [3:0] view_address=0;
    int checks=0;
    rabbitpunch_io dut(
        .i_clk(clk),.i_initialize(initialize),.i_request(request),.i_request_write(writing),
        .iu24_request_address(address),.iu16_request_data(data),.iu2_request_bytes(bytes),
        .o_response_valid(valid),.ou16_response_data(reply),
        .iu8_player1(8'h15),.iu8_player2(8'h2a),.iu8_service(8'h51),.iu16_dips(16'ha539),
        .i_sound_command_read(sound_read),.o_sound_command_write(sound_write),
        .ou8_sound_command(command),.o_sound_pending(pending),.ou16_video_flags(flags),
        .ou9_scroll0_y(y0),.ou9_scroll0_x(x0),.ou9_scroll1_y(y1),.ou9_scroll1_x(x1),
        .ou6_sprite_count(count),.ou6_sprite_priority(priority_point),
        .ou4_gga_selected(selected),.iu4_gga_view_address(view_address),.ou8_gga_view_data(gga_view),
        .o_gga_write(gga_write),.ou4_gga_write_address(gga_address),.ou8_gga_write_data(gga_data),
        .o_irq_configure(configure),.o_irq_twice_per_frame(twice)
    );
    task access(input bit wr,input [23:0] addr,input [1:0] lanes,input [15:0] value,input [15:0] expected);
        @(negedge clk); request=1;writing=wr;address=addr;bytes=lanes;data=value;
        @(posedge clk); #1;
        if(!valid || (!wr && reply!==expected)) $fatal(1,"IO access %h got %h expected %h",addr,reply,expected);
        checks++;
        @(negedge clk); request=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); initialize=0;
        access(0,'hc0018,3,0,16'h5115);
        access(0,'hc001a,3,0,16'h512a);
        access(0,'h1c001c,3,0,16'ha539);
        access(0,'hc000c,3,0,16'hffff);
        access(1,'hc000c,3,16'ha55a,0);
        access(1,'hc000c,2,16'h1200,0);
        access(1,'hc000d,1,16'h0034,0);
        if(flags!==16'h1234) $fatal(1,"flag byte merge");
        access(1,'hc0000,3,16'hf123,0);
        access(1,'hc0000,1,16'h0055,0);
        access(1,'hc0002,3,16'hf234,0);
        access(1,'hc0004,3,16'hf345,0);
        access(1,'hc0006,3,16'hf456,0);
        if(y0!==9'h123 || x0!==9'h034 || y1!==9'h145 || x1!==9'h056) $fatal(1,"scroll mapping/mask/byte-only write");
        access(1,'hc0010,3,16'hffff,0);
        access(1,'hc0012,1,16'h0061,0);
        access(1,'hc0010,2,16'h0000,0);
        if(count!==6'h3f || priority_point!==6'h21) $fatal(1,"sprite mask or upper-lane filtering");
        for(int index=0;index<16;index++) begin
            access(1,'hc0029,1,16'h00f0+index,0);
            access(1,'hc0009,1,16'h0040+index,0);
            if(!gga_write || gga_address!==index[3:0] || gga_data!==8'h40+index || selected!==index[3:0])
                $fatal(1,"GGA select/write mismatch");
            view_address=index; #1;
            if(gga_view!==8'h40+index) $fatal(1,"GGA state readback");
        end
        access(1,'hc0029,1,16'h001b,0);
        access(1,'hc0009,1,16'h00c0,0);
        if(!configure || !twice) $fatal(1,"double IRQ configuration");
        access(1,'hc0009,1,16'h0060,0);
        if(!configure || twice) $fatal(1,"single IRQ configuration");
        access(0,'hc001e,3,0,0);
        access(1,'hc000f,1,16'h0042,0);
        if(!pending || !sound_write || command!==8'h42) $fatal(1,"sound latch write");
        access(0,'hc001e,3,0,1);
        @(negedge clk); sound_read=1;
        @(negedge clk); sound_read=0;
        access(0,'hc001e,3,0,0);
        @(negedge clk); request=1;writing=1;address='hc000e;bytes=1;data='h55;sound_read=1;
        @(posedge clk); #1;
        if(!pending || command!==8'h55) $fatal(1,"new command lost during consume");
        @(negedge clk);request=0;sound_read=0;
        @(posedge clk); #1;
        if(valid || sound_write || gga_write || configure) $fatal(1,"pulse held too long");
        $display("IO_PASS: byte lanes, scrolls, inputs, GGA state, IRQ mode, sound mailbox; accesses=%0d",checks);
        $finish;
    end
endmodule
