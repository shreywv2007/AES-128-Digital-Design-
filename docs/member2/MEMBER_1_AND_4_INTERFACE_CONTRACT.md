# Interface contract — send this to Members 1 and 4

## Decryption RTL interface

```verilog
module aes_decrypt (
    input  wire          clk,
    input  wire          reset,       // synchronous, active-high
    input  wire          start,
    input  wire [127:0]  data_in,     // ciphertext
    input  wire [1407:0] round_keys,
    output reg  [127:0]  data_out,    // plaintext
    output wire          busy,
    output wire          done
);
```

## Required from Member 1

- AES-128 **forward** key schedule, providing K0..K10 (11 keys, 128 bits each).
- Pack into one bus EXACTLY as:
  - `round_keys[127:0] = K0` (the original 128-bit secret key)
  - `round_keys[255:128] = K1`
  - ...
  - `round_keys[1407:1280] = K10` (the last round key)
- If the existing key expansion packs keys differently, **adapt with a wrapper**; do not rewrite the AES decryption math.
- Member 1's `aes_key_expansion` (in `rtl/common/`) already matches this packing and is combinational; it has been simulated with this core against 204 AES-128 vectors including FIPS-197 Appendix B.

## Required from Member 4

- `reset`: synchronous active-HIGH reset; must be stable around a rising `clk` edge.
- `start`: one rising-edge sample high while `busy=0` (single-clock pulse).
- Inputs: `data_in` (ciphertext) must be valid at the accepted `start` edge; `round_keys` remain stable through `done`.
- `busy`: high throughout all 11 processing cycles (`busy`/`done` are declared `wire` because they come from `aes_decrypt_controller`; this does not affect instantiation).
- Latency: `done` pulses 12 clock edges after the accepted `start` edge (encryption core: 11). The controller must wait for `done`, not count cycles.
- `done`: one-clock pulse produced at the end of the last processing cycle.
- `data_out` (plaintext): registered result, valid when `done=1`; holds until next result or reset.
- All core signals use one system clock; UART framing and packet parsing are Member 3's job.
- State byte order: first 8-bit byte at `[127:120]` and last at `[7:0]`.

## Physical project integration

The decryption core does not parse UART packets or drive LEDs or 7-segment displays.
Member 4 connects the `busy`/`done` status to indicators and forwards the 128-bit result to Member 3's UART packet sender.

## Caution

The full core has combinational inverse S-box and column-mixing paths between clocked state registers. Later synthesis/timing analysis may require optimizations depending on the FPGA and clock period. No hardware timing guarantee is made here.
