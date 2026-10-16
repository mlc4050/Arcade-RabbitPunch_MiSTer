`timescale 1ns/1ps
module bitmap_tb;
    reg clk=0,reset=1,pixel_valid=0;
    always #5 clk=~clk;
    reg [8:0] x=0;
    reg [7:0] y=0;
    reg [15:0] flags=0;
    wire ready,ram_request,valid,opaque;
    wire [14:0] ram_address;
    wire [8:0] out_x;
    wire [7:0] out_y;
    wire [9:0] palette_index;
    reg ram_valid=0;
    reg [15:0] ram_data=0;
    bit pending=0;
    int remaining,delay_cycles=0,checks=0,requests=0;
    reg [14:0] captured_address;
    reg [14:0] expected_address;
    rabbitpunch_bitmap dut(.i_clk(clk),.i_reset(reset),.i_pixel_valid(pixel_valid),.o_pixel_ready(ready),
        .iu9_pixel_x(x),.iu8_pixel_y(y),.iu16_video_flags(flags),
        .o_ram_request(ram_request),.ou15_ram_word_address(ram_address),
        .i_ram_response_valid(ram_valid),.iu16_ram_response_data(ram_data),
        .o_pixel_valid(valid),.ou9_pixel_x(out_x),.ou8_pixel_y(out_y),
        .ou10_palette_index(palette_index),.o_opaque(opaque));
    function [15:0] memory_word(input int addr);
        for(int n=0;n<4;n++) memory_word[15-4*n-:4]=(addr+n)&15;
    endfunction
    always @(posedge clk) begin
        ram_valid<=0;
        if(ram_request) begin
            if(pending)$fatal(1,"overlapping bitmap requests");
            if(ram_address!==expected_address)$fatal(1,"bitmap word address %h expected %h",ram_address,expected_address);
            pending=1;remaining=delay_cycles;captured_address=ram_address;requests++;
        end else if(pending) begin
            if(remaining>0)remaining--;
            else begin ram_data<=memory_word(captured_address);ram_valid<=1;pending=0;end
        end
    end
    task pixel(input int px,py,bank);
        int pen,timeout_cycles;
        while(!ready) @(negedge clk);
        @(negedge clk);x=px;y=py;flags=bank;pixel_valid=1;
        expected_address=(py*512+((px+4)&511))/4;
        delay_cycles=(checks%3==0)?0:((checks%3==1)?3:11);
        @(negedge clk);pixel_valid=0;
        // Change the inputs while waiting: output metadata must come from acceptance.
        x=0;y=0;flags='hffff;
        timeout_cycles=0;
        while(!valid && timeout_cycles<100)begin @(negedge clk);timeout_cycles++;end
        pen=(expected_address+((px+4)&3))&15;
        if(!valid || out_x!==px[8:0] || out_y!==py[7:0] ||
           palette_index!==(512+bank*16+pen) || opaque!==(pen!=15))
            $fatal(1,"pixel (%0d,%0d) bank=%0d index=%h pen=%0d opaque=%b",px,py,bank,palette_index,pen,opaque);
        checks++;
        @(negedge clk);if(valid)$fatal(1,"pixel valid held");
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;
        for(int py=0;py<256;py++)
            for(int px=0;px<512;px++) pixel(px,py,(px^py)&15);
        @(negedge clk);x=5;y=7;flags=3;pixel_valid=1;delay_cycles=30;
        expected_address=(7*512+9)/4;
        @(negedge clk);pixel_valid=0;
        wait(pending);@(negedge clk);reset=1;
        repeat(2)@(negedge clk);reset=0;
        do begin @(negedge clk);if(valid)$fatal(1,"reset leaked stale pixel");end while(!ready);
        pixel(511,255,15);
        if(requests!=checks+1)$fatal(1,"request count does not include exactly one canceled fetch");
        $display("BITMAP_PASS: 131072 coordinates, all palette banks/pens, nibble order, x wrap, metadata, delays and reset drain; pixels=%0d",checks);
        $finish;
    end
    initial begin #40ms;$fatal(1,"TIMEOUT checks=%0d",checks);end
endmodule
