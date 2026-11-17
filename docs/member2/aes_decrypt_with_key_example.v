// INTEGRATION EXAMPLE ONLY - not part of the synthesizable source list.
// Shows how Member 4 connects Member 1's combinational aes_key_expansion
// (rtl/common/aes_key_expansion.v) to the decryption core. Member 4's aes_top
// should instead instantiate aes_key_expansion once and share round_keys
// between aes_encrypt and aes_decrypt (Shared Coding Specification 7.3).
module aes_decrypt_with_key_example (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [127:0] data_in,    // ciphertext
    input  wire [127:0] key,
    output wire [127:0] data_out,   // plaintext
    output wire         busy,
    output wire         done
);
    wire [1407:0] round_keys;

    aes_key_expansion u_keys (
        .key(key),
        .round_keys(round_keys)
    );

    aes_decrypt u_decrypt (
        .clk(clk), .reset(reset), .start(start),
        .data_in(data_in),
        .round_keys(round_keys),
        .data_out(data_out),
        .busy(busy), .done(done)
    );
endmodule
