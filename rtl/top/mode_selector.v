// ============================================================================
// mode_selector.v  -  Member 4 (Top-level system)
// ----------------------------------------------------------------------------
// Purely combinational decode of the 8-bit request COMMAND byte
// (Shared Coding Specification, Sections 10.1 and 12.3):
//
//     8'h01  CMD_ENCRYPT  -> select_encrypt = 1
//     8'h02  CMD_DECRYPT  -> select_decrypt = 1
//     other               -> command_error  = 1
//
// Exactly one of the three outputs is high for any input value, so the
// controller can never start both AES cores for the same request.
// No clock, no reset, no state.
// ============================================================================
module mode_selector (
    input  wire [7:0] command,
    output reg        select_encrypt,
    output reg        select_decrypt,
    output reg        command_error
);

    localparam [7:0] CMD_ENCRYPT = 8'h01;
    localparam [7:0] CMD_DECRYPT = 8'h02;

    always @(*) begin
        // Defaults on every path -> no inferred latches.
        select_encrypt = 1'b0;
        select_decrypt = 1'b0;
        command_error  = 1'b0;

        case (command)
            CMD_ENCRYPT: select_encrypt = 1'b1;
            CMD_DECRYPT: select_decrypt = 1'b1;
            default:     command_error  = 1'b1;
        endcase
    end

endmodule
