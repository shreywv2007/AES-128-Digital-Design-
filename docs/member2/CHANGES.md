# Member 2 package - changes made during integration review

1. `aes_decrypt` ports renamed to match the Shared Coding Specification, section 8.2:
   `rst` -> `reset`, `ciphertext` -> `data_in`, `plaintext` -> `data_out`.
   (`aes_decrypt_controller` also uses `reset` now.) No logic was changed.
2. Files moved to the agreed repository layout: `rtl/decryption/*.v`.
   Documentation and the integration example moved to `docs/member2/`.
3. Interface contract, README and example updated to the new port names.
4. `busy`/`done` remain `wire` outputs (driven by the controller). This does not
   affect how Member 4 instantiates the module.
5. Latency is 12 clock edges from accepted start to done (encryption: 11); the
   top-level controller must wait on `done`.
