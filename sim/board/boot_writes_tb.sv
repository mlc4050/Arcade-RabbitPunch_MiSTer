`timescale 1ns/1ps
module boot_writes_tb;
    reg clk = 0;
    // Evaluation clock is 48 MHz; absolute phase is unrelated to a physical raster.
    always #10.416667 clk = ~clk;
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
    reg [15:0] rom[0:131071];
    reg [15:0] ram[0:524287];
    integer trace_file, writes = 0, reads = 0;
    reg [19:0] address;
    reg [15:0] mask;
    initial begin
        $readmemh("program.hex", rom);
        for (int i=0; i<524288; i++) ram[i]=0;
        trace_file = $fopen("rtl_writes.txt", "w");
        if (!trace_file) $fatal(1,"cannot open trace");
        repeat (100) @(negedge clk);
        reset = 0;
    end
    always @(posedge clk) begin
        response_valid <= 0;
        if (request) begin
            address = request_address[19:0];
            mask = {{8{request_bytes[1]}},{8{request_bytes[0]}}};
            if (request_write) begin
                $fdisplay(trace_file,"%06x %04x %04x",address,mask,request_data & mask);
                if (request_bytes[1]) ram[address>>1][15:8] = request_data[15:8];
                if (request_bytes[0]) ram[address>>1][7:0] = request_data[7:0];
                writes++;
                if (writes == 512) begin
                    $fclose(trace_file);
                    $display("BOOT_PREFIX_COMPLETE writes=%0d reads=%0d",writes,reads);
                    $finish;
                end
            end else reads++;
            if (address < 'h40000) response_data <= rom[address>>1];
            else if (address >= 'hc0018 && address <= 'hc001e)
                $fatal(1,"input/mailbox read needs real backend at %h",address);
            else if (address >= 'hc0000 && address < 'hc0030)
                // CLR.B reads before writing on a 68000. These write-only
                // registers are unmapped on reads in MAME (unmapped value ffff).
                response_data <= 16'hffff;
            else response_data <= ram[address>>1];
            response_valid <= 1;
        end
    end
    initial begin
        #100ms;
        $fatal(1,"TIMEOUT writes=%0d reads=%0d",writes,reads);
    end
endmodule
