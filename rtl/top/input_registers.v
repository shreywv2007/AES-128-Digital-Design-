// ============================================================================
// input_registers.v  -  Member 4 (Top-level system)
// ----------------------------------------------------------------------------
// Holds the request (command, 128-bit key, 128-bit data block) for the whole
// lifetime of one transaction.
//
// * Loads ONLY when `load` is high. The controller asserts `load` in the same
//   clock cycle as the parser's one-cycle `packet_valid` pulse, and only while
//   the system is IDLE. The parser's outputs are therefore sampled exactly
//   when they are guaranteed valid, and a request that arrives while a
//   transaction is in progress can never overwrite the operands of the
//   running AES operation.
// * Because the key is held here, the combinational aes_key_expansion output
//   (round_keys) stays stable for the entire AES operation (Section 12.2).
//
// Byte order is passed through untouched: byte 0 = bits [127:120]
// (Section 6). This module never reorders bytes.
//
// Reset: active-high, synchronous (Section 5).
// ============================================================================
module input_registers (
    input  wire         clk,
    input  wire         reset,
    input  wire         load,
    input  wire [7:0]   command_in,
    input  wire [127:0] key_in,
    input  wire [127:0] data_in,
    output reg  [7:0]   command_out,
    output reg  [127:0] key_out,
    output reg  [127:0] data_out
);

    always @(posedge clk) begin
        if (reset) begin
            command_out <= 8'h00;
            key_out     <= 128'd0;
            data_out    <= 128'd0;
        end else if (load) begin
            command_out <= command_in;
            key_out     <= key_in;
            data_out    <= data_in;
        end
    end

endmodule
