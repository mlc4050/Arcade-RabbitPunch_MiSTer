`timescale 1ns/1ps
module memory_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg request = 0, writing = 0;
    reg [23:0] address = 0;
    reg [15:0] data_in = 0;
    reg [1:0] bytes = 3;
    wire supported, response_valid;
    wire [15:0] data_out;
    wire rom_request;
    wire [17:0] rom_address;
    reg rom_valid = 0;
    reg [15:0] rom_data = 0;
    reg view_enable = 0;
    reg [4:0] view_target = 0;
    reg [14:0] view_address = 0;
    wire view_valid;
    wire [15:0] view_data;
    int checks = 0, rom_age = -1, rom_delay = 0;
    bit rom_pending = 0;
    rabbitpunch_memory dut(
        .i_clk(clk), .i_request(request), .i_request_write(writing),
        .iu24_request_address(address), .iu16_request_data(data_in), .iu2_request_bytes(bytes),
        .o_request_supported(supported), .o_response_valid(response_valid), .ou16_response_data(data_out),
        .o_rom_request(rom_request), .ou18_rom_byte_address(rom_address),
        .i_rom_response_valid(rom_valid), .iu16_rom_response_data(rom_data),
        .i_view_enable(view_enable), .iu5_view_target(view_target),
        .iu15_view_word_address(view_address), .o_view_valid(view_valid), .ou16_view_data(view_data)
    );
    always @(posedge clk) begin
        rom_valid <= 0;
        if (rom_request) begin
            if (rom_pending) $fatal(1,"duplicate ROM request");
            rom_pending = 1;
            rom_age = rom_delay;
        end else if (rom_pending) begin
            if (rom_age != 0) rom_age--;
            else begin
                rom_data <= rom_address[16:1] ^ 16'h5a3c;
                rom_valid <= 1;
                rom_pending = 0;
            end
        end
    end
    task access(input bit wr, input [23:0] addr, input [1:0] lanes,
                input [15:0] value, input [15:0] expected);
        int timeout_cycles;
        @(negedge clk);
        request = 1; writing = wr; address = addr; bytes = lanes; data_in = value;
        #1;
        if (!supported) $fatal(1,"unexpected unsupported address %h",addr);
        @(negedge clk); request = 0;
        timeout_cycles = 0;
        while (!response_valid && timeout_cycles < 100) begin
            @(negedge clk); timeout_cycles++;
        end
        if (!response_valid || (!wr && data_out !== expected))
            $fatal(1,"memory addr=%h expected=%h got=%h valid=%b",addr,expected,data_out,response_valid);
        checks++;
        @(negedge clk);
        if (response_valid) $fatal(1,"response repeated");
    endtask
    task inspect(input [4:0] target, input [14:0] word_addr, input [15:0] expected);
        @(negedge clk);
        view_enable = 1; view_target = target; view_address = word_addr;
        @(posedge clk); #1;
        if (!view_valid || view_data !== expected) $fatal(1,"view mismatch target=%d address=%h got=%h expected=%h",target,word_addr,view_data,expected);
        @(negedge clk); view_enable = 0;
        @(posedge clk); #1;
        if (view_valid) $fatal(1,"view valid repeated");
        checks++;
    endtask
    int base[0:4], size_words[0:4], target[0:4];
    reg [15:0] pattern;
    initial begin
        base[0]='h40000; size_words[0]=32768; target[0]=2;
        base[1]='h60000; size_words[1]=2048; target[1]=3;
        base[2]='h80000; size_words[2]=8192; target[2]=4;
        base[3]='ha0000; size_words[3]=1024; target[3]=5;
        base[4]='hfc000; size_words[4]=8192; target[4]=17;
        repeat (4) @(negedge clk);
        // Initialize every location before reading: there is no artificial RAM reset.
        for (int bank=0; bank<5; bank++)
            for (int word_addr=0; word_addr<size_words[bank]; word_addr++) begin
                pattern = word_addr ^ (16'h1234 + (bank << 12));
                access(1,base[bank]+2*word_addr,3,pattern,0);
            end
        for (int bank=0; bank<5; bank++) begin
            for (int word_addr=0; word_addr<size_words[bank]; word_addr++) begin
                pattern = word_addr ^ (16'h1234 + (bank << 12));
                access(0,base[bank]+2*word_addr,3,0,pattern);
            end
            inspect(target[bank],size_words[bank]-1,(size_words[bank]-1) ^ (16'h1234 + (bank << 12)));
            access(1,base[bank],3,16'ha55a,0);
            access(1,base[bank],2,16'h1200,0);
            access(1,base[bank]+1,1,16'h0034,0);
            access(0,base[bank],3,0,16'h1234);
            access(0,base[bank]+'h100000,3,0,16'h1234);
            inspect(target[bank],0,16'h1234);
        end
        for (int delay_cycles=0; delay_cycles<=40; delay_cycles+=20) begin
            rom_delay = delay_cycles;
            access(0,24'h020040,3,0,16'h5a1c);
        end
        @(negedge clk);
        request=1; writing=0; address='hc0018; bytes=3;
        #1; if (supported) $fatal(1,"IO target incorrectly claimed");
        @(negedge clk); request=0;
        repeat(5) @(negedge clk);
        if(response_valid) $fatal(1,"unhandled IO acknowledged");
        $display("MEMORY_PASS: all 52224 words, bank isolation, byte lanes, mirrors, view reads, delayed ROM; checks=%0d",checks);
        $finish;
    end
    initial begin
        #20ms; $fatal(1,"TIMEOUT checks=%0d",checks);
    end
endmodule
