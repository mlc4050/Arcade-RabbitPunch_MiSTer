`timescale 1ns/1ps
module cpu_irq_tb;
    reg clk=0,reset=1,irq=0;
    always #10 clk=~clk;
    wire request,writing,valid,ack,rom_request,supported;
    wire [23:0] address;
    wire [15:0] write_data,read_data;
    wire [1:0] bytes;
    wire [17:0] rom_address;
    reg rom_valid=0;
    reg [15:0] rom_data;
    reg [15:0] rom[0:511];
    bit main_ready=0,handler_done=0,returned=0;
    int acknowledges=0,stack_writes=0;
    rabbitpunch_maincpu cpu(
        .i_clk(clk),.i_reset(reset),.i_pause(1'b0),.i_interrupt_level1(irq),
        .o_interrupt_acknowledge(ack),.o_request(request),.o_request_write(writing),
        .ou24_request_address(address),.ou16_request_data(write_data),.ou2_request_bytes(bytes),
        .i_response_valid(valid),.iu16_response_data(read_data),.o_paused()
    );
    rabbitpunch_memory memory_backend(
        .i_clk(clk),.i_request(request),.i_request_write(writing),.iu24_request_address(address),
        .iu16_request_data(write_data),.iu2_request_bytes(bytes),.o_request_supported(supported),
        .o_response_valid(valid),.ou16_response_data(read_data),.o_rom_request(rom_request),
        .ou18_rom_byte_address(rom_address),.i_rom_response_valid(rom_valid),.iu16_rom_response_data(rom_data),
        .i_view_enable(1'b0),.iu5_view_target(5'b0),.iu15_view_word_address(15'b0),
        .o_view_valid(),.ou16_view_data()
    );
    initial begin
        for(int n=0;n<512;n++)rom[n]=16'h4e71;
        rom[0]=16'h000f;rom[1]=16'hfffc;rom[2]=0;rom[3]=16'h0100;
        rom['h64/2]=0;rom['h66/2]=16'h0200; // Level 1 autovector = vector 25.
        rom['h100/2]=16'h46fc;rom['h102/2]=16'h2000; // MOVE #2000,SR: supervisor, IRQ mask zero.
        rom['h104/2]=16'h33fc;rom['h106/2]=16'h1111;rom['h108/2]=16'h000f;rom['h10a/2]=16'hc000;
        rom['h10c/2]=16'h4e72;rom['h10e/2]=16'h2000; // STOP until interrupt.
        rom['h110/2]=16'h33fc;rom['h112/2]=16'h2222;rom['h114/2]=16'h000f;rom['h116/2]=16'hc002;
        rom['h118/2]=16'h60fe;
        rom['h200/2]=16'h33fc;rom['h202/2]=16'h600d;rom['h204/2]=16'h000f;rom['h206/2]=16'hc004;
        rom['h208/2]=16'h4e73; // RTE restores the interrupted PC/SR.
        repeat(100) @(negedge clk);reset=0;
        wait(main_ready);
        repeat(300) @(negedge clk);
        if(returned || handler_done) $fatal(1,"STOP did not wait for interrupt");
        irq=1;
        wait(ack);@(negedge clk);irq=0;
        wait(returned);
        repeat(100) @(negedge clk);
        if(!handler_done || acknowledges!=1 || stack_writes!=3)
            $fatal(1,"IRQ handler/ack/stack incomplete: handler=%b ack=%0d stack=%0d",handler_done,acknowledges,stack_writes);
        $display("CPU_IRQ_PASS: STOP, level-1 autovector, one acknowledge, three stack words, handler and RTE via VHDL RAM");
        $finish;
    end
    always @(posedge clk) begin
        rom_valid<=rom_request;
        if(rom_request)rom_data<=rom[rom_address>>1];
        if(ack)acknowledges++;
        if(request) begin
            if(!supported || address[23:20]!=0) $fatal(1,"IACK leaked to memory or unsupported access: %h",address);
            if(writing) begin
                case(address)
                    'hfc000: begin if(write_data!==16'h1111)$fatal;main_ready=1;end
                    'hfc004: begin if(write_data!==16'h600d)$fatal;handler_done=1;end
                    'hfc002: begin if(write_data!==16'h2222)$fatal;returned=1;end
                    'hffff6,'hffff8,'hffffa: stack_writes++;
                    default: $fatal(1,"unexpected CPU write %h",address);
                endcase
            end
        end
    end
    initial begin #1ms;$fatal(1,"TIMEOUT ready=%b handler=%b returned=%b ack=%0d",main_ready,handler_done,returned,acknowledges);end
endmodule
