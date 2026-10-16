`timescale 1ns/1ps
module maincpu_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset = 1, pause = 0;
    wire request, request_write, paused;
    wire [23:0] request_address;
    wire [15:0] request_data;
    wire [1:0] request_bytes;
    reg response_valid = 0;
    reg [15:0] response_data = 0;
    rabbitpunch_maincpu dut(
        .i_clk(clk),
        .i_reset(reset),
        .i_pause(pause),
        .o_request(request),
        .o_request_write(request_write),
        .ou24_request_address(request_address),
        .ou16_request_data(request_data),
        .ou2_request_bytes(request_bytes),
        .i_response_valid(response_valid),
        .iu16_response_data(response_data),
        .o_paused(paused));

    reg [15:0] rom[0:255];
    reg [15:0] ram[0:7];
    int pc = 'h80;
    task word(input reg [15:0] value);
        rom[pc] = value;
        pc++;
    endtask
    task move_imm(input bit byte_op, input reg [15:0] value, input reg [15:0] addr);
        word(byte_op ? 16'h13fc : 16'h33fc);
        word(value); word(16'h000f); word(addr);
    endtask
    task copy_via_d0(input bit byte_op, input reg [15:0] src, input reg [15:0] dst);
        word(byte_op ? 16'h1039 : 16'h3039);
        word(16'h000f); word(src);
        word(byte_op ? 16'h13c0 : 16'h33c0);
        word(16'h000f); word(dst);
    endtask
    initial begin
        for (int i=0; i<256; i++) rom[i] = 16'h4e71;
        for (int i=0; i<8; i++) ram[i] = 0;
        rom[0]=16'h000f; rom[1]=16'hfffc;
        rom[2]=0; rom[3]=16'h0100;
        move_imm(0, 16'ha55a, 16'hc000);
        move_imm(1, 16'h0012, 16'hc000);
        move_imm(1, 16'h0034, 16'hc001);
        copy_via_d0(0, 16'hc000, 16'hc002);
        copy_via_d0(1, 16'hc000, 16'hc004);
        copy_via_d0(1, 16'hc001, 16'hc005);
        move_imm(0, 16'h600d, 16'hc006);
        word(16'h60fe);
    end

    bit pending = 0;
    reg [23:0] addr;
    reg [15:0] value;
    reg [1:0] lanes;
    bit writing;
    int delay_left, accesses = 0, writes = 0, completions = 0;
    int vector_reads = 0;
    always @(posedge clk) begin
        response_valid <= 0;
        if (request) begin
            if (pending) $fatal(1,"duplicate request while pending");
            if ($isunknown({request_address,request_bytes,request_write}))
                $fatal(1,"unknown CPU request");
            addr = request_address;
            lanes = request_bytes;
            value = request_data;
            writing = request_write;
            delay_left = (accesses % 3 == 0) ? 0 : ((accesses % 3 == 1) ? 17 : 65);
            accesses++;
            pending = 1;
        end else if (pending) begin
            if (delay_left != 0) delay_left--;
            else begin
                if (addr < 512 && !writing) begin
                    response_data <= rom[addr>>1];
                    if (addr < 8) vector_reads++;
                end else if (addr >= 'hfc000 && addr <= 'hfc00e) begin
                    if (writing) begin
                        if (lanes[1]) ram[(addr-'hfc000)>>1][15:8] = value[15:8];
                        if (lanes[0]) ram[(addr-'hfc000)>>1][7:0] = value[7:0];
                        writes++;
                        if (addr == 'hfc006) begin
                            if (ram[0] !== 16'h1234 || ram[1] !== 16'h1234 ||
                                ram[2] !== 16'h1234 || ram[3] !== 16'h600d)
                                $fatal(1,"RAM mismatch %h %h %h %h",ram[0],ram[1],ram[2],ram[3]);
                            completions++;
                        end
                    end
                    response_data <= ram[(addr-'hfc000)>>1];
                end else $fatal(1,"unexpected access addr=%h write=%b",addr,writing);
                pending = 0;
                response_valid <= 1;
            end
        end
    end

    int saved_accesses;
    initial begin
        repeat (100) @(negedge clk);
        reset = 0;
        wait (writes == 2);
        @(negedge clk); pause = 1;
        wait (paused);
        // A response may still be draining into the adapter at the pause boundary.
        repeat (100) @(negedge clk);
        saved_accesses = accesses;
        repeat (200) @(negedge clk);
        if (!paused || accesses != saved_accesses) $fatal(1,"pause did not hold CPU");
        pause = 0;
        wait (completions == 1);
        repeat (100) @(negedge clk);
        reset = 1;
        repeat (100) @(negedge clk);
        reset = 0;
        wait (completions == 2);
        repeat (100) @(negedge clk);
        if (writes != 14 || vector_reads != 8) $fatal(1,"reset replay writes=%0d vectors=%0d",writes,vector_reads);
        $display("MAINCPU_PASS: diagnostic twice, byte lanes, readback, 0/17/65-cycle latency, pause, reset; accesses=%0d",accesses);
        $finish;
    end
    initial begin
        #2ms;
        $fatal(1,"TIMEOUT writes=%0d completions=%0d accesses=%0d",writes,completions,accesses);
    end
endmodule
