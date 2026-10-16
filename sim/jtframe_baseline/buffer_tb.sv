`timescale 1ns/1ps
module buffer_tb;
    reg clk = 0, lhbl = 1, flip = 0, we = 0, rd = 0;
    reg [3:0] wr_addr = 0, rd_addr = 0;
    reg [7:0] wr_data = 0;
    wire [7:0] newest, oldest;
    always #5 clk = ~clk;

    jtframe_obj_buffer #(.AW(4), .KEEP_OLD(0)) replace_buffer(
        .clk(clk), .LHBL(lhbl), .flip(flip), .wr_data(wr_data), .wr_addr(wr_addr),
        .we(we), .rd_addr(rd_addr), .rd(rd), .rd_data(newest));
    jtframe_obj_buffer #(.AW(4), .KEEP_OLD(1)) preserve_buffer(
        .clk(clk), .LHBL(lhbl), .flip(flip), .wr_data(wr_data), .wr_addr(wr_addr),
        .we(we), .rd_addr(rd_addr), .rd(rd), .rd_data(oldest));

    task read_pixel(input [3:0] address, input bit check,
                    input [7:0] expected_new, expected_old);
        begin
            @(negedge clk); rd_addr = address;
            repeat (3) @(negedge clk);
            rd = 1;
            @(negedge clk); rd = 0;
            repeat (4) @(negedge clk);
            if (check && (newest !== expected_new || oldest !== expected_old))
                $fatal(1, "Buffer address %0d: newest=%02x oldest=%02x expected=%02x/%02x",
                       address, newest, oldest, expected_new, expected_old);
        end
    endtask

    task next_line;
        begin
            @(negedge clk); lhbl = 0;
            repeat (3) @(negedge clk);
            lhbl = 1;
            repeat (3) @(negedge clk);
        end
    endtask

    task write_pixel(input [3:0] address, input [7:0] pixel);
        begin
            @(negedge clk); wr_addr = address; wr_data = pixel;
            repeat (3) @(negedge clk);
            we = 1;
            repeat (3) @(negedge clk);
            we = 0;
        end
    endtask

    integer i;
    initial begin
        // Resetless primitive: clear both line banks through their public read/erase port.
        repeat (5) @(negedge clk);
        for (i = 0; i < 16; i = i + 1) read_pixel(i, 0, 0, 0);
        next_line();
        for (i = 0; i < 16; i = i + 1) read_pixel(i, 0, 0, 0);
        next_line();
        write_pixel(3, 8'h21);
        write_pixel(3, 8'h52);
        write_pixel(4, 8'haf);
        next_line();
        read_pixel(3, 1, 8'h52, 8'h21);
        read_pixel(4, 1, 8'h0f, 8'h0f);
        read_pixel(3, 1, 8'h0f, 8'h0f);
        flip = 1;
        write_pixel(2, 8'h63);
        flip = 0;
        next_line();
        read_pixel(13, 1, 8'h63, 8'h63);
        $display("JTFRAME_BUFFER_PASS: bank swap, transparency, priority, erase and flip");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Object buffer timeout");
    end
endmodule
