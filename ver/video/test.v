`timescale 1ns/1ps

module test;

reg                rst, clk, cen8;
wire       [ 7:0]  vdump, vrender;
wire       [ 8:0]  hdump;
// video signals
wire               HS, VS, HB, VB, frame;
// Video RAM interface
wire       [23:1]  vram1_addr, vram2_addr, vram3_addr;
wire       [15:0]  vram1_data, vram2_data, vram3_data;
wire               vram1_ok, vram2_ok, vram3_ok;
wire               vram1_cs, vram2_cs, vram3_cs;

// GFX ROM interface
wire       [22:0]  rom1_addr, rom2_addr, rom3_addr;
wire       [31:0]  rom1_data, rom2_data, rom3_data;
wire       [ 3:0]  rom1_bank, rom2_bank, rom3_bank;
wire               rom1_half, rom2_half, rom3_half;
wire               rom1_cs, rom2_cs, rom3_cs;
wire               rom1_ok, rom2_ok, rom3_ok;
// To frame buffer
wire       [11:0]  line_data;
wire       [ 8:0]  line_addr;
wire               line_wr, line_wr_ok;

reg                downloading=1'b0, loop_rst=1'b0, sdram_ack;
reg        [31:0]  data_read;
wire               sdram_req, refresh_en;
wire       [21:0]  sdram_addr;
reg        [ 3:0]  sdram_ok4;
reg        [21:0]  last_sdram_addr;
reg                data_rdy;

jtcps1_video UUT (
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen8       ( cen8          ),

    .hdump      ( hdump         ),
    .vdump      ( vdump         ),
    .vrender    ( vrender       ),
    .frame      ( frame         ),

    // Video signal
    .HS         ( HS            ),
    .VS         ( VS            ),
    .HB         ( HB            ),
    .VB         ( VB            ),

    // Register configuration
    .hpos1      ( 16'hffc0      ),
    .vpos1      ( 16'h0000      ),
    .hpos2      ( 16'h03c0      ),
    .vpos2      ( 16'h0300      ),
    .hpos3      ( 16'h07c0      ),
    .vpos3      ( 16'h0700      ),
    .vram1_base ( 16'h9000      ),
    .vram2_base ( 16'h9040      ),
    .vram3_base ( 16'h9080      ),
    .pal_base   ( 16'h9100      ),
    // Video RAM interface
    .vram1_addr ( vram1_addr    ),
    .vram1_data ( vram1_data    ),
    .vram1_ok   ( vram1_ok      ),
    .vram1_cs   ( vram1_cs      ),

    .vram2_addr ( vram2_addr    ),
    .vram2_data ( vram2_data    ),
    .vram2_ok   ( vram2_ok      ),
    .vram2_cs   ( vram2_cs      ),

    .vram3_addr ( vram3_addr    ),
    .vram3_data ( vram3_data    ),
    .vram3_ok   ( vram3_ok      ),
    .vram3_cs   ( vram3_cs      ),

    // GFX ROM interface
    .rom1_addr  ( rom1_addr     ),
    .rom1_bank  ( rom1_bank     ),
    .rom1_half  ( rom1_half     ),
    .rom1_data  ( rom1_data     ),
    .rom1_cs    ( rom1_cs       ),
    .rom1_ok    ( rom1_ok       ),

    .rom2_addr  ( rom2_addr     ),
    .rom2_bank  ( rom2_bank     ),
    .rom2_half  ( rom2_half     ),
    .rom2_data  ( rom2_data     ),
    .rom2_cs    ( rom2_cs       ),
    .rom2_ok    ( rom2_ok       ),

    .rom3_addr  ( rom3_addr     ),
    .rom3_bank  ( rom3_bank     ),
    .rom3_half  ( rom3_half     ),
    .rom3_data  ( rom3_data     ),
    .rom3_cs    ( rom3_cs       ),
    .rom3_ok    ( rom3_ok       ),
    // To frame buffer
    .line_data  ( line_data     ),
    .line_addr  ( line_addr     ),
    .line_wr    ( line_wr       ),
    .line_wr_ok ( line_wr_ok    )
);

//always @(posedge start) begin
//    if(!line_done) $display("WARNING: tilemap line did not complete at time %t", $time);
//end

// JTFRAME_ROM_RW slot types
// 0 = read only    ( default )
// 1 = write only
// 2 = R/W

localparam WO=1;

wire [9:0] slot_cs, slot_ok, slot_wr;
assign slot_cs[0] = 1'b0;
assign slot_cs[1] = 1'b0;
assign slot_cs[2] = 1'b1;
assign slot_cs[3] = vram1_cs;
assign slot_cs[4] = vram2_cs;
assign slot_cs[5] = vram3_cs;
assign slot_cs[6] = rom1_cs;
assign slot_cs[7] = rom2_cs;
assign slot_cs[8] = rom3_cs;
assign slot_cs[9] = line_wr;

assign fbread_ok  = slot_ok[2];
assign vram1_ok   = slot_ok[3];
assign vram2_ok   = slot_ok[4];
assign vram3_ok   = slot_ok[5];
assign rom1_ok    = slot_ok[6];
assign rom2_ok    = slot_ok[7];
assign rom3_ok    = slot_ok[8];
assign line_wr_ok = slot_ok[9];

assign slot_wr[8:0] = 9'd0;
assign slot_wr[9]   = line_wr;

wire [31:0] data_write;
wire        sdram_rnw;
wire [21:0] rom1_offset, rom2_offset, rom3_offset,
            frame0_offset, frame1_offset;

localparam [21:0] gfx_offset   = 22'h10_0000;
localparam [21:0] vram_offset  = 22'h32_0000;
localparam [21:0] frame_offset = 22'h36_0000;
assign rom1_offset   = gfx_offset;
assign rom2_offset   = gfx_offset;
assign rom3_offset   = gfx_offset;//+22'h10_0000;

wire [19:0] gfx3_addr_pre = rom3_addr[17:0] + 20'h4_0000;

wire [16:0] fbwr_addr = { vrender, line_addr };
wire [15:0] fbwr_data = { 4'd0, line_data };

reg  [ 9:0] fbrd_addr;

wire [21:0] gfx1_addr = {rom1_addr[19:0], rom1_half, 1'b0 };
wire [21:0] gfx2_addr = {rom2_addr[19:0], rom2_half, 1'b0 };
wire [21:0] gfx3_addr = {gfx3_addr_pre, rom3_half, 1'b0 };

jtframe_sdram_mux #(
    // Frame buffer, read access
    .SLOT2_AW   ( 18    ),  //8
    .SLOT2_DW   ( 16    ),
    // VRAM read access:
    .SLOT3_AW   ( 18    ),
    .SLOT3_DW   ( 16    ),
    .SLOT4_AW   ( 18    ),  //4
    .SLOT4_DW   ( 16    ),
    .SLOT5_AW   ( 18    ),  //5
    .SLOT5_DW   ( 16    ),
    // GFX ROM
    .SLOT6_AW   ( 22    ),  //6
    .SLOT7_AW   ( 22    ),  //7
    .SLOT8_AW   ( 22    ),  //8
    .SLOT6_DW   ( 32    ),
    .SLOT7_DW   ( 32    ),
    .SLOT8_DW   ( 32    ),
    // Frame buffer, write access
    .SLOT9_AW   ( 17    ),  //8
    .SLOT9_DW   ( 16    ),
    .SLOT9_TYPE ( WO    )
)
u_sdram_mux(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .vblank         ( 1'b0          ),
    // Frame buffer reads
    .slot2_offset   ( frame_offset      ),
    .slot2_addr     ( {vdump, fbrd_addr}    ),
    //.slot2_dout     ( fbrd_data         ),

    // VRAM read access only
    .slot3_offset   ( vram_offset       ),
    .slot3_addr     ( vram1_addr[18:1]  ),
    .slot3_dout     ( vram1_data        ),

    .slot4_offset   ( vram_offset       ),
    .slot4_addr     ( vram2_addr[18:1]  ),
    .slot4_dout     ( vram2_data        ),

    .slot5_offset   ( vram_offset       ),
    .slot5_addr     ( vram3_addr[18:1]  ),
    .slot5_dout     ( vram3_data        ),

    // GFX ROM
    .slot6_offset   ( rom1_offset       ),
    .slot6_addr     ( gfx1_addr         ),
    .slot6_dout     ( rom1_data         ),

    .slot7_offset   ( rom2_offset       ),
    .slot7_addr     ( gfx2_addr         ),
    .slot7_dout     ( rom2_data         ),

    .slot8_offset   ( rom3_offset       ),
    .slot8_addr     ( gfx3_addr         ),
    .slot8_dout     ( rom3_data         ),

    // Frame buffer writes
    .slot9_offset   ( frame_offset      ),
    .slot9_addr     ( fbwr_addr         ),
    .slot9_din      ( fbwr_data         ),

    // bus signals
    .slot_cs        ( slot_cs       ),
    .slot_ok        ( slot_ok       ),
    .slot_wr        ( slot_wr       ),

    // SDRAM controller interface
    .downloading    ( downloading   ),
    .loop_rst       ( loop_rst      ),
    .sdram_ack      ( sdram_ack     ),
    .sdram_req      ( sdram_req     ),
    .refresh_en     ( refresh_en    ),
    .sdram_addr     ( sdram_addr    ),
    .sdram_rnw      ( sdram_rnw     ),
    .data_rdy       ( data_rdy      ),
    .data_read      ( data_read     ),   
    .data_write     ( data_write    )
);

// Dump output frame buffer
integer dumpcnt=0, dump_start=0, dumpv=0, fout;

// Palette
reg [15:0] pal[0:(2**11)-1]; // 4096?
reg [15:0] raw;
reg [11:0] pal_idx;
reg [ 3:0] raw_r, raw_g, raw_b, raw_br;

always @(pal_idx) begin
    raw    = pal[pal_idx];
    raw_br = raw[15:12];
    raw_r  = raw[11: 8];
    raw_g  = raw[ 7: 4];
    raw_b  = raw[ 3: 0];
end

initial begin
    $readmemh("pal16.hex",pal);
    fout<=$fopen("video.raw","wb");
end

reg dumpdly, dumplast;

always @(posedge clk) begin
    if( !dump_start ) begin
        dumpv   <= 0;
        dumpcnt <= 64;
        dumpdly <= 0;
        dumplast<= 0;
    end else begin
        dumpdly <= 1'b1;
        pal_idx <= cpy_buf[{dumpv[7:0],dumpcnt[8:0]}];
        dumpcnt <= dumpcnt+1;
        if( dumpcnt==384+63 ) begin
            dumpcnt <= 64;
            dumpv   <= dumpv+1;
            dumplast <= dumpv==255;
        end
        if( dumpdly ) begin
            $fwrite(fout,"%u", { 8'hff, raw_b[3:0],4'd0, raw_g[3:0], 4'd0, raw_r[3:0], 4'd0 });
            if(dumplast) $finish;
        end
    end
end

// SDRAM
reg [15:0] sdram[0:(2**22)-1];

initial begin
    $readmemh( "gfx16.hex",  sdram, gfx_offset, gfx_offset+1_572_875  );
    $readmemh( "vram16.hex", sdram, vram_offset, vram_offset+98303 );
    // fout=$fopen("sdram_dump.hex","w");
    // for( dumpcnt=0; dumpcnt<vram_offset+98303; dumpcnt=dumpcnt+1 ) begin
    //     $fdisplay(fout,"%X", sdram[dumpcnt]);
    // end
    // $finish;
end

localparam SDRAM_STCNT=6; // 6 Realistic, 5 Possible, less than 5 unrealistic
reg [SDRAM_STCNT-1:0] sdram_st;
reg       last_st0, last_HS;
integer  sdram_idle_cnt, total_cycles, line_idle;
wire     HS_negedge = !HS &&  last_HS;
wire     HS_posedge =  HS && !last_HS;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        sdram_st <= 1;
        data_rdy <= 1'b1;
        data_read<= 16'd0;
        last_st0 <= 1'b0;
        sdram_idle_cnt <= 0;
        total_cycles   <= 0;
        line_idle      <= 0;
    end else begin
        last_st0 <= sdram_st[0];
        last_HS  <= HS;
        if( last_st0 && sdram_st[0] ) begin
            sdram_idle_cnt=sdram_idle_cnt+1;
            line_idle <= line_idle+1;
        end
        if( HS_negedge ) line_idle <= 0;
        total_cycles = total_cycles+1;
        if(sdram_st!=1 || sdram_req ) sdram_st <= { sdram_st[SDRAM_STCNT-2:0], sdram_st[SDRAM_STCNT-1] };
        sdram_ack  <= 1'b0;
        data_rdy <= 1'b0;
        if( sdram_req ) begin
            sdram_ack <= 1'b1;
        end
        if( sdram_st[SDRAM_STCNT-1] ) begin
            data_rdy <= 1'b1;
            data_read  <= { sdram[sdram_addr+1], sdram[sdram_addr] };
            if( !sdram_rnw ) sdram[sdram_addr] <= data_write[15:0];
        end
    end
end

// Frame buffer read
reg fbread_wait, fbread_done;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        fbrd_addr = 9'd0;
        fbread_wait <= 1'd0;
        fbread_done <= 1'b0;
    end else begin
        fbread_wait <= 1'b0;
        if( HS_negedge ) begin
            fbrd_addr   <= 1'd0;
            fbread_done <= 1'b0;
        end else if( fbread_ok && !fbread_wait && !fbread_done) begin
            fbrd_addr <= fbrd_addr + 9'd1;
            fbread_wait <= 1'b1;
            if( fbrd_addr == 9'd384 ) fbread_done <= 1'b1;
        end
    end
end

// Reset and clock

initial begin
    rst = 1'b0;
    #20 rst = 1'b1;
    #400 rst = 1'b0;
end

initial begin
    clk = 1'b0;
    forever #(10.417/2) clk = ~clk;
end

integer cen_cnt=0;

always @(posedge clk) begin
    cen_cnt <= cen_cnt+1;
    if(cen_cnt>=12) cen_cnt<=0;
    cen8 <= cen_cnt==0;
end

// Line count
reg [12:0] cpy_buf[0:(2**(8+9))-1];
integer framecnt;

always @(posedge clk) begin
    if( line_wr )
        cpy_buf[ {vrender, line_addr} ] <= line_data;
end

always @(posedge HS, posedge rst) begin
    if(rst) begin
        framecnt <= 0;
    end else begin
        if( vdump[3:0]==0 ) $display("Line %d",vdump);
        if(&vdump) begin
            framecnt <= framecnt+1;
            $display("FRAME");
        end
        if(vdump==8'd24 && 0) begin
            $display("%d%% SDRAM idle", (sdram_idle_cnt*100)/total_cycles);
            $finish;
        end
        if ( framecnt==1 && !dump_start) begin
            dump_start<=1;
            $display("%d%% SDRAM idle", (sdram_idle_cnt*100)/total_cycles);
            $display("Image dump");
        end
    end
end

`ifndef NCVERILOG
    initial begin
        $dumpfile("test.lxt");
        $dumpvars(0,test);
        $dumpon;
    end
`else
    initial begin
        $shm_open("test.shm");
        $shm_probe(test,"AS");
    end
`endif

endmodule