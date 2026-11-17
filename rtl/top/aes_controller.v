// ============================================================================
// aes_controller.v  -  Member 4 (Top-level system FSM)
// ----------------------------------------------------------------------------
// Sequences exactly one AES transaction per accepted UART request
// (Shared Coding Specification, Section 12.2):
//
//   IDLE ──packet_valid──> CAPTURE ──valid cmd──> KEY_READY ──> START_AES
//     ^                       │                                    │
//     │                       └─invalid cmd──> ERROR               v
//     │                                          │             WAIT_AES ──timeout──> ERROR
//     │                                          │                 │ selected done
//     │                                          v                 v
//     │                                    SEND_RESPONSE <── CAPTURE_RESULT
//     │                                          │
//     └──────────── response_done ───────── WAIT_TX
//
// State details
//   IDLE           status_ready=1. On the packet_valid pulse, input_load is
//                  asserted IN THE SAME CYCLE so input_registers sample the
//                  parser outputs while they are guaranteed valid.
//   CAPTURE        Registered command is now stable; mode_selector decode is
//                  checked. Invalid command -> ERROR (STATUS_BAD_COMMAND).
//   KEY_READY      Waits KEY_SETTLE_CYCLES (>=1) for the combinational
//                  aes_key_expansion bus to settle from the new key.
//   START_AES      Waits for the selected core's busy=0, then pulses
//                  enc_start OR dec_start for exactly one clock (never both).
//   WAIT_AES       Waits for the SELECTED core's one-cycle done pulse. If it
//                  never arrives within AES_TIMEOUT_CYCLES -> ERROR
//                  (STATUS_AES_TIMEOUT).
//   CAPTURE_RESULT result_load=1 with STATUS_OK; the selected core's data_out
//                  is stable (it holds until the next accepted start).
//   ERROR          result_load=1 with a nonzero status; the top level forces
//                  the 16 result bytes to zero. error_pulse=1 for one cycle.
//   SEND_RESPONSE  Waits for response_busy=0, then pulses response_start.
//   WAIT_TX        Waits for response_done, pulses status_done, -> IDLE.
//                  A TX_TIMEOUT_CYCLES watchdog returns to IDLE if the UART
//                  sender never reports completion (prevents a dead-lock).
//
// Requests arriving while not IDLE are ignored: input_load is only possible
// in IDLE, so a new packet can never corrupt a transaction that is running
// or being transmitted. (The host must wait for the 19-byte response before
// sending the next request.)
//
// Clock: single system clock.  Reset: active-high, synchronous.
// All handshake outputs (input_load, enc_start, dec_start, result_load,
// response_start, done_pulse, error_pulse) are one-cycle pulses.
// ============================================================================
module aes_controller #(
    parameter integer KEY_SETTLE_CYCLES  = 2,
    parameter integer AES_TIMEOUT_CYCLES = 1024,
    parameter integer TX_TIMEOUT_CYCLES  = 1000000
) (
    input  wire       clk,
    input  wire       reset,

    // From UART subsystem (packet parser)
    input  wire       packet_valid,

    // From mode_selector (decode of the REGISTERED command)
    input  wire       select_encrypt,
    input  wire       select_decrypt,
    input  wire       command_error,

    // AES encryption core handshake (Member 1)
    input  wire       enc_busy,
    input  wire       enc_done,
    output reg        enc_start,

    // AES decryption core handshake (Member 2)
    input  wire       dec_busy,
    input  wire       dec_done,
    output reg        dec_start,

    // UART response handshake (Member 3 packet sender)
    input  wire       response_busy,
    input  wire       response_done,
    output reg        response_start,

    // Register control
    output reg        input_load,      // load input_registers
    output reg        result_load,     // load output_registers
    output reg  [7:0] result_status,   // STATUS byte to load with result_load
    output reg        result_from_dec, // 1: result mux selects decrypt core

    // Status
    output reg        status_ready,    // level: IDLE, can accept a request
    output reg        status_busy,     // level: transaction in progress
    output reg        done_pulse,      // pulse: response transmission complete
    output reg        error_pulse,     // pulse: error response being prepared
    output wire [3:0] state_out        // current state (for debug / 7-seg)
);

    // ---------------------------------------------------------------------
    // Response STATUS codes (Section 10.2: 0x00 = success, nonzero = error)
    // ---------------------------------------------------------------------
    localparam [7:0] STATUS_OK          = 8'h00;
    localparam [7:0] STATUS_BAD_COMMAND = 8'h01;
    localparam [7:0] STATUS_AES_TIMEOUT = 8'h02;

    // ---------------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------------
    localparam [3:0] S_IDLE           = 4'd0;
    localparam [3:0] S_CAPTURE        = 4'd1;
    localparam [3:0] S_KEY_READY      = 4'd2;
    localparam [3:0] S_START_AES      = 4'd3;
    localparam [3:0] S_WAIT_AES       = 4'd4;
    localparam [3:0] S_CAPTURE_RESULT = 4'd5;
    localparam [3:0] S_SEND_RESPONSE  = 4'd6;
    localparam [3:0] S_WAIT_TX        = 4'd7;
    localparam [3:0] S_ERROR          = 4'd8;

    reg [3:0]  state_reg, state_next;
    reg [31:0] timer_reg, timer_next;       // shared settle / timeout counter
    reg        op_decrypt_reg, op_decrypt_next; // operation latched in CAPTURE
    reg [7:0]  err_code_reg, err_code_next;     // status for the ERROR state

    assign state_out = state_reg;

    // ---------------------------------------------------------------------
    // Sequential part
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state_reg      <= S_IDLE;
            timer_reg      <= 32'd0;
            op_decrypt_reg <= 1'b0;
            err_code_reg   <= STATUS_OK;
        end else begin
            state_reg      <= state_next;
            timer_reg      <= timer_next;
            op_decrypt_reg <= op_decrypt_next;
            err_code_reg   <= err_code_next;
        end
    end

    // Helpers for the selected core
    wire sel_busy = op_decrypt_reg ? dec_busy : enc_busy;
    wire sel_done = op_decrypt_reg ? dec_done : enc_done;

    // ---------------------------------------------------------------------
    // Combinational next-state and output logic (all outputs defaulted)
    // ---------------------------------------------------------------------
    always @(*) begin
        state_next      = state_reg;
        timer_next      = timer_reg;
        op_decrypt_next = op_decrypt_reg;
        err_code_next   = err_code_reg;

        input_load      = 1'b0;
        enc_start       = 1'b0;
        dec_start       = 1'b0;
        result_load     = 1'b0;
        result_status   = STATUS_OK;
        result_from_dec = op_decrypt_reg;
        response_start  = 1'b0;
        status_ready    = 1'b0;
        status_busy     = 1'b1;
        done_pulse      = 1'b0;
        error_pulse     = 1'b0;

        case (state_reg)
            // -------------------------------------------------------------
            S_IDLE: begin
                status_ready = 1'b1;
                status_busy  = 1'b0;
                timer_next   = 32'd0;
                if (packet_valid) begin
                    input_load = 1'b1;          // sample parser outputs now
                    state_next = S_CAPTURE;
                end
            end

            // -------------------------------------------------------------
            S_CAPTURE: begin
                timer_next = 32'd0;
                if (command_error) begin
                    err_code_next = STATUS_BAD_COMMAND;
                    state_next    = S_ERROR;
                end else begin
                    op_decrypt_next = select_decrypt;
                    state_next      = S_KEY_READY;
                end
            end

            // -------------------------------------------------------------
            S_KEY_READY: begin
                if (timer_reg >= KEY_SETTLE_CYCLES - 1) begin
                    timer_next = 32'd0;
                    state_next = S_START_AES;
                end else begin
                    timer_next = timer_reg + 1'b1;
                end
            end

            // -------------------------------------------------------------
            S_START_AES: begin
                if (!sel_busy) begin
                    enc_start  = ~op_decrypt_reg;
                    dec_start  =  op_decrypt_reg;
                    timer_next = 32'd0;
                    state_next = S_WAIT_AES;
                end else if (timer_reg >= AES_TIMEOUT_CYCLES - 1) begin
                    err_code_next = STATUS_AES_TIMEOUT;
                    state_next    = S_ERROR;
                end else begin
                    timer_next = timer_reg + 1'b1;
                end
            end

            // -------------------------------------------------------------
            S_WAIT_AES: begin
                if (sel_done) begin
                    state_next = S_CAPTURE_RESULT;
                end else if (timer_reg >= AES_TIMEOUT_CYCLES - 1) begin
                    err_code_next = STATUS_AES_TIMEOUT;
                    state_next    = S_ERROR;
                end else begin
                    timer_next = timer_reg + 1'b1;
                end
            end

            // -------------------------------------------------------------
            S_CAPTURE_RESULT: begin
                result_load   = 1'b1;
                result_status = STATUS_OK;
                timer_next    = 32'd0;
                state_next    = S_SEND_RESPONSE;
            end

            // -------------------------------------------------------------
            S_ERROR: begin
                result_load   = 1'b1;
                result_status = err_code_reg;   // nonzero; result forced to 0
                error_pulse   = 1'b1;
                timer_next    = 32'd0;
                state_next    = S_SEND_RESPONSE;
            end

            // -------------------------------------------------------------
            S_SEND_RESPONSE: begin
                if (!response_busy) begin
                    response_start = 1'b1;
                    timer_next     = 32'd0;
                    state_next     = S_WAIT_TX;
                end
            end

            // -------------------------------------------------------------
            S_WAIT_TX: begin
                if (response_done) begin
                    done_pulse    = 1'b1;
                    err_code_next = STATUS_OK;
                    state_next    = S_IDLE;
                end else if (timer_reg >= TX_TIMEOUT_CYCLES - 1) begin
                    error_pulse   = 1'b1;       // sender never finished
                    err_code_next = STATUS_OK;
                    state_next    = S_IDLE;
                end else begin
                    timer_next = timer_reg + 1'b1;
                end
            end

            // -------------------------------------------------------------
            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

endmodule
