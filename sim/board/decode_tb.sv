`timescale 1ns/1ps
module decode_tb;
    reg [23:0] address = 0;
    reg active = 1, rw = 1, uds_n = 0, lds_n = 0;
    wire [4:0] target;
    integer checks = 0;
    rabbitpunch_decode dut(address, active, rw, uds_n, lds_n, target);
    task check(input [23:0] a, input [4:0] expected);
        begin
            address = a;
            #1;
            if (target !== expected)
                $fatal(1, "Decode %06x rw=%b uds=%b lds=%b active=%b: %0d expected %0d",
                       address, rw, uds_n, lds_n, active, target, expected);
            checks = checks + 1;
        end
    endtask
    task memory_range(input [23:0] first, last, input [4:0] expected);
        begin
            rw = 1; check(first, expected); check(last, expected);
            rw = 0; check(first, expected); check(last, expected);
        end
    endtask
    task low_byte_register(input [23:0] a, input [4:0] expected);
        begin
            rw = 0; uds_n = 0; lds_n = 0; check(a, expected);
            uds_n = 1; check(a + 1, expected);
            uds_n = 0; lds_n = 1; check(a, 0);
            lds_n = 0; rw = 1; check(a, 0);
        end
    endtask
    initial begin
        check(24'h000000, 1); check(24'h03ffff, 1);
        rw = 0; check(24'h000000, 0); check(24'h03ffff, 0);
        memory_range(24'h040000, 24'h04ffff, 2);
        memory_range(24'h060000, 24'h060fff, 3);
        memory_range(24'h080000, 24'h083fff, 4);
        memory_range(24'h0a0000, 24'h0a07ff, 5);
        memory_range(24'h0fc000, 24'h0fffff, 17);
        rw = 1;
        check(24'h050000, 0); check(24'h061000, 0);
        check(24'h084000, 0); check(24'h0a0800, 0); check(24'h0fbfff, 0);
        check(24'h0c0018, 13); check(24'h0c001a, 14);
        check(24'h0c001c, 15); check(24'h0c001e, 16);
        rw = 0; check(24'h0c0018, 0); check(24'h0c001e, 0);
        check(24'h0c0000, 6); check(24'h0c0006, 6);
        uds_n = 1; check(24'h0c0000, 0);
        uds_n = 0; lds_n = 1; check(24'h0c0006, 0);
        check(24'h0c000c, 9);
        uds_n = 1; lds_n = 0; check(24'h0c000d, 9);
        uds_n = 0;
        low_byte_register(24'h0c0008, 7);
        low_byte_register(24'h0c0028, 8);
        low_byte_register(24'h0c000e, 10);
        low_byte_register(24'h0c0010, 11);
        low_byte_register(24'h0c0012, 12);
        check(24'hf00000, 1); check(24'hafc000, 17); check(24'hbc001c, 15);
        check(24'hxxxxxx, 0);
        active = 0; check(24'h000000, 0);
        active = 1; uds_n = 1; lds_n = 1; check(24'h000000, 0);
        $display("BOARD_DECODE_PASS: %0d boundary, lane, access and mirror checks", checks);
        $finish;
    end
endmodule
