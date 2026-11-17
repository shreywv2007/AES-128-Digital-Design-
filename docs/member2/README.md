# Member 2 — AES-128 Decryption (Verilog-2001)

This is the RTL coding package, with no testbenches, UART source, synthesis, or FPGA constraints. It consumes Member 1's shared `aes_key_expansion` (`rtl/common/`), which is not duplicated here.

## Start here (beginner)

1. Download/unzip the package.
2. In VS Code, use **File -> Open Folder** and select the extracted directory.
3. Open `rtl/decryption/inv_add_round_key.v` first. Understand bitwise XOR: `A ^ K`.
4. Open `rtl/decryption/inv_shift_rows.v`; data bytes are 8 bits each and the `[127 - 8*i -: 8]` syntax selects 8 bits from the high end downward.
5. Open `rtl/decryption/aes_inv_sbox.v`. This is a 256-case combinational lookup table mapping one input byte to one output byte.
6. Open `rtl/decryption/inv_sub_bytes.v`. The `generate` loop creates 16 inverse S-box instances.
7. Open `rtl/decryption/inv_mix_columns.v` — four columns, each 4 bytes, are multiplied by fixed factors in GF(2^8) and XORed.
8. Open `rtl/decryption/aes_decrypt_controller.v` — a small FSM generates 11 step numbers.
9. Open `rtl/decryption/aes_decrypt.v` — this connects the controller to all inverse transformations and selects reverse round keys.
10. Read `docs/member2/MEMBER_1_AND_4_INTERFACE_CONTRACT.md` and share it with teammates.

## File ownership

```
rtl/decryption/
    aes_inv_sbox.v
    inv_sub_bytes.v
    inv_shift_rows.v
    inv_mix_columns.v
    inv_add_round_key.v
    aes_decrypt_controller.v
    aes_decrypt.v
docs/member2/
    README.md
    MEMBER_1_AND_4_INTERFACE_CONTRACT.md
    aes_decrypt_with_key_example.v   (example only; not in the source list)
```

## Core data flow

```
Ciphertext (128 bits)
    |
Initial AddRoundKey with K10
    |
9 inverse rounds with keys K9 ... K1:
    InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns
    |
Final inverse round using K0:
    InvShiftRows -> InvSubBytes -> AddRoundKey
    |
Plaintext (128 bits)
```

## Key interface (important)

This core **does not calculate the round keys**. Member 1 provides `round_keys[1407:0]`, packed with K0 in least-significant 128 bits, K10 in most-significant 128 bits.

This is deliberately different from providing a single `key[127:0]` to the core. The original key is K0, and the AES algorithm also needs K1 through K10. If Member 4 needs a 128-bit key input, the example `docs/member2/aes_decrypt_with_key_example.v` shows how to connect Member 1's key expansion.

## Timing behavior

- Ports: `clk`, `reset` (synchronous, active-high), `start`, `data_in` (ciphertext), `round_keys`, `data_out` (plaintext), `busy`, `done` — as in Shared Coding Specification 8.2.
- Pulse `start=1` for one rising clock edge when not busy.
- At that edge, `data_in` (ciphertext) is captured and the controller enters RUN.
- Next 11 rising clock edges perform the initial XOR, nine inner rounds, and final round.
- After the final edge (12 edges after the accepted start): `data_out` is valid, `done=1` for one clock, and `busy=0`.
- Round-key bus must remain stable between accepted start and done.

## Known-answer values for later validation

- Key: `2B7E151628AED2A6ABF7158809CF4F3C`
- Ciphertext input: `3925841D02DC09FBDC118597196A0B32`
- Expected plaintext: `3243F6A8885A308D313198A2E0370734`

Source: NIST FIPS 197 Appendix B example. Simulated with Icarus Verilog together with Member 1's `aes_key_expansion`: 204 vectors (this one, FIPS-197 C.1, all-zero, all-FF, 200 random) all decrypt correctly; done is one cycle, output is held, start while busy is ignored, and mid-operation reset recovers. Not yet tested for FPGA timing or on hardware.

## Why there is no separate inverse AddRoundKey arithmetic

AES AddRoundKey is bitwise XOR. Since `A ^ K ^ K == A`, encryption and decryption may reuse the same XOR logic. `inv_add_round_key.v` is provided because it was explicitly listed in Member 2's allocation, but can be replaced by Member 1's identical XOR component by team agreement.
