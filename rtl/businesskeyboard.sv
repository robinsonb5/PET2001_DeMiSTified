
module businesskeyboard
(
	input             reset,
	input             clk,

	input      [10:0] ps2_key,

	input       [3:0] keyrow,
	output      [7:0] keyin,
	output reg        shift_lock,

	output reg [11:1] Fn = 0,
	output reg  [2:0] mod = 0
);

wire pressed    = ps2_key[9];
wire [8:0] code = ps2_key[8:0]; // Extended, code

reg  [7:0] keys[10];
wire       release_btn = ~pressed;

assign     keyin = keys[keyrow];

wire       shift = mod[0];

reg old_reset = 0;
reg old_stb;
always @(posedge clk) begin

	old_reset <= reset;

	if(~old_reset & reset)begin
		keys[0] <= 8'hFF;
		keys[1] <= 8'hFF;
		keys[2] <= 8'hFF;
		keys[3] <= 8'hFF;
		keys[4] <= 8'hFF;
		keys[5] <= 8'hFF;
		keys[6] <= 8'hFF;
		keys[7] <= 8'hFF;
		keys[8] <= 8'hFF;
		keys[9] <= 8'hFF;
		shift_lock <= 0;
	end
	
	old_stb <= ps2_key[10];

	if(old_stb != ps2_key[10]) begin
		case(code)
			8'h59: mod[0]<= ~release_btn; // right shift
			8'h12: mod[0]<= ~release_btn; // Left shift
			8'h11: mod[1]<= ~release_btn; // alt
			8'h14: mod[2]<= ~release_btn; // ctrl
			8'h05: Fn[1] <= ~release_btn; // F1
			8'h06: Fn[2] <= ~release_btn; // F2
			8'h04: Fn[3] <= ~release_btn; // F3
			8'h0C: Fn[4] <= ~release_btn; // F4
			8'h03: Fn[5] <= ~release_btn; // F5
			8'h0B: Fn[6] <= ~release_btn; // F6
			8'h83: Fn[7] <= ~release_btn; // F7
			8'h0A: Fn[8] <= ~release_btn; // F8
			8'h01: Fn[9] <= ~release_btn; // F9
			8'h09: Fn[10]<= ~release_btn; // F10
			8'h78: Fn[11]<= ~release_btn; // F11
		endcase

		case(code)
			'h76: begin
						keys[6][6] <= release_btn; // ESC -> STOP
						if(~release_btn) keys[6][6] <= 1;
							else keys[6][6] <= ~shift_lock;
					end
			'h05: begin
						keys[9][4] <= release_btn; // F1 -> RUN
						if(~release_btn) keys[6][6] <= 0;
							else keys[6][6] <= ~shift_lock;
					end
			'h06: begin
						keys[8][4] <= release_btn; // F2 -> CLR
						if(~release_btn) keys[6][6] <= 0;
							else keys[6][6] <= ~shift_lock;
					end
			'h171: begin
						keys[4][7] <= release_btn; // DEL
						if(~release_btn) keys[6][6] <= 1;
							else keys[6][6] <= ~shift_lock;
					end
			'h170: begin
						keys[4][7] <= release_btn; // INSERT
						if(~release_btn) keys[6][6] <= 0;
							else keys[6][6] <= ~shift_lock;
					end
			'h16C: begin
						keys[8][4] <= release_btn; // HOME
						if(~release_btn) keys[6][6] <= 1;
							else keys[6][6] <= ~shift_lock;
					end
			'h172: begin
						keys[5][4] <= release_btn; // DOWN
						if(~release_btn) keys[6][6] <= 1;
							else keys[6][6] <= ~shift_lock;
					end
			'h175: begin
						keys[5][4] <= release_btn; // UP
						if(~release_btn) keys[6][6] <= 0;
							else keys[6][6] <= ~shift_lock;
					end
			'h174: begin
						keys[0][5] <= release_btn; // RIGHT
						if(~release_btn) keys[6][6] <= 1;
							else keys[6][6] <= ~shift_lock;
					end
			'h16B: begin
						keys[0][5] <= release_btn; // LEFT
						if(~release_btn) keys[6][6] <= 0;
							else keys[6][6] <= ~shift_lock;
					end

			'h58: begin
						keys[6][6] <= release_btn ^ shift_lock; // CAPS -> R SHIFT
						if(~release_btn) shift_lock <= ~shift_lock;
					end

			'h59: keys[6][6] <= release_btn ^ shift_lock;  // R SHIFT
			'h12: keys[6][0] <= release_btn;  // SHIFT
			'h1F: keys[8][0] <= release_btn;  // L GUI -> REV ON/OFF
			'h5A: keys[3][4] <= release_btn;  // RETURN
			'h66: keys[4][7] <= release_btn;  // BKSP  -> DEL

			'h1C: keys[3][0] <= release_btn;  // a
			'h32: keys[6][2] <= release_btn;  // b
			'h21: keys[6][1] <= release_btn;  // c
			'h23: keys[3][1] <= release_btn;  // d
			'h24: keys[5][1] <= release_btn;  // e
			'h2B: keys[2][2] <= release_btn;  // f
			'h34: keys[3][2] <= release_btn;  // g
			'h33: keys[2][3] <= release_btn;  // h
			'h43: keys[4][5] <= release_btn;  // i
			'h3B: keys[3][3] <= release_btn;  // j
			'h42: keys[2][5] <= release_btn;  // k
			'h4B: keys[3][5] <= release_btn;  // l
			'h3A: keys[8][3] <= release_btn;  // m
			'h31: keys[7][2] <= release_btn;  // n
			'h44: keys[5][5] <= release_btn;  // o
			'h4D: keys[4][6] <= release_btn;  // p
			'h15: keys[5][0] <= release_btn;  // q
			'h2D: keys[4][2] <= release_btn;  // r
			'h1B: keys[2][1] <= release_btn;  // s
			'h2C: keys[5][2] <= release_btn;  // t
			'h3C: keys[5][3] <= release_btn;  // u
			'h2A: keys[7][1] <= release_btn;  // v
			'h1D: keys[4][1] <= release_btn;  // w
			'h22: keys[8][1] <= release_btn;  // x
			'h35: keys[4][3] <= release_btn;  // y
			'h1A: keys[7][0] <= release_btn;  // z
						
			'h54: keys[5][6] <= release_btn;  // [
			'h5B: keys[2][4] <= release_btn;  // ]
			'h5D: keys[4][4] <= release_btn;  // \
			'h29: keys[8][2] <= release_btn;  // SPACE

			'h16: keys[1][0] <= release_btn ; // 1

			'h1E: keys[0][0] <= release_btn ;  // 2

			'h26: keys[9][1] <= release_btn ;  // 3

			'h25: keys[1][1] <= release_btn ;  // 4

			'h2E: keys[0][1] <= release_btn ;  // 5

			'h36: keys[9][2] <= release_btn ;  // 6

			'h3D: keys[1][2] <= release_btn ;  // 7

			'h3E: keys[3][6] <= release_btn ;  // 8

			'h46: keys[9][3] <= release_btn ;  // 9

			'h45: keys[1][3] <= release_btn ;  // 0

			'h41: keys[7][3] <= release_btn ;  // ,

			'h49: keys[6][3] <= release_btn ;  // .

			'h4A: keys[8][6] <= release_btn ;  // /

			'h4C: keys[2][6] <= release_btn ;  // ;
			
			'h4E: keys[0][3] <= release_btn ;  // -

			'h52: keys[1][2] <= release_btn ;  // '

			'h55: keys[0][3] <= release_btn ;  // =

			// Numeric keypad
			'h70: keys[7][4] <= release_btn; // 0
			'h71: keys[6][4] <= release_btn; // .
			'h69: keys[8][7] <= release_btn; // 1
			'h72: keys[7][7] <= release_btn; // 2
			'h7a: keys[6][7] <= release_btn; // 3
			'h6b: keys[5][7] <= release_btn; // 4
			'h73: keys[2][7] <= release_btn; // 5
			'h74: keys[3][7] <= release_btn; // 6
			'h6c: keys[1][4] <= release_btn; // 7
			'h75: keys[0][4] <= release_btn; // 8
			'h7d: keys[1][7] <= release_btn; // 9

			default:;
		endcase
	end
end

endmodule
