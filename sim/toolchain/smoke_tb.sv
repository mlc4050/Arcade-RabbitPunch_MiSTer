`timescale 1ns/1ps
module smoke_tb;
    reg clk = 0;
    reg reset = 1;
    reg enable = 0;
    reg [7:0] data_in = 0;
    wire [7:0] data_out;
    always #5 clk = ~clk;
    smoke_register dut(clk, reset, enable, data_in, data_out);

    task check(input [7:0] expected);
        @(posedge clk);
        #1;
        if (data_out !== expected)
            $fatal(1, "Mixed-language register: expected %02x got %02x", expected, data_out);
    endtask

    initial begin
        check(8'h00);
        @(negedge clk);
        reset = 0;
        enable = 1;
        data_in = 8'ha5;
        check(8'ha5);
        @(negedge clk);
        enable = 0;
        data_in = 8'h5a;
        check(8'ha5);
        @(negedge clk);
        enable = 1;
        check(8'h5a);
        @(negedge clk);
        reset = 1;
        check(8'h00);
        $display("TOOLCHAIN_SMOKE_PASS");
        $finish;
    end
endmodule
