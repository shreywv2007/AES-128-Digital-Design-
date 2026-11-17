// ============================================================================
// status_leds.v  -  Member 4 (Top-level system)
// ----------------------------------------------------------------------------
// Turns the controller's status flags into human-visible, ACTIVE-HIGH logical
// indicator outputs (Section 12.3). Any board-specific active-low inversion
// belongs in the board wrapper / pin mapping, not here.
//
//   led_ready  : level, high while the system is IDLE and can accept a request
//   led_busy   : level, high from request capture until the response is sent
//   led_done   : the one-cycle done pulse (response transmission complete),
//                stretched to HOLD_CYCLES clock cycles so it is visible
//   led_error  : the one-cycle error pulse (invalid command / timeout),
//                stretched to HOLD_CYCLES clock cycles so it is visible
//
// Why stretch: one AES operation takes well under a microsecond and a single
// clock-cycle pulse is invisible on an LED. A new pulse restarts the timer.
// Set HOLD_CYCLES = 1 to pass the raw one-cycle pulses through unchanged
// (useful in simulation).
//
// Reset: active-high, synchronous.
// ============================================================================
module status_leds #(
    parameter integer HOLD_CYCLES = 5000000   // set by aes_top from CLK_FREQ_HZ
) (
    input  wire clk,
    input  wire reset,
    input  wire ready_in,
    input  wire busy_in,
    input  wire done_pulse,
    input  wire error_pulse,
    output wire led_ready,
    output wire led_busy,
    output reg  led_done,
    output reg  led_error
);

    // Width large enough for HOLD_CYCLES (max 2^32-1).
    localparam integer CW = 32;

    reg [CW-1:0] done_cnt;
    reg [CW-1:0] error_cnt;

    assign led_ready = ready_in;
    assign led_busy  = busy_in;

    always @(posedge clk) begin
        if (reset) begin
            done_cnt  <= {CW{1'b0}};
            led_done  <= 1'b0;
        end else if (done_pulse) begin
            done_cnt  <= HOLD_CYCLES - 1;
            led_done  <= 1'b1;
        end else if (done_cnt != {CW{1'b0}}) begin
            done_cnt  <= done_cnt - 1'b1;
            led_done  <= 1'b1;
        end else begin
            led_done  <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            error_cnt <= {CW{1'b0}};
            led_error <= 1'b0;
        end else if (error_pulse) begin
            error_cnt <= HOLD_CYCLES - 1;
            led_error <= 1'b1;
        end else if (error_cnt != {CW{1'b0}}) begin
            error_cnt <= error_cnt - 1'b1;
            led_error <= 1'b1;
        end else begin
            led_error <= 1'b0;
        end
    end

endmodule
