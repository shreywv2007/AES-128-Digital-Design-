// ============================================================================
// aes_top.v  -  Member 4 (FPGA top level)
// ----------------------------------------------------------------------------
// Connects the four work packages into one system (Shared Coding
// Specification, Sections 7.3, 8, 11.3 and 12):
//
//   uart_rx_pin ─> uart_interface (M3) ─ command/key/data/packet_valid ─┐
//                                                                      v
//                                                       input_registers (M4)
//                                                     key_reg │    data_reg │
//                                                             v             │
//                                            aes_key_expansion (M1)          │
//                                               round_keys[1407:0]           │
//                                                ┌────────┴────────┐         │
//                                                v                 v         │
//                                         aes_encrypt (M1)  aes_decrypt (M2) <┘
//                                                └──── result mux ──┘
//                                                         v
//                                               output_registers (M4)
//                                                         v
//   uart_tx_pin <─ uart_interface (M3) <── status/result/response_start
//
//   aes_controller (M4) sequences everything; mode_selector (M4) decodes the
//   command; status_leds (M4) drives the visible status outputs.
//
// Port list is EXACTLY the Section 12.1 contract. Board-specific LEDs,
// switches and 7-segment pins are to be added once the board is confirmed;
// signals for them (led_error_w, ctrl_state_w) are already available below.
//
// Parameters
//   CLK_FREQ_HZ  board oscillator frequency. 50 MHz is ONLY a placeholder
//                (Section 5) - override it with the real board clock.
//   BAUD_RATE    115200 by default (Section 9).
//
// Reset: the external `reset` is active-high. It is passed through a 2-flop
//        synchronizer so that a push-button reset (asynchronous to clk) is
//        safely turned into the project's synchronous active-high reset.
//        An active-low board button must be inverted in the board wrapper /
//        pin mapping, not here.
// ============================================================================
module aes_top #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer BAUD_RATE   = 115200
) (
    input  wire clk,
    input  wire reset,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire status_ready,
    output wire status_busy,
    output wire status_done
);

    // ---------------------------------------------------------------------
    // Derived parameters
    // ---------------------------------------------------------------------
    // Visible LED stretch for one-cycle done/error pulses: ~100 ms.
    localparam integer LED_HOLD_CYCLES  = (CLK_FREQ_HZ / 10 > 0) ? (CLK_FREQ_HZ / 10) : 1;
    // Clocks for one UART bit, and a generous TX watchdog: 4x the time of a
    // complete 19-byte response (19 bytes * 10 bits/byte).
    localparam integer CLKS_PER_BIT     = (CLK_FREQ_HZ / BAUD_RATE > 0) ? (CLK_FREQ_HZ / BAUD_RATE) : 1;
    localparam integer TX_TIMEOUT       = 4 * 19 * 10 * CLKS_PER_BIT;
    // An iterative AES-128 core needs only tens of cycles; 1024 is a safe
    // upper bound that still turns a hung core into an error response.
    localparam integer AES_TIMEOUT      = 1024;
    // Cycles allowed for the combinational key expansion to settle after the
    // key register changes (see README: multicycle-path note).
    localparam integer KEY_SETTLE       = 2;

    // ---------------------------------------------------------------------
    // Reset synchronizer (active-high in, active-high synchronous out)
    // ---------------------------------------------------------------------
    reg [1:0] reset_sync_reg = 2'b11;
    always @(posedge clk) begin
        reset_sync_reg <= {reset_sync_reg[0], reset};
    end
    wire sys_reset = reset_sync_reg[1];

    // ---------------------------------------------------------------------
    // Internal nets
    // ---------------------------------------------------------------------
    // UART subsystem -> top
    wire [7:0]    rx_command;
    wire [127:0]  rx_key;
    wire [127:0]  rx_data;
    wire          packet_valid;
    wire          packet_error;   // parser rejected an unknown command
    // A rejected command is handled exactly like a request: it is captured
    // (command = bad value, key/data = 0), mode_selector flags command_error,
    // and the controller replies with STATUS 0x01 and 16 zero bytes.
    wire          request_pulse = packet_valid | packet_error;
    // Top -> UART subsystem
    wire [7:0]    tx_status;
    wire [127:0]  tx_result;
    wire          response_start;
    // UART subsystem -> controller
    wire          response_busy;
    wire          response_done;

    // Registered request
    wire [7:0]    command_reg;
    wire [127:0]  key_reg;
    wire [127:0]  data_reg;

    // Mode decode
    wire          select_encrypt;
    wire          select_decrypt;
    wire          command_error;

    // Shared key schedule: K[r] = round_keys[128*r +: 128]
    wire [1407:0] round_keys;

    // AES cores
    wire          enc_start, enc_busy, enc_done;
    wire [127:0]  enc_data_out;
    wire          dec_start, dec_busy, dec_done;
    wire [127:0]  dec_data_out;

    // Controller -> output path
    wire          input_load;
    wire          result_load;
    wire [7:0]    result_status;
    wire          result_from_dec;

    // Status
    wire          ctrl_ready, ctrl_busy, ctrl_done_pulse, ctrl_error_pulse;
    wire [3:0]    ctrl_state_w;        // for a future 7-segment / debug LEDs
    wire          led_error_w;         // for a future board error LED

    // ---------------------------------------------------------------------
    // Member 3: UART subsystem
    // Port names match Member 3's rtl/uart/uart_interface.v (agreed handoff).
    // ---------------------------------------------------------------------
    uart_interface #(
        .CLK_FREQ_HZ       (CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .PARSER_TIMEOUT_MS (20)
    ) u_uart_interface (
        .clk            (clk),
        .reset          (sys_reset),
        .uart_rx_pin    (uart_rx_pin),
        .uart_tx_pin    (uart_tx_pin),
        // request (parser) side
        .command        (rx_command),
        .key            (rx_key),
        .data           (rx_data),
        .packet_valid   (packet_valid),
        .packet_error   (packet_error),
        // response (sender) side
        .status         (tx_status),
        .result         (tx_result),
        .response_start (response_start),
        .response_busy  (response_busy),
        .response_done  (response_done)
    );

    // ---------------------------------------------------------------------
    // Member 4: request capture and decode
    // ---------------------------------------------------------------------
    input_registers u_input_registers (
        .clk         (clk),
        .reset       (sys_reset),
        .load        (input_load),
        .command_in  (rx_command),
        .key_in      (rx_key),
        .data_in     (rx_data),
        .command_out (command_reg),
        .key_out     (key_reg),
        .data_out    (data_reg)
    );

    mode_selector u_mode_selector (
        .command        (command_reg),
        .select_encrypt (select_encrypt),
        .select_decrypt (select_decrypt),
        .command_error  (command_error)
    );

    // ---------------------------------------------------------------------
    // Member 1: shared key expansion (instantiated ONCE, Section 7.3)
    // ---------------------------------------------------------------------
    aes_key_expansion u_key_expansion (
        .key        (key_reg),
        .round_keys (round_keys)
    );

    // ---------------------------------------------------------------------
    // Member 1: encryption core (Section 8.1)
    // ---------------------------------------------------------------------
    aes_encrypt u_aes_encrypt (
        .clk        (clk),
        .reset      (sys_reset),
        .start      (enc_start),
        .data_in    (data_reg),
        .round_keys (round_keys),
        .data_out   (enc_data_out),
        .busy       (enc_busy),
        .done       (enc_done)
    );

    // ---------------------------------------------------------------------
    // Member 2: decryption core (Section 8.2) - same round_keys bus
    // ---------------------------------------------------------------------
    aes_decrypt u_aes_decrypt (
        .clk        (clk),
        .reset      (sys_reset),
        .start      (dec_start),
        .data_in    (data_reg),
        .round_keys (round_keys),
        .data_out   (dec_data_out),
        .busy       (dec_busy),
        .done       (dec_done)
    );

    // ---------------------------------------------------------------------
    // Member 4: system FSM
    // ---------------------------------------------------------------------
    aes_controller #(
        .KEY_SETTLE_CYCLES  (KEY_SETTLE),
        .AES_TIMEOUT_CYCLES (AES_TIMEOUT),
        .TX_TIMEOUT_CYCLES  (TX_TIMEOUT)
    ) u_aes_controller (
        .clk             (clk),
        .reset           (sys_reset),
        .packet_valid    (request_pulse),
        .select_encrypt  (select_encrypt),
        .select_decrypt  (select_decrypt),
        .command_error   (command_error),
        .enc_busy        (enc_busy),
        .enc_done        (enc_done),
        .enc_start       (enc_start),
        .dec_busy        (dec_busy),
        .dec_done        (dec_done),
        .dec_start       (dec_start),
        .response_busy   (response_busy),
        .response_done   (response_done),
        .response_start  (response_start),
        .input_load      (input_load),
        .result_load     (result_load),
        .result_status   (result_status),
        .result_from_dec (result_from_dec),
        .status_ready    (ctrl_ready),
        .status_busy     (ctrl_busy),
        .done_pulse      (ctrl_done_pulse),
        .error_pulse     (ctrl_error_pulse),
        .state_out       (ctrl_state_w)
    );

    // ---------------------------------------------------------------------
    // Member 4: result capture. Success -> selected core output;
    // error (nonzero status) -> 16 zero bytes (Section 10.2).
    // ---------------------------------------------------------------------
    wire [127:0] result_mux = (result_status != 8'h00) ? 128'd0 :
                              (result_from_dec ? dec_data_out : enc_data_out);

    output_registers u_output_registers (
        .clk        (clk),
        .reset      (sys_reset),
        .load       (result_load),
        .status_in  (result_status),
        .result_in  (result_mux),
        .status_out (tx_status),
        .result_out (tx_result)
    );

    // ---------------------------------------------------------------------
    // Member 4: status indicators
    //   status_ready : IDLE, can accept a request            (level)
    //   status_busy  : transaction in progress               (level)
    //   status_done  : response transmission completed,
    //                  stretched ~100 ms to be visible on an LED
    // ---------------------------------------------------------------------
    status_leds #(
        .HOLD_CYCLES (LED_HOLD_CYCLES)
    ) u_status_leds (
        .clk         (clk),
        .reset       (sys_reset),
        .ready_in    (ctrl_ready),
        .busy_in     (ctrl_busy),
        .done_pulse  (ctrl_done_pulse),
        .error_pulse (ctrl_error_pulse),
        .led_ready   (status_ready),
        .led_busy    (status_busy),
        .led_done    (status_done),
        .led_error   (led_error_w)
    );

endmodule
