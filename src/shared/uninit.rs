//! Safe writes into caller-provided uninitialized output.

use core::mem::MaybeUninit;

/// Initializes `destination` from `source`, which must have the same length.
///
/// `<[MaybeUninit<u8>]>::write_copy_of_slice` needs Rust 1.93; this loop keeps
/// the 1.89 MSRV and compiles to a `memcpy`. Unequal lengths copy the shorter
/// prefix, which no caller relies on.
#[inline]
pub(crate) fn copy_to_uninit(destination: &mut [MaybeUninit<u8>], source: &[u8]) {
    debug_assert_eq!(destination.len(), source.len());
    for (slot, &byte) in destination.iter_mut().zip(source) {
        slot.write(byte);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copies_every_byte_and_leaves_nothing_else_written() {
        let mut destination = [MaybeUninit::new(0xAA); 6];
        copy_to_uninit(&mut destination[1..5], b"abcd");
        // SAFETY: every element was initialized by the array literal and the copy.
        let bytes = destination.map(|slot| unsafe { slot.assume_init() });
        assert_eq!(&bytes, b"\xAAabcd\xAA");
    }

    #[test]
    fn an_empty_copy_is_a_no_op() {
        copy_to_uninit(&mut [], &[]);
    }
}
