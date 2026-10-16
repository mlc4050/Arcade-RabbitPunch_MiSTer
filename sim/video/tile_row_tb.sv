`timescale 1ns/1ps
module tile_row_tb;
    reg clk=0, reset=1, row_valid=0, foreground=0;
    reg [13:0] code=0;
    reg [2:0] row=0;
    reg [8:0] origin=0;
    reg [8:0] destination_y=0;
    reg [3:0] palette=0;
    wire ready, request, pixel_valid, opaque, rom_foreground;
    wire [16:0] address;
    wire [8:0] pixel_x, pixel_y, index;
    reg response_valid=0;
    reg [31:0] response_data=0;
    integer latency=0, remaining=0, pixels=0, trials=0, requests=0, total_pixels=0;
    reg pending=0, checking=0;
    reg [16:0] saved_address;
    integer expected_code, expected_row, expected_origin, expected_palette;
    integer expected_y;
    reg expected_foreground;
    always #5 clk=~clk;

    rabbitpunch_tile_row dut(
        .i_clk(clk), .i_reset(reset), .i_row_valid(row_valid), .o_row_ready(ready),
        .iu14_tile_code(code), .iu3_tile_row(row), .iu9_pixel_x(origin), .iu9_pixel_y(destination_y),
        .iu4_palette(palette), .i_foreground(foreground), .o_rom_request(request),
        .ou17_rom_word_address(address), .o_rom_foreground(rom_foreground),
        .i_rom_response_valid(response_valid), .iu32_rom_response_data(response_data),
        .o_pixel_valid(pixel_valid), .ou9_pixel_x(pixel_x), .ou9_pixel_y(pixel_y),
        .ou9_palette_index(index), .o_opaque(opaque));

    function automatic integer pen(input integer c, r, p);
        pen=(c+3*r+p)&15;
    endfunction
    function automatic [31:0] packed_row(input [16:0] a);
        integer p;
        begin
            packed_row=0;
            for (p=0;p<8;p=p+1)
                packed_row=packed_row|(pen(a>>3,a&7,p)<<(p*4));
        end
    endfunction
    always @(posedge clk) begin
        response_valid<=0;
        if (request) begin
            if (pending) $fatal(1,"Overlapping tile ROM requests");
            if (address !== ((expected_code<<3)|expected_row))
                $fatal(1,"Tile ROM address %x expected code=%x row=%0d",address,expected_code,expected_row);
            if (rom_foreground !== expected_foreground) $fatal(1,"Wrong graphics ROM bank");
            saved_address<=address;
            remaining<=latency;
            pending<=1;
            requests=requests+1;
        end else if (pending) begin
            if (remaining==0) begin
                response_valid<=1;
                response_data<=packed_row(saved_address);
                pending<=0;
            end else remaining<=remaining-1;
        end
        if (pixel_valid) begin
            if (!checking || reset) $fatal(1,"Unexpected pixel after reset/abort");
            if (pixels>=8 || pixel_x!==((expected_origin+pixels)&511) || pixel_y!==expected_y ||
                index!==((expected_foreground?256:0)+(expected_palette<<4)+pen(expected_code,expected_row,pixels)) ||
                opaque!==(expected_foreground && pen(expected_code,expected_row,pixels)==15 ? 1'b0:1'b1))
                $fatal(1,"Tile pixel %0d x=%0d index=%x opaque=%b",pixels,pixel_x,index,opaque);
            pixels=pixels+1;
            total_pixels=total_pixels+1;
        end
    end

    task begin_row(input integer c,r,x,p,fg,d);
        begin
            wait(ready);
            @(negedge clk);
            expected_code=c; expected_row=r; expected_origin=x;
            expected_palette=p; expected_foreground=fg;
            expected_y=(c+r+p)&511;
            code=c; row=r; origin=x; palette=p; foreground=fg;
            destination_y=expected_y;
            latency=d; pixels=0; checking=1; row_valid=1;
            @(negedge clk);
            row_valid=0;
            // The accepted row must not follow changing upstream metadata.
            code=~c; row=~r; origin=~x; palette=~p; foreground=!fg;
            destination_y=~expected_y;
        end
    endtask
    task trial(input integer c,r,x,p,fg,d);
        integer before_requests;
        begin
            before_requests=requests;
            begin_row(c,r,x,p,fg,d);
            // Extra valid pulses while busy must not start another row.
            row_valid=1;
            repeat(2) @(negedge clk);
            row_valid=0;
            wait(ready);
            @(negedge clk);
            if (pixels!=8 || requests!=before_requests+1)
                $fatal(1,"Tile burst pixels=%0d requests=%0d",pixels,requests-before_requests);
            checking=0;
            trials=trials+1;
        end
    endtask

    integer c,r,p,fg,d;
    integer codes[0:5]='{0,1,8191,8192,12287,16383};
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        for (c=0;c<6;c=c+1)
            for (r=0;r<8;r=r+1)
                for (p=0;p<16;p=p+1)
                    for (fg=0;fg<2;fg=fg+1)
                        for (d=0;d<3;d=d+1)
                            trial(codes[c],r,(p&1)?508:32,p,fg,d==0?0:d==1?3:11);

        begin_row(123,5,40,7,1,20);
        wait(pending);
        @(negedge clk); reset=1; checking=0;
        repeat(2) @(negedge clk);
        reset=0;
        wait(ready);
        if (pending) $fatal(1,"Ready before stale ROM response was drained");
        trial(456,6,508,3,0,0);

        begin_row(123,4,20,5,1,0);
        wait(pixels==2);
        @(negedge clk); reset=1; checking=0;
        repeat(3) @(negedge clk);
        reset=0;
        trial(234,2,508,15,1,3);

        // Reset before the first external ROM request is accepted.
        begin_row(12,1,0,0,0,0);
        reset=1; checking=0;
        repeat(3) @(negedge clk);
        reset=0;
        trial(34,7,32,1,0,11);

        $display("TILE_ROW_PASS: %0d rows, %0d pixels; byte order, palettes, wrap, wait states and reset",trials,total_pixels);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Tile-row timeout");
    end
endmodule
