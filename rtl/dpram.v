module dpram
# (
	parameter width = 8,
	parameter depth = 16
)
(
	input        clock_a,
	input        clock_b,

	input [depth-1:0] address_a,
	input [depth-1:0] address_b,
	input  [width-1:0] data_a,
	input  [width-1:0] data_b,
	input        wren_a,
	input        wren_b,
	output reg [width-1:0] q_a,
	output reg [width-1:0] q_b
);

reg [7:0] data[65536];

always @(posedge clock_a) begin
	if(wren_a) begin
		data[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= data[address_a];
	end
end

always @(posedge clock_b) begin
	if(wren_b) begin
		data[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= data[address_b];
	end
end

endmodule
