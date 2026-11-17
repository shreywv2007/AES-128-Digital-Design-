# Member 3 package - changes made during integration review

1. Interrupted-request recovery (was: FPGA reset required).
   `uart_packet_parser` now has parameters `CLK_FREQ_HZ` and `TIMEOUT_MS`
   (default 20). If a request has started but no byte arrives for TIMEOUT_MS,
   the partial request is discarded silently and the parser returns to sync
   search. `uart_interface` forwards `CLK_FREQ_HZ` and a new parameter
   `PARSER_TIMEOUT_MS` (default 20). No ports and no packet format changed.
2. Status codes defined: 0x00 = success, 0x01 = invalid command, as
   `STATUS_OK` / `STATUS_INVALID_COMMAND` in `uart_interface.v` and in
   `host/aes_uart_demo.py` (which now prints "invalid command" for 0x01).
3. `packet_error` kept. It is an extension to spec 11.3, needed for the
   spec 12.2 ERROR state; Member 4 must connect it.
4. Removed the reference to a specific board (DE10-Lite) from comments; the
   board is still unconfirmed in the shared specification.
5. Host script recovery messages updated: wait > 20 ms and retry; reset the
   FPGA only if it still does not answer.

Simulated (Icarus Verilog, 50 MHz clock, 115200 baud, serial bit-level):
requests built by host/aes_uart_demo.py are parsed correctly for encrypt and
decrypt, an invalid command raises packet_error, sync is found after junk
bytes, the 19-byte response is correct for success and error, a mid-packet
reset recovers, and a truncated request recovers via the timeout without reset.
