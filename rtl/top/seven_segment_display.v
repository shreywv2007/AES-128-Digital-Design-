// ============================================================================
// seven_segment_display.v  -  Member 4 (OPTIONAL)
// ----------------------------------------------------------------------------
// Generic multiplexed 4-digit hexadecimal 7-segment driver. It is NOT
// instantiated in aes_top yet, because the board (digit count, segment
// order, common-anode vs common-cathode) is not confirmed.
//
// Suggested use once the board is known: show {4'h0, ctrl_state_w,
// tx_status} i.e. the controller state and the last response STATUS.
//
//   value[15:12] -> digit 3 (leftmost) ... value[3:0] -> digit 0
//   seg[6:0]     -> segments {g,f,e,d,c,b,a}, ACTIVE-HIGH (1 = lit)
//   digit_en[3:0]-> one-hot digit enable, ACTIVE-HIGH
//   Invert seg / digit_en in the board wrapper for active-low hardware.
//
// REFRESH_CYCLES = clocks per digit (aim for ~1 kHz per digit).
// Reset: active-high, synchronous.
// ============================================================================
module seven_segment_display #(
    parameter integer REFRESH_CYCLES = 50000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] value,
    output reg  [6:0]  seg,
    output reg  [3:0]  digit_en
);

    reg [31:0] refresh_cnt;
    reg [1:0]  digit_sel;
    reg [3:0]  nibble;

    always @(posedge clk) begin
        if (reset) begin
            refresh_cnt <= 32'd0;
            digit_sel   <= 2'd0;
        end else if (refresh_cnt >= REFRESH_CYCLES - 1) begin
            refresh_cnt <= 32'd0;
            digit_sel   <= digit_sel + 1'b1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
        end
    end

    always @(*) begin
        case (digit_sel)
            2'd0: begin nibble = value[3:0];   digit_en = 4'b0001; end
            2'd1: begin nibble = value[7:4];   digit_en = 4'b0010; end
            2'd2: begin nibble = value[11:8];  digit_en = 4'b0100; end
            default: begin nibble = value[15:12]; digit_en = 4'b1000; end
        endcase
    end

    //                gfedcba
    always @(*) begin
        case (nibble)
            4'h0: seg = 7'b0111111;
            4'h1: seg = 7'b0000110;
            4'h2: seg = 7'b1011011;
            4'h3: seg = 7'b1001111;
            4'h4: seg = 7'b1100110;
            4'h5: seg = 7'b1101101;
            4'h6: seg = 7'b1111101;
            4'h7: seg = 7'b0000111;
            4'h8: seg = 7'b1111111;
            4'h9: seg = 7'b1101111;
            4'hA: seg = 7'b1110111;
            4'hB: seg = 7'b1111100;
            4'hC: seg = 7'b0111001;
            4'hD: seg = 7'b1011110;
            4'hE: seg = 7'b1111001;
            default: seg = 7'b1110001; // F
        endcase
    end

endmodule
