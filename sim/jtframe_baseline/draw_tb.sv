`timescale 1ns/1ps
module draw_tb;
    reg clk = 0, rst = 1, draw = 0, hflip = 0, vflip = 0;
    reg [10:0] code = 11'h123;
    wire busy, rom_cs, buf_we;
    wire [17:2] rom_addr;
    wire [8:0] buf_addr;
    wire [7:0] buf_din;
    integer latency = 0, remaining = 0, pixels = 0, trials = 0;
    wire rom_ok = rom_cs && remaining == 0;
    always #5 clk = ~clk;

    function automatic [31:0] planar(input bit half);
        integer p, plane;
        begin
            planar = 0;
            for (p = 0; p < 8; p = p + 1)
                for (plane = 0; plane < 4; plane = plane + 1)
                    planar[plane*8+p] = (((half ? 8 : 0)+p) >> plane) & 1;
        end
    endfunction

    jtframe_draw #(.CW(11)) dut(
        .clk(clk), .rst(rst), .draw(draw), .busy(busy),
        .code(code), .xpos(9'd32), .ysub(4'd5), .trunc(2'b00),
        .hzoom(6'd0), .hz_keep(1'b0), .hflip(hflip), .vflip(vflip), .pal(4'ha),
        .rom_addr(rom_addr), .rom_cs(rom_cs), .rom_ok(rom_ok),
        .rom_data(planar(rom_addr[6])), .buf_addr(buf_addr), .buf_we(buf_we), .buf_din(buf_din)
    );

    always @(posedge clk) begin
        if (rst || !rom_cs || rom_ok) remaining <= latency;
        else if (remaining > 0) remaining <= remaining - 1;
        if (!rst && rom_cs) begin
            if (rom_addr[17:7] !== code || rom_addr[5:2] !== (4'd5 ^ {4{vflip}}))
                $fatal(1, "Unexpected sprite code/row ROM address");
        end
        if (!rst && buf_we) begin
            if (pixels >= 16 || buf_addr !== (9'd32 + pixels) ||
                buf_din !== (8'ha0 | (hflip ? 15-pixels : pixels)))
                $fatal(1, "Pixel %0d addr=%0d data=%02x hflip=%0d latency=%0d",
                       pixels, buf_addr, buf_din, hflip, latency);
            pixels = pixels + 1;
        end
    end

    task trial(input integer delay_cycles, input bit hf, input bit vf);
        begin
            @(negedge clk);
            rst = 1;
            latency = delay_cycles;
            hflip = hf;
            vflip = vf;
            pixels = 0;
            repeat (3) @(negedge clk);
            rst = 0;
            @(negedge clk); draw = 1;
            @(negedge clk); draw = 0;
            wait (!busy);
            @(negedge clk);
            if (pixels != 16) $fatal(1, "Expected 16 pixels, got %0d", pixels);
            trials = trials + 1;
        end
    endtask

    integer d, hf, vf;
    initial begin
        for (d = 0; d < 3; d = d + 1)
            for (hf = 0; hf < 2; hf = hf + 1)
                for (vf = 0; vf < 2; vf = vf + 1)
                    trial(d == 0 ? 0 : d == 1 ? 3 : 11, hf != 0, vf != 0);
        $display("JTFRAME_DRAW_PASS: %0d trials, 16 checked pixels each", trials);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Sprite drawer timeout");
    end
endmodule
