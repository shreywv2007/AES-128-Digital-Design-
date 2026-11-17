# Member 4 – Top-Level Integration (AES-128 FPGA + UART)

Written against the *AES128 FPGA Shared Coding Specification*. Files are in `rtl/top/`. Phase: coding only; this package does **not** include a
testbench or pin constraints.

## Files

| File | Module | Purpose |
|---|---|---|
| `rtl/top/aes_top.v` | `aes_top` | Top level. Port list matches Spec §12.1 exactly. Instantiates every member's modules. |
| `rtl/top/aes_controller.v` | `aes_controller` | System FSM: IDLE → CAPTURE → KEY_READY → START_AES → WAIT_AES → CAPTURE_RESULT → SEND_RESPONSE → WAIT_TX, plus ERROR (§12.2). |
| `rtl/top/input_registers.v` | `input_registers` | Latches command/key/data **only** on the IDLE `packet_valid` pulse. |
| `rtl/top/output_registers.v` | `output_registers` | Latches STATUS + 128-bit RESULT; stays stable during the 19-byte reply. |
| `rtl/top/mode_selector.v` | `mode_selector` | Combinational: `0x01` encrypt, `0x02` decrypt, anything else is an error. |
| `rtl/top/status_leds.v` | `status_leds` | Active-high ready/busy levels; done/error pulses stretched (~100 ms) so they show on an LED. |
| `rtl/top/seven_segment_display.v` | `seven_segment_display` | **Optional**, generic 4-digit hex driver. Not instantiated until the board is known. |

## Compile list (full system)

```
rtl/common/aes_key_expansion.v
rtl/encryption/aes_sbox.v  sub_bytes.v  shift_rows.v  mix_columns.v  add_round_key.v  aes_encrypt.v
rtl/decryption/aes_inv_sbox.v  inv_sub_bytes.v  inv_shift_rows.v  inv_mix_columns.v  aes_decrypt.v
rtl/uart/baud_generator.v  uart_rx.v  uart_tx.v  uart_packet_parser.v  uart_packet_sender.v  uart_interface.v
rtl/top/aes_controller.v  input_registers.v  output_registers.v  mode_selector.v  status_leds.v  aes_top.v
```
Top module: `aes_top`. Override `CLK_FREQ_HZ` with the real board clock (50 MHz is only a placeholder).

## Ports Member 4 instantiates from other members

Members 1 and 2 use the fixed contracts from Spec §7.3, §8.1 and §8.2, unchanged:

- `aes_key_expansion (key[127:0], round_keys[1407:0])`. It is instantiated **once**, and its output feeds both cores.
- `aes_encrypt` / `aes_decrypt` `(clk, reset, start, data_in, round_keys, data_out, busy, done)`.

`uart_interface` (Member 3) is instantiated with its actual ports:
`clk, reset, uart_rx_pin, uart_tx_pin, command, key, data, packet_valid, packet_error,
status, result, response_start, response_busy, response_done` and parameters
`CLK_FREQ_HZ, BAUD_RATE, PARSER_TIMEOUT_MS`.

**Invalid commands.** Member 3's parser rejects an unknown command with a one-cycle
`packet_error` pulse (command = bad value, key/data = 0). `aes_top` ORs `packet_error`
with `packet_valid`, so the controller captures it, `mode_selector` flags it, and the
reply is `STATUS=0x01` with 16 zero bytes. Same 0x01 value as `uart_interface.v` and
`host/aes_uart_demo.py`.

## Behaviour decisions made by Member 4 (please review)

| Topic | Decision |
|---|---|
| STATUS codes | `0x00` OK · `0x01` invalid command · `0x02` AES core timeout (no `done` within 1024 cycles). All nonzero codes return 16 zero bytes. |
| Requests while busy | Ignored. The input registers load only in IDLE. The host must wait for the 19-byte reply before it sends again. |
| `start` | One-cycle pulse to **exactly one** core, only after that core reports `busy = 0`. |
| `status_ready` / `status_busy` | Levels. Ready means IDLE. Busy covers the whole time from capture until the reply is sent. |
| `status_done` | Pulses when the UART reply **finishes** (as §12.3 recommends), stretched to about 100 ms so it can be seen. |
| Reset | External `reset` is active-high. It passes through a 2-flop synchronizer and becomes a synchronous reset. An active-low board button is inverted in the board wrapper. |
| TX watchdog | If `response_done` does not arrive within 4× the time of a full reply, the FSM goes back to IDLE so it cannot lock up. |
| Error LED / FSM state | Available as `led_error_w` and `ctrl_state_w` inside `aes_top`. Wire them to pins once the board is chosen. |

## Timing note: key expansion

`aes_key_expansion` is combinational, as the spec requires. That makes a long path:
`key_reg` → 10 chained S-box/XOR stages → `round_keys` → AES core registers. The key is held
for the whole transaction, and the FSM waits `KEY_SETTLE = 2` cycles before it starts. Two
results are possible:

- If static timing analysis passes at the board clock, nothing needs to change.
- If it fails, add a multicycle constraint from `u_input_registers/key_out_reg*` to the AES core
  state registers. Alternatively, raise `KEY_SETTLE` and add the matching multicycle constraint.

## Still open

1. FPGA board, part number, oscillator frequency, and the pin/IO-standard constraints file.
2. Timing analysis on the real board (see the key-expansion note above).
3. `seven_segment_display.v` is a generic 4-digit multiplexed driver and is not instantiated.
   Some boards (e.g. Intel DE10-Lite) have separate, non-multiplexed, active-low displays,
   so check it against the chosen board before using it.

## Verification (simulation only, Icarus Verilog, 50 MHz clock, 115200 baud)

Full system (`aes_top` with the real Member 1-3 RTL), driven bit-by-bit on `uart_rx_pin`
with request bytes produced by `host/aes_uart_demo.py`, replies decoded from `uart_tx_pin`:

- FIPS-197 Appendix B encrypt -> `3925841D02DC09FBDC118597196A0B32`, and decrypt back.
- Invalid command 0x07 -> STATUS 0x01 with 16 zero bytes.
- 12 further random encrypt/decrypt transactions, checked against a reference AES library.
- `status_ready`/`status_busy` behave as documented; a second request sent during a
  transaction is ignored; reset during a transaction recovers.
- Yosys `synth` + `check`: 0 problems, no latches. Not yet tested on hardware or for timing.
