`timescale 1ns/1ps
module tile_capture_tb;
    reg clk=0,reset=1,valid=0,foreground=0;
    reg [8:0] x=0,y=0,scroll_x=0,scroll_y=0;
    reg [15:0] flags=0;
    wire ready,ram_request,rom_request,rom_foreground,pixel_valid,opaque;
    wire [12:0] ram_address;
    wire [16:0] rom_address;
    wire [8:0] pixel_x,pixel_y,palette_index;
    reg ram_valid=0,rom_valid=0,ram_pending=0,rom_pending=0;
    reg [15:0] ram_data=0;
    reg [31:0] rom_data=0;
    reg [12:0] saved_ram_address;
    reg [16:0] saved_rom_address;
    reg saved_foreground;
    reg [15:0] vram[0:8191],settings[0:4];
    reg [31:0] tiles0[0:131071],tiles1[0:131071];
    reg [9:0] expected_pixels[0:124415],actual_pixels[0:124415];
    bit seen[0:124415];
    integer ram_delay=0,rom_delay=0,requests=0,ram_requests=0,rom_requests=0,visible=0;
    integer position,fg,py,px,dx,dy,i;
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
    always @(posedge clk) begin
        ram_valid<=0;
        if(ram_request) begin
            if(ram_pending) $fatal(1,"Overlapping captured tile RAM requests");
            ram_requests=ram_requests+1;ram_pending<=1;saved_ram_address<=ram_address;
            ram_delay<=ram_address%3==0?0:ram_address%3==1?3:11;
        end else if(ram_pending) begin
            if(ram_delay==0) begin
                ram_valid<=1;ram_pending<=0;ram_data<=vram[saved_ram_address];
            end else ram_delay<=ram_delay-1;
        end
        rom_valid<=0;
        if(rom_request) begin
            if(rom_pending) $fatal(1,"Overlapping captured tile ROM requests");
            rom_requests=rom_requests+1;rom_pending<=1;
            saved_rom_address<=rom_address;saved_foreground<=rom_foreground;
            rom_delay<=rom_address%3==0?0:rom_address%3==1?3:11;
        end else if(rom_pending) begin
            if(rom_delay==0) begin
                rom_valid<=1;rom_pending<=0;
                rom_data<=saved_foreground?tiles1[saved_rom_address]:tiles0[saved_rom_address];
            end else rom_delay<=rom_delay-1;
        end
        if(!reset && pixel_valid && pixel_x>=8 && pixel_x<296 && pixel_y<216) begin
            position=palette_index[8]*62208+pixel_y*288+pixel_x-8;
            if(seen[position]) $fatal(1,"Repeated captured tile pixel %0d",position);
            if({opaque,palette_index}!==expected_pixels[position])
                $fatal(1,"Captured tile pixel layer=%0d x=%0d y=%0d got=%x opaque=%b expected=%x",
                    palette_index[8],pixel_x,pixel_y,palette_index,opaque,expected_pixels[position]);
            seen[position]=1;
            actual_pixels[position]={opaque,palette_index};
            visible=visible+1;
        end
    end
    initial begin
        $readmemh("vram.hex",vram);
        $readmemh("settings.hex",settings);
        $readmemh("tiles0.hex",tiles0);
        $readmemh("tiles1.hex",tiles1);
        $readmemh("expected.hex",expected_pixels);
        for(i=0;i<124416;i=i+1) seen[i]=0;
        repeat(3) @(negedge clk);
        reset=0;
        for(fg=0;fg<2;fg=fg+1) begin
            dx=settings[fg*2+2]&511;dy=settings[fg*2+1]&511;
            for(py=0;py<216;py=py+1) begin
                px=8;
                while(px<296) begin
                    wait(ready);
                    @(negedge clk);
                    x=px;y=py;scroll_x=dx;scroll_y=dy;flags=settings[0];foreground=fg;valid=1;
                    @(negedge clk);
                    valid=0;requests=requests+1;
                    x=~px;y=~py;scroll_x=~dx;scroll_y=~dy;flags=~settings[0];foreground=!fg;
                    px=px-((px+dx)&7)+8;
                end
            end
        end
        wait(visible==124416);
        repeat(32) @(negedge clk);
        if(ram_pending || rom_pending || requests!=ram_requests || requests!=rom_requests)
            $fatal(1,"Captured tile transactions missing or repeated");
        $writememh("pixels.hex",actual_pixels);
        $display("TILE_CAPTURE_PASS: %0d tile rows; every one of %0d visible layer pixels and opacity bits identical",requests,visible);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Captured tile timeout pixels=%0d requests=%0d",visible,requests);
    end
endmodule
