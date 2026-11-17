// Request: A5 5A COMMAND KEY[16] DATA[16], exactly 35 raw bytes.
// First key/data byte maps to [127:120]; last maps to [7:0].
// Collect in private buffers; publish stable fields with a one-cycle valid.
// packet_error (extension to spec 11.3, needed for the spec 12.2 ERROR state):
// pulses for an unknown command; packet_valid stays low, command holds the bad
// value, key/data are zero. The controller must send an error response.
// Recovery:
// - Ignore bytes until A5 5A. A5 A5 5A correctly uses the second A5.
// - Reject unknown commands and immediately resume sync search, retaining an
//   A5 invalid command as a possible first sync byte. Never launch AES on error.
// - Inter-byte timeout: if a request is started but no byte arrives for
//   TIMEOUT_MS milliseconds, the partial request is discarded silently and the
//   parser returns to sync search. A truncated request therefore no longer
//   needs an FPGA reset; the host just waits > TIMEOUT_MS before retrying.
//   The host must send each 35-byte request without pauses >= TIMEOUT_MS.
// - reset abandons any partial request and clears published/buffered data.
// - Once KEY/DATA starts, every byte is payload (including A5 5A), because
//   payloads are arbitrary binary. No checksum exists (spec 10.1).
// Host must wait for each response before sending another request: no queue.
module uart_packet_parser #(
    parameter integer CLK_FREQ_HZ = 50000000,  // placeholder; override from top
    parameter integer TIMEOUT_MS  = 20
)(
    input  wire         clk,
    input  wire         reset,
    input  wire [7:0]   rx_data,
    input  wire         rx_valid,
    output reg  [7:0]   command,
    output reg  [127:0] key,
    output reg  [127:0] data,
    output reg          packet_valid,
    output reg          packet_error
);
    localparam [7:0] CMD_ENCRYPT = 8'h01;
    localparam [7:0] CMD_DECRYPT = 8'h02;
    localparam [2:0] STATE_SYNC_0 = 3'd0;
    localparam [2:0] STATE_SYNC_1 = 3'd1;
    localparam [2:0] STATE_COMMAND = 3'd2;
    localparam [2:0] STATE_KEY = 3'd3;
    localparam [2:0] STATE_DATA = 3'd4;

    reg [2:0] state_reg;
    reg [3:0] byte_index;
    reg [7:0] command_reg;
    reg [127:0] key_reg;
    reg [127:0] data_reg;

    // Inter-byte timeout counter (counts clocks since the last byte while a
    // request is partially received).
    localparam integer TIMEOUT_CLKS =
        ((CLK_FREQ_HZ / 1000) * TIMEOUT_MS < 1) ? 1 : (CLK_FREQ_HZ / 1000) * TIMEOUT_MS;
    reg [31:0] idle_count;
    wire in_request = (state_reg != STATE_SYNC_0);
    wire timed_out  = in_request && !rx_valid && (idle_count >= TIMEOUT_CLKS - 1);

    always @(posedge clk) begin
        if (reset) begin
            state_reg <= STATE_SYNC_0;
            byte_index <= 4'd0;
            command_reg <= 8'h00;
            key_reg <= 128'h0;
            data_reg <= 128'h0;
            command <= 8'h00;
            key <= 128'h0;
            data <= 128'h0;
            packet_valid <= 1'b0;
            packet_error <= 1'b0;
            idle_count <= 32'd0;
        end else begin
            packet_valid <= 1'b0;
            packet_error <= 1'b0;
            if (rx_valid || !in_request)
                idle_count <= 32'd0;
            else if (!timed_out)
                idle_count <= idle_count + 32'd1;

            if (timed_out) begin
                // Partial request abandoned: discard it and search for sync.
                state_reg <= STATE_SYNC_0;
                byte_index <= 4'd0;
                idle_count <= 32'd0;
            end else if (rx_valid) begin
                case (state_reg)
                    STATE_SYNC_0: begin
                        if (rx_data == 8'hA5)
                            state_reg <= STATE_SYNC_1;
                    end
                    STATE_SYNC_1: begin
                        if (rx_data == 8'h5A)
                            state_reg <= STATE_COMMAND;
                        else if (rx_data != 8'hA5)
                            state_reg <= STATE_SYNC_0;
                    end
                    STATE_COMMAND: begin
                        if ((rx_data == CMD_ENCRYPT) ||
                            (rx_data == CMD_DECRYPT)) begin
                            command_reg <= rx_data;
                            key_reg <= 128'h0;
                            data_reg <= 128'h0;
                            byte_index <= 4'd0;
                            state_reg <= STATE_KEY;
                        end else begin
                            command <= rx_data;
                            key <= 128'h0;
                            data <= 128'h0;
                            packet_error <= 1'b1;
                            byte_index <= 4'd0;
                            if (rx_data == 8'hA5)
                                state_reg <= STATE_SYNC_1;
                            else
                                state_reg <= STATE_SYNC_0;
                        end
                    end
                    STATE_KEY: begin
                        key_reg <= {key_reg[119:0], rx_data};
                        if (byte_index == 4'd15) begin
                            byte_index <= 4'd0;
                            state_reg <= STATE_DATA;
                        end else begin
                            byte_index <= byte_index + 4'd1;
                        end
                    end
                    STATE_DATA: begin
                        data_reg <= {data_reg[119:0], rx_data};
                        if (byte_index == 4'd15) begin
                            command <= command_reg;
                            key <= key_reg;
                            data <= {data_reg[119:0], rx_data};
                            packet_valid <= 1'b1;
                            byte_index <= 4'd0;
                            state_reg <= STATE_SYNC_0;
                        end else begin
                            byte_index <= byte_index + 4'd1;
                        end
                    end
                    default: state_reg <= STATE_SYNC_0;
                endcase
            end
        end
    end
endmodule
