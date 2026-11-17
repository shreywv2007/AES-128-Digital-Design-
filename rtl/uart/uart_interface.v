// Member 3 UART wrapper. All controls are active high; reset is synchronous.
// Member 4 connects aes_top's clk/reset/uart_rx_pin/uart_tx_pin directly here
// and forwards its actual CLK_FREQ_HZ and BAUD_RATE parameters.
// CLK_FREQ_HZ = 50000000 is the specification's placeholder only; the board
// and its oscillator are not yet confirmed by the team.
//
// To controller/input_registers:
//   command[7:0], key[127:0], data[127:0], packet_valid (one clk).
//   packet_error (one clk): invalid command; key/data are zero. This port is
//   an extension to spec 11.3 that the controller needs for its ERROR state.
// From controller/output_registers:
//   status[7:0], result[127:0], response_start (one clk, while !response_busy).
//   status: 8'h00 = success (STATUS_OK); 8'h01 = invalid command
//   (STATUS_INVALID_COMMAND, proposed; same value in host/aes_uart_demo.py).
//   For an error the sender transmits 16 zero result bytes automatically.
//   status/result are snapshotted when response_start is accepted.
// To controller:
//   response_busy covers all 19 bytes; response_done pulses after final stop.
//   It describes transmission ONLY, not AES processing or system readiness.
//
// One outstanding request: the host sends one request and waits for its
// reply. The controller should ignore packet_valid/packet_error while busy.
// A partially received request is discarded after PARSER_TIMEOUT_MS of
// silence (see uart_packet_parser.v), so no FPGA reset is needed to recover.
// Dependencies: uart_rx, uart_tx, uart_packet_parser, uart_packet_sender,
// baud_generator. No dependency on a teammate's AES implementation.
module uart_interface #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer BAUD_RATE = 115200,
    parameter integer PARSER_TIMEOUT_MS = 20
)(
    input  wire         clk,
    input  wire         reset,
    input  wire         uart_rx_pin,
    output wire         uart_tx_pin,
    output wire [7:0]   command,
    output wire [127:0] key,
    output wire [127:0] data,
    output wire         packet_valid,
    output wire         packet_error,
    input  wire [7:0]   status,
    input  wire [127:0] result,
    input  wire         response_start,
    output wire         response_busy,
    output wire         response_done
);
    wire [7:0] rx_data;
    wire rx_valid;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;

    // Response status values (shared with host/aes_uart_demo.py).
    localparam [7:0] STATUS_OK              = 8'h00;
    localparam [7:0] STATUS_INVALID_COMMAND = 8'h01;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .clk(clk), .reset(reset), .rx_serial(uart_rx_pin),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    uart_packet_parser #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .TIMEOUT_MS(PARSER_TIMEOUT_MS)
    ) u_uart_packet_parser (
        .clk(clk), .reset(reset), .rx_data(rx_data), .rx_valid(rx_valid),
        .command(command), .key(key), .data(data),
        .packet_valid(packet_valid), .packet_error(packet_error)
    );

    uart_packet_sender u_uart_packet_sender (
        .clk(clk), .reset(reset), .status(status), .result(result),
        .response_start(response_start), .response_busy(response_busy),
        .response_done(response_done), .tx_data(tx_data),
        .tx_start(tx_start), .tx_busy(tx_busy)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk(clk), .reset(reset), .tx_data(tx_data), .tx_start(tx_start),
        .tx_serial(uart_tx_pin), .tx_busy(tx_busy)
    );
endmodule
