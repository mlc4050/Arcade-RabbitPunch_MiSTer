`timescale 1ns/1ps
module bitmap_capture_tb;
    reg clk=0,reset=1,pixel_valid=0;
    always #5 clk=~clk;
    reg [8:0] x=0;
    reg [7:0] y=0;
    reg [15:0] flags;
    wire ready,pixel_out_valid,opaque,bitmap_request,view_valid;
    wire [8:0] out_x;
    wire [7:0] out_y;
    wire [9:0] palette_index;
    wire [14:0] bitmap_address;
    wire [15:0] view_data;
    reg cpu_request=0;
    reg [23:0] cpu_address=0;
    reg [15:0] cpu_data=0;
    wire cpu_valid;
    reg [15:0] bitmap_words[0:32767];
    reg [10:0] expected[0:62207];
    reg [15:0] register_flags[0:0];
    int checks=0;
    rabbitpunch_bitmap bitmap_reader(.i_clk(clk),.i_reset(reset),.i_pixel_valid(pixel_valid),.o_pixel_ready(ready),
        .iu9_pixel_x(x),.iu8_pixel_y(y),.iu16_video_flags(flags),
        .o_ram_request(bitmap_request),.ou15_ram_word_address(bitmap_address),
        .i_ram_response_valid(view_valid),.iu16_ram_response_data(view_data),
        .o_pixel_valid(pixel_out_valid),.ou9_pixel_x(out_x),.ou8_pixel_y(out_y),
        .ou10_palette_index(palette_index),.o_opaque(opaque));
    rabbitpunch_memory memory_backend(.i_clk(clk),.i_request(cpu_request),.i_request_write(1'b1),
        .iu24_request_address(cpu_address),.iu16_request_data(cpu_data),.iu2_request_bytes(2'b11),
        .o_request_supported(),.o_response_valid(cpu_valid),.ou16_response_data(),
        .o_rom_request(),.ou18_rom_byte_address(),.i_rom_response_valid(1'b0),.iu16_rom_response_data(16'b0),
        .i_view_enable(bitmap_request),.iu5_view_target(5'd2),.iu15_view_word_address(bitmap_address),
        .o_view_valid(view_valid),.ou16_view_data(view_data));
    initial begin
        $readmemh("bitmap_words.hex",bitmap_words);
        $readmemh("bitmap_expected.hex",expected);
        $readmemh("video_flags.hex",register_flags);flags=register_flags[0];
        repeat(3)@(negedge clk);
        for(int word_addr=0;word_addr<32768;word_addr++) begin
            @(negedge clk);cpu_request=1;cpu_address='h40000+2*word_addr;cpu_data=bitmap_words[word_addr];
            @(negedge clk);cpu_request=0;
            while(!cpu_valid)@(negedge clk);
        end
        @(negedge clk);reset=0;
        for(int py=0;py<216;py++)begin
            for(int px=8;px<296;px++)begin
                while(!ready)@(negedge clk);
                @(negedge clk);x=px;y=py;pixel_valid=1;
                @(negedge clk);pixel_valid=0;
                while(!pixel_out_valid)@(negedge clk);
                if(out_x!==px[8:0] || out_y!==py[7:0] || {opaque,palette_index}!==expected[checks])
                    $fatal(1,"captured bitmap pixel (%0d,%0d) got %h expected %h",px,py,{opaque,palette_index},expected[checks]);
                checks++;
            end
        end
        $display("BITMAP_CAPTURE_PASS: all %0d visible pixels via CPU-loaded VHDL bitmap RAM",checks);
        $finish;
    end
    initial begin #20ms;$fatal(1,"TIMEOUT checks=%0d",checks);end
endmodule
