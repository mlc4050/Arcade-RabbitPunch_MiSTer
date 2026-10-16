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
    wire response_valid;
    wire [15:0] response_data;
    wire memory_valid, memory_supported, rom_request;
    wire [15:0] memory_data;
    wire [17:0] rom_address;
    reg rom_valid = 0, io_valid = 0;
    reg [15:0] rom_data;
    reg [15:0] io_data = 16'hffff;
    int dip_default = 0;
    assign response_valid = memory_valid | io_valid;
    assign response_data = memory_valid ? memory_data : io_data;
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
    rabbitpunch_memory memory_backend(
        .i_clk(clk), .i_request(request), .i_request_write(request_write),
        .iu24_request_address(request_address), .iu16_request_data(request_data),
        .iu2_request_bytes(request_bytes), .o_request_supported(memory_supported),
        .o_response_valid(memory_valid), .ou16_response_data(memory_data),
        .o_rom_request(rom_request), .ou18_rom_byte_address(rom_address),
        .i_rom_response_valid(rom_valid), .iu16_rom_response_data(rom_data),
        .i_view_enable(1'b0), .iu5_view_target(5'b0), .iu15_view_word_address(15'b0),
        .o_view_valid(), .ou16_view_data()
    );
    integer trace_file, writes = 0, reads = 0;
    reg [19:0] address;
    reg [15:0] mask;
    int write_limit = 10000;
    initial begin
        void'($value$plusargs("BOOT_WRITES=%d",write_limit));
        void'($value$plusargs("DSW=%h",dip_default));
        $readmemh("program.hex", rom);
        trace_file = $fopen("rtl_writes.txt", "w");
        if (!trace_file) $fatal(1,"cannot open trace");
        repeat (100) @(negedge clk);
        reset = 0;
    end
    always @(posedge clk) begin
        rom_valid <= rom_request;
        if (rom_request) rom_data <= rom[rom_address>>1];
        io_valid <= 0;
        if (request) begin
            address = request_address[19:0];
            mask = {{8{request_bytes[1]}},{8{request_bytes[0]}}};
            if (request_write) begin
                $fdisplay(trace_file,"%06x %04x %04x",address,mask,request_data & mask);
                writes++;
                if (writes == write_limit) begin
                    $fclose(trace_file);
                    $display("BOOT_PREFIX_COMPLETE writes=%0d reads=%0d",writes,reads);
                    $finish;
                end
            end else reads++;
            if (!memory_supported) begin
                io_data <= 16'hffff;
                if (!request_write) begin
                    case (address)
                        'hc0018, 'hc001a: io_data <= 16'h0000; // Inactive active-high controls.
                        'hc001c: io_data <= dip_default[15:0]; // Generated MRA defaults.
                        'hc001e: $fatal(1,"sound mailbox needs real backend");
                    endcase
                end
                // Register writes are traced but have no raster or sound effects yet.
                // Reads of write-only ports return MAME's unmapped ffff value.
                io_valid <= 1;
            end
        end
    end
    initial begin
        #100ms;
        $fatal(1,"TIMEOUT writes=%0d reads=%0d",writes,reads);
    end
endmodule
