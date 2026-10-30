/* cc -Imbrotli-ffi/include mbrotli-ffi/examples/sessions.c \
 *    -Ltarget/release -lmbrotli_ffi -Wl,-rpath,target/release -o /tmp/sessions
 */
#include "mbrotli.h"
#include <assert.h>
#include <string.h>

int main(void) {
    const uint8_t input[] = "hello from an owning C session";
    uint8_t encoded[256]; /* No initialization required. */
    uint8_t decoded[sizeof(input)];
    size_t in_len = sizeof(input), out_len = sizeof(encoded);
    mbrotli_encoder_session *encoder = mbrotli_encoder_session_create(5, 22);
    mbrotli_decoder_session *decoder = mbrotli_decoder_session_create();
    assert(encoder && decoder);
    /* For this small example the entire output fits. General callers repeat
     * FINISH with the unconsumed suffix while NEEDS_OUTPUT is returned. */
    assert(mbrotli_encoder_session_process(encoder, input, &in_len,
        encoded, &out_len, MBROTLI_FINISH) == MBROTLI_FINISHED);
    assert(in_len == sizeof(input));
    in_len = out_len;
    out_len = sizeof(decoded);
    assert(mbrotli_decoder_session_process(decoder, encoded, &in_len,
        decoded, &out_len, MBROTLI_FINISH) == MBROTLI_FINISHED);
    assert(out_len == sizeof(input) && memcmp(input, decoded, out_len) == 0);
    assert(mbrotli_encoder_session_reinit(encoder) == MBROTLI_OK);
    assert(mbrotli_decoder_session_reinit(decoder) == MBROTLI_OK);
    out_len = sizeof(encoded);
    assert(mbrotli_encoder_session_flush(encoder, encoded, &out_len) == MBROTLI_NEEDS_INPUT);
    out_len = sizeof(encoded);
    assert(mbrotli_encoder_session_finish(encoder, encoded, &out_len) == MBROTLI_FINISHED);
    out_len = sizeof(decoded);
    assert(mbrotli_decoder_session_flush(decoder, decoded, &out_len) == MBROTLI_NEEDS_INPUT);
    /* EOF without a single member is truncation. */
    out_len = sizeof(decoded);
    assert(mbrotli_decoder_session_finish(decoder, decoded, &out_len) == MBROTLI_ERROR);
    mbrotli_encoder_session_destroy(encoder);
    mbrotli_decoder_session_destroy(decoder);
    return 0;
}
