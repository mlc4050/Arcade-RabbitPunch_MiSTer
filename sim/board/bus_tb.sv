`timescale 1ns/1ps
module bus_tb;
    reg clk = 0, reset = 1, as_n = 1, rw = 1, uds_n = 1, lds_n = 1;
    reg [23:1] address = 0;
    reg [15:0] write_data = 0;
    wire [15:0] read_data, req_data;
    wire dtack_n, req, req_write;
    wire [23:0] req_address;
    wire [1:0] req_bytes;
    reg response_valid = 0;
    reg [15:0] response_data = 0;
    integer requests = 0, latency = 0, remaining = 0, checks = 0;
    bit pending = 0;
    reg [15:0] reply;
    always #5 clk = ~clk;
    rabbitpunch_bus dut(clk, reset, as_n, rw, uds_n, lds_n, address, write_data,
                       read_data, dtack_n, req, req_write, req_address, req_data,
                       req_bytes, response_valid, response_data);

    // Backend deliberately keeps outstanding requests alive across CPU reset.
    always @(posedge clk) begin
        response_valid <= 0;
        if (pending) begin
            if (remaining == 0) begin
                response_valid <= 1;
                response_data <= reply;
                pending = 0;
            end else remaining = remaining - 1;
        end
        if (req) begin
            if (pending) $fatal(1, "Overlapping backend requests");
            requests = requests + 1;
            if (req_address !== {address, 1'b0} || req_write !== !rw ||
                req_bytes !== {!uds_n, !lds_n} || req_data !== write_data)
                $fatal(1, "Request fields or byte lanes incorrect");
            reply = 16'hcafe;
            remaining = latency;
            pending = 1;
        end
    end

    task access(input bit write, input [1:0] lanes, input integer delay_cycles);
        integer before_count;
        begin
            @(negedge clk);
            before_count = requests;
            latency = delay_cycles;
            address = 23'h60007;
            write_data = 16'h1234;
            rw = !write; uds_n = !lanes[1]; lds_n = !lanes[0]; as_n = 0;
            wait (!dtack_n);
            @(negedge clk);
            if (read_data !== 16'hcafe || requests != before_count + 1)
                $fatal(1, "Response or request count incorrect");
            repeat (5) @(negedge clk);
            if (requests != before_count + 1 || dtack_n !== 0)
                $fatal(1, "Held AS repeated request or lost ACK");
            as_n = 1; uds_n = 1; lds_n = 1;
            repeat (3) @(negedge clk);
            if (dtack_n !== 1) $fatal(1, "ACK did not release");
            checks = checks + 1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        // AS may precede its data strobes; no request until a byte is selected.
        as_n = 0;
        repeat (4) @(negedge clk);
        if (requests != 0 || dtack_n !== 1) $fatal(1, "Premature request/ACK");
        as_n = 1;
        access(0, 2'b11, 0);
        access(0, 2'b10, 3);
        access(0, 2'b01, 11);
        access(1, 2'b11, 0);
        access(1, 2'b10, 3);
        access(1, 2'b01, 11);
        @(negedge clk);
        latency = 12; as_n = 0; uds_n = 0; lds_n = 0;
        wait (pending);
        @(negedge clk); reset = 1; as_n = 1;
        repeat (3) @(negedge clk); reset = 0;
        if (dtack_n !== 1) $fatal(1, "Old response acknowledged a reset CPU");
        // Reissue before the old reply arrives; the backend rejects overlap.
        access(0, 2'b11, 2);
        $display("BOARD_BUS_PASS: %0d accesses; delayed strobes, latency, held ACK and reset drain", checks);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Bus adapter timeout");
    end
endmodule
