// ============================================================================
// output_registers.v  -  Member 4 (Top-level system)
// ----------------------------------------------------------------------------
// Captures the response STATUS byte and the 128-bit RESULT for the UART
// packet sender (Section 10.2), and holds them stable for the full 19-byte
// transmission.
//
// * Loads only when `load` is high (one cycle, driven by aes_controller in
//   its CAPTURE_RESULT or ERROR state).
// * On success the controller presents STATUS = 8'h00 and the selected AES
//   core's data_out; on error it presents a nonzero STATUS and 128'd0
//   (Section 10.2: "invalid command -> nonzero status and 16 zero bytes").
// * Values do not change again until the next `load`, which the controller
//   only issues after the previous response has finished (response_done).
//
// Byte order is passed through untouched: byte 0 = bits [127:120].
// Reset: active-high, synchronous.
// ============================================================================
module output_registers (
    input  wire         clk,
    input  wire         reset,
    input  wire         load,
    input  wire [7:0]   status_in,
    input  wire [127:0] result_in,
    output reg  [7:0]   status_out,
    output reg  [127:0] result_out
);

    always @(posedge clk) begin
        if (reset) begin
            status_out <= 8'h00;
            result_out <= 128'd0;
        end else if (load) begin
            status_out <= status_in;
            result_out <= result_in;
        end
    end

endmodule
