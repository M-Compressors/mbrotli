fn main() {
    let context = mbrotli_afl::Context::default();
    afl::fuzz!(|data: &[u8]| mbrotli_afl::session_targets::encoder_session(&context, data));
}
