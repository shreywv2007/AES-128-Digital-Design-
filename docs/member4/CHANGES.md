# Member 4 package - changes made during integration review

1. `aes_top.v`: `uart_interface` instance used `.rx_serial/.tx_serial`, which are not
   ports of Member 3's module (full system failed to compile). Changed to
   `.uart_rx_pin/.uart_tx_pin`.
2. `aes_top.v`: connected Member 3's `packet_error` and fed
   `packet_valid | packet_error` to the controller, so an invalid command now gets the
   STATUS 0x01 reply (previously the host would get no reply and time out).
3. `aes_top.v`: passes `PARSER_TIMEOUT_MS (20)` to `uart_interface`.
4. README moved to `docs/member4/README.md` and updated with the final UART ports and
   full-system simulation results. No changes to the controller, registers, mode
   selector, LEDs or seven-segment files.
