`timescale 1ns/1ps
module t80_wrapper_tb;
    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    wire memory_n, io_n, read_n, write_n, halted_n;
    wire [15:0] address;
    reg [7:0] data_in;
    wire [7:0] data_out;
    bit memory_seen = 0, io_seen = 0;
    rabbitpunch_t80 dut(
        .i_clk(clk), .i_reset_n(reset_n), .i_clock_enable(1'b1),
        .i_wait_n(1'b1), .i_interrupt_n(1'b1), .i_nonmaskable_interrupt_n(1'b1),
        .i_bus_request_n(1'b1), .o_opcode_fetch_n(),
        .o_memory_request_n(memory_n), .o_io_request_n(io_n),
        .o_read_n(read_n), .o_write_n(write_n), .o_refresh_n(),
        .o_halted_n(halted_n), .o_bus_acknowledge_n(),
        .ou16_address(address), .iu8_read_data(data_in), .ou8_write_data(data_out)
    );
    // Same LD A,42 / LD (8000),A / OUT (00),A / HALT program as the donor baseline.
    always @* begin
        case (address)
            0: data_in = 'h3e;
            1: data_in = 'h42;
            2: data_in = 'h32;
            3: data_in = 'h00;
            4: data_in = 'h80;
            5: data_in = 'hd3;
            6: data_in = 'h00;
            7: data_in = 'h76;
            default: data_in = 0;
        endcase
    end
    always @(posedge clk) begin
        if (!memory_n && !write_n) begin
            if (address !== 16'h8000 || data_out !== 8'h42) $fatal(1,"incorrect memory write");
            memory_seen = 1;
        end
        if (!io_n && !write_n) begin
            if (address !== 16'h4200 || data_out !== 8'h42) $fatal(1,"incorrect IO write");
            io_seen = 1;
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        repeat (200) @(negedge clk);
        if (!memory_seen || !io_seen || halted_n !== 0) $fatal(1,"T80 program incomplete");
        $display("T80_WRAPPER_PASS: reset, memory write, full IO address/data and HALT");
        $finish;
    end
endmodule
