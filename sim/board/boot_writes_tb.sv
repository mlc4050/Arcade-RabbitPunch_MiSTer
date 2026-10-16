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
    reg rom_valid = 0;
    wire io_valid;
    reg [15:0] rom_data;
    wire [15:0] io_data;
    wire sound_pending, irq_configure, irq_twice, irq_pending, irq_ack;
    wire [15:0] video_flags;
    wire [8:0] scroll0_y,scroll0_x,scroll1_y,scroll1_x;
    wire [5:0] sprite_count,sprite_priority;
    wire [3:0] gga_selected;
    reg [3:0] gga_view_address=0;
    wire [7:0] gga_view_data;
    int dip_default = 0;
    assign response_valid = memory_valid | io_valid;
    assign response_data = memory_valid ? memory_data : io_data;
    rabbitpunch_maincpu dut(
        .i_interrupt_level1(irq_pending), .o_interrupt_acknowledge(irq_ack),
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
    rabbitpunch_io io_backend(
        .i_clk(clk),.i_initialize(reset),.i_request(request && !memory_supported),
        .i_request_write(request_write),.iu24_request_address(request_address),
        .iu16_request_data(request_data),.iu2_request_bytes(request_bytes),
        .o_response_valid(io_valid),.ou16_response_data(io_data),
        .iu8_player1(8'b0),.iu8_player2(8'b0),.iu8_service(8'b0),.iu16_dips(dip_default[15:0]),
        .i_sound_command_read(1'b0),.o_sound_command_write(),.ou8_sound_command(),.o_sound_pending(sound_pending),
        .ou16_video_flags(video_flags),.ou9_scroll0_y(scroll0_y),.ou9_scroll0_x(scroll0_x),
        .ou9_scroll1_y(scroll1_y),.ou9_scroll1_x(scroll1_x),
        .ou6_sprite_count(sprite_count),.ou6_sprite_priority(sprite_priority),
        .ou4_gga_selected(gga_selected),.iu4_gga_view_address(gga_view_address),.ou8_gga_view_data(gga_view_data),
        .o_gga_write(),.ou4_gga_write_address(),.ou8_gga_write_data(),
        .o_irq_configure(irq_configure),.o_irq_twice_per_frame(irq_twice)
    );
    rabbitpunch_irq interrupts(
        .i_clk(clk),.i_initialize(reset),.i_configure(irq_configure),.i_twice_per_frame(irq_twice),
        .i_vblank_start(1'b0),.i_half_frame(1'b0),.i_acknowledge(irq_ack),.o_level1_pending(irq_pending)
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
        if (request) begin
            address = request_address[19:0];
            mask = {{8{request_bytes[1]}},{8{request_bytes[0]}}};
            if (request_write) begin
                $fdisplay(trace_file,"%06x %04x %04x",address,mask,request_data & mask);
                writes++;
            end else reads++;
            if (!request_write && address=='hc001e && sound_pending)
                $fatal(1,"sound CPU needed to consume pending command");
        end
    end
    integer state_file;
    initial begin
        wait(writes==write_limit);
        @(negedge clk);pause=1;
        wait(paused);
        // The last write has completed before state is inspected.
        repeat(3) @(negedge clk);
        if(writes!=write_limit)$fatal(1,"CPU continued writing after pause");
        $fclose(trace_file);
        state_file=$fopen("rtl_io_state.txt","w");
        if(!state_file)$fatal(1,"cannot open IO state output");
        $fdisplay(state_file,"flags %04x",video_flags);
        $fdisplay(state_file,"scroll0_y %04x",scroll0_y);
        $fdisplay(state_file,"scroll0_x %04x",scroll0_x);
        $fdisplay(state_file,"scroll1_y %04x",scroll1_y);
        $fdisplay(state_file,"scroll1_x %04x",scroll1_x);
        $fdisplay(state_file,"sprite_count %04x",sprite_count);
        $fdisplay(state_file,"sprite_priority %04x",sprite_priority);
        $fdisplay(state_file,"gga_selected %04x",gga_selected);
        for(int index=0;index<16;index++) begin
            @(negedge clk);gga_view_address=index;#1;
            $fdisplay(state_file,"gga%02x %04x",index,gga_view_data);
        end
        $fclose(state_file);
        $display("BOOT_PREFIX_COMPLETE writes=%0d reads=%0d; VHDL RAM/IO snapshot captured",writes,reads);
        $finish;
    end
    initial begin
        #100ms;
        $fatal(1,"TIMEOUT writes=%0d reads=%0d",writes,reads);
    end
endmodule
