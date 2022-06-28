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
	"O9A,CPU Speed,Normal,x2,x4,x8;",
	"O3,Diag,Off,On(needs Reset);",
	"O2,Screen Color,White,Green;",
	"O45,Scanlines,None,25%,50%,75%;",
	"T0,Reset;",
	"V,v1.00",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;
		
pll pll
(
	.inclk0(CLOCK_27),
	.c0(SDRAM_CLK),
	.c1(clk_sys),
	.locked(pll_locked)
);

reg reset = 1;
reg sdram_reset_n;
always @(posedge clk_sys) begin
	integer   initRESET = 10000000;
	reg [3:0] reset_cnt;

	sdram_reset_n <= initRESET ? 1'b0 : 1'b1;
	
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
wire [6:0] cpu_rates[4] = '{55, 27, 13, 6};

always @(posedge clk_sys) begin
	reg  [2:0] div = 0;
	reg  [6:0] cpu_div = 0;
	reg  [6:0] cpu_rate = 55;

	div <= div + 1'd1;
	ce_7mp  <= !div[2] & !div[1:0];
	ce_7mn  <=  div[2] & !div[1:0];
	
	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == cpu_rate) begin
		cpu_div  <= 0;
		cpu_rate <= (tape_active && !status[8:7]) ? 7'd2 : cpu_rates[status[10:9]];
	end
	ce_1m <= ~(tape_active & ~ram_ready) && !cpu_div;
end


///////////////////////////////////////////////////
// RAM
///////////////////////////////////////////////////

wire ram_ready;

wire [15:0] sdram_din={8'hff,ioctl_dout};
wire [15:0] sdram_dout;
assign tape_data=sdram_dout[7:0];

wire [15:0] sdram_dq_out;
wire [15:0] sdram_dq_in;
wire sdram_drive_dq;

assign SDRAM_DQ = sdram_drive_dq ? sdram_dq_out : {16{1'bz}};
assign sdram_dq_in = SDRAM_DQ;

wire [15:0] addr;
wire [15:0] addr_d;
wire [15:0] rom_dout;
wire [7:0] rom_byte = addr[0] ? rom_dout[7:0] : rom_dout[15:8];
reg rom_req;
wire rom_ack;
reg rom_write;

wire [15:0] charaddr;
assign charaddr[15:11] = 5'b1110_1; // FIXME - too many bits?
wire [15:0] charaddr_d;
wire [15:0] char_dout;
wire [7:0] char_byte = charaddr[0] ? char_dout[7:0] : char_dout[15:8];
reg char_req;
wire char_ack;

always @(posedge clk_sys) begin
	if((addr!=addr_d && !rom_download) || (rom_download && ioctl_wr))
		rom_req<=~rom_req;

	if((charaddr!=charaddr_d && !rom_download )) // || (rom_download && ioctl_wr))
		char_req<=~char_req;

	if (rom_req == rom_ack && char_req == char_ack)
		rom_write<=1'b0;
		
	if (rom_download && ioctl_wr)
		rom_write<=1'b1;
		
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
	.clkref(ce_7mp),
	.sync_en(1'b1),
	.ready(ram_ready),

	// ROM and Char are in tha same bank since they both access the same ROM.
	
	.rom_addr(rom_download ? 16'h3000+ioctl_addr[21:0] : addr[14:0]),
	.rom_dout(rom_dout),
	.rom_din (ioctl_dout),
	.rom_req (rom_req),
	.rom_ack (rom_ack),
	.rom_we (rom_write),

	.char_addr(charaddr[14:0]),
	.char_dout(char_dout),
	.char_din (ioctl_dout),
	.char_req (char_req),
	.char_ack (char_ack),
	.char_we (1'b0),

	.tape_addr(tap_download ? ioctl_addr : tape_addr),
	.tape_we( ioctl_download && ioctl_wr && (ioctl_index == 1))
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
	.ypbpr          ( ),
	.no_csync       ( ),
	.buttons        ( buttons        ),

	.joystick_0     ( js0            ),
	.joystick_1     ( js1            ),

	.status         ( status         ),
	.key_pressed    (ps2_key_pressed ),
	.key_extended   (ps2_key_ext),
	.key_code       (ps2_key),
	.key_strobe     (ps2_key_stb)
);

wire rom_download = ioctl_download && (ioctl_index == 8'h00);
wire prg_download = ioctl_download && (ioctl_index == 8'h01);
wire tap_download = ioctl_download && (ioctl_index == 8'h41);

wire c16_wait = rom_download | prg_download;

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

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;

	dl_wr <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && (ioctl_index == 8'h41)) begin
		state <= 0;
		if(ioctl_wr) begin  
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_dout;
			else begin
				if(addr<'h8000) begin
					dl_addr <= addr;
					dl_data <= ioctl_dout;
					dl_wr   <= 1;
					addr    <= addr + 1'd1;
				end
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index == 8'h41)) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2a; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2b; dl_data <= addr[15:8]; dl_wr <= 1; end
	endcase
	
	if(ioctl_download && !ioctl_index) begin
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

mist_video #(.COLOR_DEPTH(2), .OSD_COLOR(3'd5), .SD_HCNT_WIDTH(10), .OSD_AUTO_CE(0)) mist_video (
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
	.no_csync    ( 1'b0 ),
	// YPbPr always uses composite sync
	.ypbpr       ( 1'b0 ),
	// Rotate OSD [0] - rotate [1] - left or right
	.rotate      ( 2'b00      ),
	// composite-like blending
	.blend       ( 1'b0       ),

	// video in
	.R           ({2{~status[2] & pix}}),
	.G           ({2{pix}}),
	.B           ({2{~status[2] & pix}}),
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
assign AUDIO_L = {audio, 12'd0};
assign AUDIO_R = AUDIO_L;

wire        tape_audio;
wire        tape_rd;
wire [24:0] tape_addr;
wire  [7:0] tape_data;
wire        tape_pause = 0;
wire        tape_active;
wire        tape_write;

tape tape(
	.clk(clk_sys),
	.reset(reset),
	.ce_1m(ce_1m),
	.ioctl_download(ioctl_download && (ioctl_index==1)),
	.tape_pause(tape_pause),
	.tape_audio(tape_audio),
	.tape_active(tape_active),
	.tape_rd(tape_rd),
	.tape_addr(tape_addr),
	.tape_data(tape_data)
);

reg [18:0] act_cnt;
wire       tape_led = act_cnt[18] ? act_cnt[17:10] <= act_cnt[7:0] : act_cnt[17:10] > act_cnt[7:0];
always @(posedge clk_sys) if((|status[8:7] ? ce_1m : ce_7mp) && (tape_active || act_cnt[18] || act_cnt[17:0])) act_cnt <= act_cnt + 1'd1; 


// FIXME - add sigma_delta here...

//////////////////////////////////////////////////////////////////////
// PS/2 to PET keyboard interface
//////////////////////////////////////////////////////////////////////
wire [7:0] 	keyin;
wire [3:0] 	keyrow;	 
wire        shift_lock;

keyboard keyboard(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key({ps2_key_stb,ps2_key_pressed,ps2_key_ext,ps2_key}),
	.keyrow(keyrow),
	.keyin(keyin),
	.shift_lock(shift_lock),
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
