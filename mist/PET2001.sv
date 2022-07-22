//============================================================================
//  PET2001
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//	Extension to Basic v4, 32KB RAM and Loader fix by raparici
//
//  Ported to MiST, and thus DeMiSTified platforms by Alastair M. Robinson
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module PET2001
(
   input         CLOCK_27,   // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,
`ifdef DEMISTIFY
   output        VGA_CLK,
   output        VGA_WINDOW,
   output        VGA_PIXEL,
   output        CORE_CLK,
`endif

   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   output        UART_TX,
   input         UART_RX,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         CONF_DATA0,

`ifdef DEMISTIFY
   input  [15:0] SDRAM_DQ_IN,
   output [15:0] SDRAM_DQ_OUT,
   output        SDRAM_DRIVE_DQ,
`endif
   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);
`default_nettype none

assign SDRAM_CKE = 1'b1;

reg ioctl_wait;
wire ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0] ioctl_dout;
wire [7:0] ioctl_index;
wire ioctl_download;

assign LED = tape_led | ioctl_download;

`include "build_id.v" 
localparam CONF_STR = 
{
	"PET2001;;",
	"F,TAPPRG,Load Tape / Program;",
	"O78,TAP mode,Fast,Normal,Normal+Sound;",
	"P1,System;",
	"P1F,ROM,Load ROM;",
	"P1O6,Keyboard,Graphics,Business;",
	"P1O9A,CPU Speed,Normal,Fast,Turbo,Turbo+;",
	"P1O3,Diag,Off,On(needs Reset);",
	"O2,Screen Color,White,Green;",
	"O45,Scanlines,None,25%,50%,75%;",
	"T0,Reset;",
	"V,v1.00",`BUILD_DATE
};

wire keyboardtype = status[6];

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;
		
pll pll
(
	.inclk0(CLOCK_27),
	.c0(SDRAM_CLK),
	.c1(clk_sys),
`ifdef DEMISTIFY_HDMI
	.c2(VGA_CLK),
`endif
	.locked(pll_locked)
);

`ifdef DEMISTIFY_HDMI
assign VGA_WINDOW = !HBlank & !VBlank;
assign CORE_CLK = clk_sys;

reg [3:0] pdiv;
always @(posedge clk_sys) begin
	pdiv <= pdiv + 1'b1;
	VGA_PIXEL <= tv15khz ? &pdiv[1:0] : pdiv[0];
end
`endif

reg reset = 1;
reg sdram_reset_n;
integer   initRESET = 100;
reg [3:0] reset_cnt;
always @(posedge clk_sys) begin

	sdram_reset_n <= initRESET || !pll_locked ? 1'b0 : 1'b1;
	
	if ((!(status[0] | buttons[1]) && reset_cnt==4'd14) && !initRESET)
		reset <= 0;
	else begin
		if(initRESET) initRESET <= initRESET - 1;
		reset <= 1;
		reset_cnt <= reset_cnt+4'd1;
	end
end

reg  ce_7mp;
reg  ce_7mn;
reg  ce_1m;
//wire [6:0] cpu_rates[4] = {55, 27, 13, 6};

reg  [2:0] div = 0;
reg  [6:0] cpu_div = 0;
reg  [6:0] cpu_rate = 55;
wire [6:0] cpu_rate_sel;
always @(posedge clk_sys) begin
	div <= div + 1'd1;
	ce_7mp  <= !div[2] & !div[1:0];
	ce_7mn  <=  div[2] & !div[1:0];

	case (status[10:9])
		2'b00 : cpu_rate_sel<=55;
		2'b01 : cpu_rate_sel<=45;
		2'b10 : cpu_rate_sel<=34;
		2'b11 : cpu_rate_sel<=24;
	endcase

	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == cpu_rate) begin
		cpu_div  <= 0;
		cpu_rate <= (tape_active && !status[8:7]) ? 7'd24 : cpu_rate_sel;
	end
	ce_1m <= ~(tape_active & ~ram_ready) && !cpu_div;
end


///////////////////////////////////////////////////
// RAM
///////////////////////////////////////////////////

wire ram_ready;

wire [15:0] sdram_dq_out;
wire [15:0] sdram_dq_in;
wire sdram_drive_dq;

`ifdef YOSYS
assign SDRAM_DQ_OUT = sdram_dq_out;
assign sdram_dq_in = SDRAM_DQ_IN;
assign SDRAM_DRIVE_DQ = sdram_drive_dq;
`else
assign SDRAM_DQ = sdram_drive_dq ? sdram_dq_out : {16{1'bz}};
assign sdram_dq_in = SDRAM_DQ;
`endif

wire [15:0] addr;
reg [15:0] addr_d;
wire [15:0] rom_dout;
wire [7:0] rom_byte = addr[0] ? rom_dout[7:0] : rom_dout[15:8];
reg rom_req;
wire rom_ack;
reg rom_write;
reg char_write;

wire [15:0] charaddr;
assign charaddr[15:11] = 5'b1110_1; // FIXME - too many bits?
reg [15:0] charaddr_d;
wire [15:0] char_dout;
wire [7:0] char_byte = charaddr[0] ? char_dout[7:0] : char_dout[15:8];
reg char_req;
wire char_ack;

wire [24:0] tape_addr;
wire [15:0] tape_dout;
wire [7:0] tape_data = tape_addr[0] ? tape_dout[7:0] : tape_dout[15:8];
reg tape_wr;
reg tape_rd_d;
reg tape_req;
wire tape_ack;

always @(posedge clk_sys) begin
	if((addr!=addr_d && !rom_download) || (rom_download && ioctl_wr))
		rom_req<=~rom_ack;

	if((charaddr!=charaddr_d && !rom_download ) || (rom_download && ioctl_wr))
		char_req<=~char_ack;

	if (rom_req == rom_ack)
		rom_write<=1'b0;

	if (char_req == char_ack)
		char_write<=1'b0;

	if (rom_download && ioctl_wr) begin
		rom_write<=1'b1;
		char_write<=1'b1;
	end
	
	if (tape_req == tape_ack)
		tape_wr<=1'b0;

	if (tap_download && ioctl_wr)
		tape_wr<=1'b1;

	if ((!tap_download && tape_rd && ~tape_rd_d) || (tap_download && ioctl_wr))
		tape_req <= ~tape_ack;
	tape_rd_d <= tape_rd;

	addr_d <= addr;
	charaddr_d <= charaddr;
end

sdram_amr ram
(
	.SDRAM_DRIVE_DQ(sdram_drive_dq),
	.SDRAM_DQ_IN(sdram_dq_in),
	.SDRAM_DQ_OUT(sdram_dq_out),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nWE(SDRAM_nWE),
	
	// cpu/chipset interface
	.init_n(sdram_reset_n),
	.clk(clk_sys),
	.clkref(ce_1m),
	.sync_en(1'b1),
	.ready(ram_ready),

	// ROM and Char are in the same bank since they both access the same ROM.
	
	.rom_addr(rom_download ? 16'h3000+ioctl_addr[21:0] : addr[14:0]),
	.rom_dout(rom_dout),
	.rom_din (ioctl_dout),
	.rom_req (rom_req),
	.rom_ack (rom_ack),
	.rom_we (rom_write),

	.char_addr(rom_download ? 16'h3000+ioctl_addr[21:0] : charaddr[14:0]),
	.char_dout(char_dout),
	.char_din (ioctl_dout),
	.char_req (char_req),
	.char_ack (char_ack),
	.char_we (char_write),

	.tape_addr(tap_download ? ioctl_addr : tape_addr),
	.tape_dout(tape_dout),
	.tape_din(ioctl_dout),
	.tape_req(tape_req),
	.tape_ack(tape_ack),
	.tape_we(tape_wr)
);

always @(posedge clk_sys) begin
	reg old_ready, old_reset;

	old_ready <= ram_ready;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(ioctl_wr && (ioctl_index == 1)) ioctl_wait <= 1;
	else if(ioctl_wait && (~old_ready & ram_ready)) ioctl_wait <= 0;
end


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire [31:0] js0;
wire [31:0] js1;
wire ps2_key_pressed;
wire ps2_key_stb;
wire ps2_key_ext;
wire [7:0] ps2_key;
wire        forced_scandoubler;

wire [1:0] scanlines = status[5:4];

wire tv15khz;

// include user_io module for arm controller communication
user_io #(.STRLEN($size(CONF_STR)>>3)) user_io (
	.conf_str       ( CONF_STR       ),

	.clk_sys        ( clk_sys        ),

	.SPI_CLK        ( SPI_SCK        ),
	.SPI_SS_IO      ( CONF_DATA0     ),
	.SPI_MISO       ( SPI_DO         ),
	.SPI_MOSI       ( SPI_DI         ),

	.scandoubler_disable ( tv15khz   ),
	.no_csync       ( nocsync ),
	.ypbpr          ( ypbpr ),
	.buttons        ( buttons        ),

	.joystick_0     ( js0            ),
	.joystick_1     ( js1            ),

	.status         ( status         ),
	.key_pressed    (ps2_key_pressed ),
	.key_extended   (ps2_key_ext),
	.key_code       (ps2_key),
	.key_strobe     (ps2_key_stb)
);

wire rom_download = ioctl_download && (ioctl_index == 8'h00 || ioctl_index == 8'h02);
wire prg_download = ioctl_download && (ioctl_index == 8'h41);
wire tap_download = ioctl_download && (ioctl_index == 8'h01);

data_io data_io (
	.clk_sys        ( clk_sys ),
	// SPI interface
	.SPI_SCK        ( SPI_SCK ),
	.SPI_SS2        ( SPI_SS2 ),
	.SPI_DI         ( SPI_DI  ),

	// ram interface
	.ioctl_download ( ioctl_download ),
	.ioctl_index    ( ioctl_index ),
	.ioctl_wr       ( ioctl_wr ),
	.ioctl_addr     ( ioctl_addr ),
	.ioctl_dout     ( ioctl_dout )
);

///////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////

wire  [7:0] cpu_data_out;
wire  [7:0] cpu_data_in;
wire        rnw;

wire we = ~rnw;
wire irq;

wire cpu_reset = reset | rom_download;

T65 cpu
(
    .Mode(0),
    .Res_n(ram_ready & ~cpu_reset),
    .Enable(ce_1m),
    .Clk(clk_sys),
    .Rdy(1),
    .Abort_n(1),
    .IRQ_n(~irq),
    .NMI_n(1),
    .SO_n(1),
    .R_W_n(rnw),
    .A(addr),
    .DI(cpu_data_in),
    .DO(cpu_data_out)
);


///////////////////////////////////////////////////
// Commodore Pet hardware
///////////////////////////////////////////////////

wire pix;
wire HSync, VSync;
wire audioDat;

wire HBlank, VBlank;

wire [7:0] chardata;

pet2001hw hw
(

	.pix(pix),
	.HSync(HSync),
	.VSync(VSync),
	.HBlank(HBlank),
	.VBlank(VBlank),
	
	.keyrow(keyrow),
	.keyin(keyin),
	.reset(reset | rom_download),
	.clk(clk_sys),
	.ce_7mp(ce_7mp),
	.ce_7mn(ce_7mn),
	.ce_1m(ce_1m),

	.addr(addr),
	.we(we),
	.irq(irq),
	.data_out(cpu_data_in),
	.data_in(cpu_data_out),

	.rom_data(rom_byte),
	.charaddr(charaddr[10:0]),
	.chardata(char_byte),
	
	.cass_motor_n(),
	.cass_write(tape_write),
	.audio(audioDat),
	.cass_sense_n(0),
	.cass_read(tape_audio),
	.diag_l(!status[3]),

	.dma_addr(dl_addr),
	.dma_din(dl_data),
	.dma_dout(),
	.dma_we(dl_wr),

	.clk_speed(0),
	.clk_stop(0)
);


////////////////////////////////////////////////////////////////////
// Loading
////////////////////////////////////////////////////////////////////

reg  [15:0] dl_addr;
reg   [7:0] dl_data;
reg         dl_wr;

reg        old_prg_download = 0;
reg  [3:0] state = 0;
reg [15:0] loadaddr;
always @(posedge clk_sys) begin

	dl_wr <= 0;
	old_prg_download <= prg_download;

	if(prg_download) begin
		state <= 0;
		if(ioctl_wr) begin  
			     if(ioctl_addr == 0) loadaddr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) loadaddr[15:8] <= ioctl_dout;
			else begin
				if(loadaddr<'h8000) begin
					dl_addr <= loadaddr;
					dl_data <= ioctl_dout;
					dl_wr   <= 1;
					loadaddr    <= loadaddr + 1'd1;
				end
			end
		end
	end

	if(old_prg_download && ~prg_download) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2a; dl_data <= loadaddr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2b; dl_data <= loadaddr[15:8]; dl_wr <= 1; end
	endcase
	
	if(rom_download) begin // Initial ROM download
		state <= 0;
		if(ioctl_wr) begin
			if(ioctl_addr>='h0400 && ioctl_addr<'h8000) begin
				dl_addr <= ioctl_addr[15:0] + 16'h8000;
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
			end
		end
	end
end


////////////////////////////////////////////////////////////////////
// Video
////////////////////////////////////////////////////////////////////	

wire nocsync;
wire ypbpr;

reg [1:0] red;
reg [1:0] green;
reg [1:0] blue;

always @(posedge clk_sys) begin
	red <= {2{~status[2] & pix}};
	green <= {2{pix}};
	blue <= {2{~status[2] & pix}};
end

mist_video #(.COLOR_DEPTH(2), .OSD_COLOR(3'd5), .SD_HCNT_WIDTH(10), .OSD_AUTO_CE(1)) mist_video (
	.clk_sys     ( clk_sys    ),

	// OSD SPI interface
	.SPI_SCK     ( SPI_SCK    ),
	.SPI_SS3     ( SPI_SS3    ),
	.SPI_DI      ( SPI_DI     ),

	// scanlines (00-none 01-25% 10-50% 11-75%)
	.scanlines   ( scanlines  ),

	// non-scandoubled pixel clock divider 0 - clk_sys/4, 1 - clk_sys/2
	.ce_divider  ( 1'b0       ),

	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	.scandoubler_disable ( tv15khz ),
	// disable csync without scandoubler
`ifdef DEMISTIFY_HDMI
	.no_csync    ( 1'b1 ),
	.ypbpr       (1'b0),
`else
	.no_csync    ( nocsync ),
	// YPbPr always uses composite sync
	.ypbpr       ( ypbpr ),
`endif
	// Rotate OSD [0] - rotate [1] - left or right
	.rotate      ( 2'b00      ),
	// composite-like blending
	.blend       ( 1'b0       ),

	// video in
	.R           (red),
	.G           (green),
	.B           (blue),
	.HSync       ( HSync      ),
	.VSync       ( VSync      ),

	// MiST video output signals
	.VGA_R       ( VGA_R      ),
	.VGA_G       ( VGA_G      ),
	.VGA_B       ( VGA_B      ),
	.VGA_VS      ( VGA_VS     ),
	.VGA_HS      ( VGA_HS     )
);

 
////////////////////////////////////////////////////////////////////
// Audio
////////////////////////////////////////////////////////////////////		

wire [1:0] audio = {audioDat ^ tape_write, tape_audio & tape_active & (status[8:7] == 2)};

wire [7:0] aud_l = {2'b10,audio,4'd0};
wire [7:0] aud_r = aud_l;


wire        tape_audio;
wire        tape_rd;
wire        tape_pause = 0;
wire        tape_active;
wire        tape_write;

tape tape(
	.clk(clk_sys),
	.reset,
	.ce_1m,
	.ioctl_download(tap_download),
	.tape_pause,
	.tape_audio,
	.tape_active,
	.tape_rd,
	.tape_addr,
	.tape_data
);

reg [18:0] act_cnt;
wire       tape_led = act_cnt[18] ? act_cnt[17:10] <= act_cnt[7:0] : act_cnt[17:10] > act_cnt[7:0];

always @(posedge clk_sys) begin
	if( (|status[8:7] ? ce_1m : ce_7mp) && (tape_active || act_cnt[18] || act_cnt[17:0]))
		act_cnt <= act_cnt + 1'd1; 
end

dac ldac (
	.clk_i(clk_sys),
	.res_n_i(!reset),
	.dac_i(aud_l),
	.dac_o(AUDIO_L)
);

dac rdac (
	.clk_i(clk_sys),
	.res_n_i(!reset),
	.dac_i(aud_r),
	.dac_o(AUDIO_R)
);


//////////////////////////////////////////////////////////////////////
// PS/2 to PET keyboard interface
//////////////////////////////////////////////////////////////////////
wire [7:0] 	keyin;
wire [7:0] 	keyin_gfx;
wire [7:0] 	keyin_business;
wire [3:0] 	keyrow;
wire        shift_lock_gfx;
wire        shift_lock_business;
wire        shift_lock;

assign keyin=keyboardtype ? keyin_business : keyin_gfx;
assign shift_lock=keyboardtype ? shift_lock_business : shift_lock_gfx;

keyboard keyboard(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key({ps2_key_stb,ps2_key_pressed,ps2_key_ext,ps2_key}),
	.keyrow(keyrow),
	.keyin(keyin_gfx),
	.shift_lock(shift_lock_gfx),
	.Fn(),
	.mod()
);

businesskeyboard businesskeyboard(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key({ps2_key_stb,ps2_key_pressed,ps2_key_ext,ps2_key}),
	.keyrow(keyrow),
	.keyin(keyin_business),
	.shift_lock(shift_lock_business),
	.Fn(),
	.mod()
);


endmodule

module sram
(
	input        clk,

	input [15:0] addr,
	input  [7:0] din,
	input        we,
	output reg [7:0] dout
);

reg [7:0] data[65536];

always @(posedge clk) begin
	if(we) begin
		data[addr] <= din;
		dout <= din;
	end else begin
		dout <= data[addr];
	end
end

endmodule
