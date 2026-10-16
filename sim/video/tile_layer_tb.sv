`timescale 1ns/1ps
module tile_layer_tb;
    reg clk=0, reset=1, valid=0, foreground=0;
    reg [8:0] x=0,y=0,scroll_x=0,scroll_y=0;
    reg [15:0] flags=0;
    wire ready, ram_request, rom_request, rom_foreground, pixel_valid, opaque;
    wire [12:0] ram_address;
    wire [16:0] rom_address;
    wire [8:0] pixel_x,pixel_y,palette_index;
    reg ram_valid=0,rom_valid=0,ram_pending=0,rom_pending=0;
    reg [15:0] ram_data=0;
    reg [31:0] rom_data=0;
    reg [12:0] saved_ram_address;
    reg [16:0] saved_rom_address;
    reg saved_foreground;
    integer ram_delay=0,rom_delay=0,force_ram_delay=-1,force_rom_delay=-1;
    integer accepted=0,completed=0,ram_requests=0,rom_requests=0,pixels=0;
    integer expected_address[0:16383],expected_code[0:16383],expected_row[0:16383];
    integer expected_x[0:16383],expected_y[0:16383],expected_palette[0:16383];
    bit expected_foreground[0:16383];
    integer sx,sy,entry,source_flags,code_bank,color_bank;
    always #5 clk=~clk;

    rabbitpunch_tile_layer dut(
        .i_clk(clk),.i_reset(reset),.i_request_valid(valid),.o_request_ready(ready),
        .iu9_pixel_x(x),.iu9_pixel_y(y),.iu9_scroll_x(scroll_x),.iu9_scroll_y(scroll_y),
        .iu16_video_flags(flags),.i_foreground(foreground),
        .o_ram_request(ram_request),.ou13_ram_word_address(ram_address),
        .i_ram_response_valid(ram_valid),.iu16_ram_response_data(ram_data),
        .o_rom_request(rom_request),.ou17_rom_word_address(rom_address),.o_rom_foreground(rom_foreground),
        .i_rom_response_valid(rom_valid),.iu32_rom_response_data(rom_data),
        .o_pixel_valid(pixel_valid),.ou9_pixel_x(pixel_x),.ou9_pixel_y(pixel_y),
        .ou9_palette_index(palette_index),.o_opaque(opaque));

    function automatic [15:0] descriptor(input integer address);
        descriptor=(address*16'h9e37)^16'hb123;
    endfunction
    function automatic integer pen(input integer c,r,p,fg);
        pen=(c+3*r+p+5*fg)&15;
    endfunction
    function automatic [31:0] packed_row(input [16:0] address,input bit fg);
        integer p;
        begin
            packed_row=0;
            for(p=0;p<8;p=p+1)
                packed_row=packed_row|(pen(address>>3,address&7,p,fg)<<(4*p));
        end
    endfunction
    always @(posedge clk) begin
        if(reset) begin
            accepted=0;completed=0;ram_requests=0;rom_requests=0;pixels=0;
        end else begin
            if(valid && ready) begin
                if(accepted>=16384) $fatal(1,"Expected-row queue overflow");
                sx=(x+scroll_x)&511;sy=(y+scroll_y)&511;
                expected_address[accepted]=foreground*4096+(sx/8)*64+sy/8;
                entry=descriptor(expected_address[accepted]);
                code_bank=flags&(foreground?16'h0800:16'h0400);
                color_bank=flags&(foreground?16'h0020:16'h0010);
                expected_code[accepted]=code_bank?((entry&4095)|8192):(entry&8191);
                expected_palette[accepted]=(color_bank?8:0)|(entry>>13);
                expected_row[accepted]=sy%8;
                expected_x[accepted]=(x-sx%8)&511;
                expected_y[accepted]=y;
                expected_foreground[accepted]=foreground;
                accepted=accepted+1;
            end
            if(ram_request) begin
                if(ram_address!==expected_address[ram_requests])
                    $fatal(1,"Column-major tile address %x expected %x",ram_address,expected_address[ram_requests]);
                ram_requests=ram_requests+1;
            end
            if(rom_request) begin
                if(rom_address!==((expected_code[rom_requests]<<3)|expected_row[rom_requests]) ||
                    rom_foreground!==expected_foreground[rom_requests])
                    $fatal(1,"Tile code/row/ROM bank mismatch at row %0d",rom_requests);
                rom_requests=rom_requests+1;
            end
            if(pixel_valid) begin
                if(completed>=accepted || pixel_x!==((expected_x[completed]+pixels)&511) ||
                    pixel_y!==expected_y[completed] ||
                    palette_index!==(expected_foreground[completed]*256+expected_palette[completed]*16+
                        pen(expected_code[completed],expected_row[completed],pixels,expected_foreground[completed])) ||
                    opaque!==(expected_foreground[completed] &&
                        pen(expected_code[completed],expected_row[completed],pixels,expected_foreground[completed])==15?1'b0:1'b1))
                    $fatal(1,"Tile pipeline row %0d pixel %0d: x=%0d y=%0d index=%x opaque=%b",
                        completed,pixels,pixel_x,pixel_y,palette_index,opaque);
                pixels=pixels+1;
                if(pixels==8) begin
                    pixels=0;
                    completed=completed+1;
                end
            end
        end
    end
    // Neither external responder discards an accepted request during reset.
    always @(posedge clk) begin
        ram_valid<=0;
        if(ram_request) begin
            if(ram_pending) $fatal(1,"Overlapping tile RAM requests");
            ram_pending<=1;saved_ram_address<=ram_address;
            ram_delay<=force_ram_delay>=0?force_ram_delay:(ram_address%3==0?0:ram_address%3==1?3:11);
        end else if(ram_pending) begin
            if(ram_delay==0) begin
                ram_pending<=0;ram_valid<=1;ram_data<=descriptor(saved_ram_address);
            end else ram_delay<=ram_delay-1;
        end
        rom_valid<=0;
        if(rom_request) begin
            if(rom_pending) $fatal(1,"Overlapping tile ROM requests");
            rom_pending<=1;saved_rom_address<=rom_address;saved_foreground<=rom_foreground;
            rom_delay<=force_rom_delay>=0?force_rom_delay:(rom_address%3==0?0:rom_address%3==1?3:11);
        end else if(rom_pending) begin
            if(rom_delay==0) begin
                rom_pending<=0;rom_valid<=1;rom_data<=packed_row(saved_rom_address,saved_foreground);
            end else rom_delay<=rom_delay-1;
        end
    end
    task send(input integer px,py,dx,dy,vf,fg);
        begin
            wait(ready);
            @(negedge clk);
            x=px;y=py;scroll_x=dx;scroll_y=dy;flags=vf;foreground=fg;valid=1;
            @(negedge clk);valid=0;
            x=~px;y=~py;scroll_x=~dx;scroll_y=~dy;flags=~vf;foreground=!fg;
        end
    endtask
    integer fg,col,r,dx,dy,vf,i;
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        for(fg=0;fg<2;fg=fg+1)
            for(col=0;col<64;col=col+1)
                for(r=0;r<64;r=r+1) begin
                    dx=(col*31+r*7)&511;dy=(col*17+r*29)&511;
                    vf=((col&1)?16'h400:0)|((col&2)?16'h800:0)|((r&1)?16'h10:0)|((r&2)?16'h20:0);
                    send((col*8+r%8-dx)&511,(r*8+col%8-dy)&511,dx,dy,vf,fg);
                end
        wait(completed==8192);
        if(accepted!=8192 || ram_requests!=8192 || rom_requests!=8192)
            $fatal(1,"Missing or repeated tile transactions");

        // Abort a drawing row and its prefetched descriptor together. The RAM
        // reply returns first; new RAM work may queue while the old ROM drains.
        force_ram_delay=0;force_rom_delay=100;
        send(13,19,3,5,16'h430,0);
        wait(rom_pending);
        force_ram_delay=20;
        send(511,511,7,9,16'hc30,1);
        wait(ram_pending);
        if(!rom_pending) $fatal(1,"Reset case did not overlap RAM and ROM requests");
        @(negedge clk);reset=1;
        repeat(3) @(negedge clk);
        reset=0;
        wait(ready);
        if(ram_pending) $fatal(1,"Lookup accepted input before stale RAM reply drained");
        force_ram_delay=-1;force_rom_delay=-1;
        for(i=0;i<64;i=i+1)
            send((i*7)&511,(i*13)&511,(i*11)&511,(i*3)&511,(i&1)?16'hc30:0,i&1);
        wait(completed==64);
        if(accepted!=64 || ram_requests!=64 || rom_requests!=64)
            $fatal(1,"Post-reset tile transaction mismatch");
        $display("TILE_LAYER_PASS: 8256 queued rows, 66048 pixels; every tilemap address, banks, scroll wrap, delays and reset");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Tile-layer timeout accepted=%0d completed=%0d",accepted,completed);
    end
endmodule
