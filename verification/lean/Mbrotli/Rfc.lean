module

public import Mathlib.Data.Nat.Log

/-! # RFC 7932, transcribed

The tables of RFC 7932 exactly as the RFC prints them, for the proofs to state
conformance against. Nothing here is derived from the Rust code. Each table
keeps the RFC's own columns (the code, its extra bits and its printed range),
so a transcription error shows up as a failure of the consistency checks at the
end of the file rather than as a silently wrong specification.
-/

@[expose] public section

namespace Mbrotli.Rfc

/-- One row of a length code table: extra bits and the printed range `lo..hi`. -/
structure Row where
  extra : Nat
  lo : Nat
  hi : Nat
deriving DecidableEq

/-- Section 5, the insert length code table (codes 0 to 23). -/
def insertRows : List Row := [
  ⟨0, 0, 0⟩, ⟨0, 1, 1⟩, ⟨0, 2, 2⟩, ⟨0, 3, 3⟩, ⟨0, 4, 4⟩, ⟨0, 5, 5⟩,
  ⟨1, 6, 7⟩, ⟨1, 8, 9⟩, ⟨2, 10, 13⟩, ⟨2, 14, 17⟩, ⟨3, 18, 25⟩, ⟨3, 26, 33⟩,
  ⟨4, 34, 49⟩, ⟨4, 50, 65⟩, ⟨5, 66, 97⟩, ⟨5, 98, 129⟩, ⟨6, 130, 193⟩,
  ⟨7, 194, 321⟩, ⟨8, 322, 577⟩, ⟨9, 578, 1089⟩, ⟨10, 1090, 2113⟩,
  ⟨12, 2114, 6209⟩, ⟨14, 6210, 22593⟩, ⟨24, 22594, 16799809⟩]

/-- Section 5, the copy length code table (codes 0 to 23). -/
def copyRows : List Row := [
  ⟨0, 2, 2⟩, ⟨0, 3, 3⟩, ⟨0, 4, 4⟩, ⟨0, 5, 5⟩, ⟨0, 6, 6⟩, ⟨0, 7, 7⟩,
  ⟨0, 8, 8⟩, ⟨0, 9, 9⟩, ⟨1, 10, 11⟩, ⟨1, 12, 13⟩, ⟨2, 14, 17⟩, ⟨2, 18, 21⟩,
  ⟨3, 22, 29⟩, ⟨3, 30, 37⟩, ⟨4, 38, 53⟩, ⟨4, 54, 69⟩, ⟨5, 70, 101⟩,
  ⟨5, 102, 133⟩, ⟨6, 134, 197⟩, ⟨7, 198, 325⟩, ⟨8, 326, 581⟩,
  ⟨9, 582, 1093⟩, ⟨10, 1094, 2117⟩, ⟨24, 2118, 16779333⟩]

/-- Row `code` of a table; codes past 23 read as an empty row. -/
def row (rows : List Row) (code : Nat) : Row := rows.getD code ⟨0, 0, 0⟩

/-- Section 5, the cell diagram: for the 64-symbol block `symbol / 64`, the
first insert length code and the first copy length code of its 8-by-8 cell.
Blocks 0 and 1 are the cells marked "distance symbol 0". -/
def cells : List (Nat × Nat) := [
  (0, 0), (0, 8),                    -- 0..63, 64..127
  (0, 0), (0, 8), (8, 0), (8, 8),    -- 128..191, 192..255, 256..319, 320..383
  (0, 16), (16, 0), (8, 16),         -- 384..447, 448..511, 512..575
  (16, 8), (16, 16)]                 -- 576..639, 640..703

/-- Number of insert-and-copy length symbols. -/
def commandSymbols : Nat := 704

/-- The insert length code of an insert-and-copy length symbol: its cell's
first insert code plus bits 3..5 of the symbol. -/
def insertCode (symbol : Nat) : Nat := (cells.getD (symbol / 64) (0, 0)).1 + symbol / 8 % 8

/-- The copy length code of an insert-and-copy length symbol: its cell's first
copy code plus bits 0..2 of the symbol. -/
def copyCode (symbol : Nat) : Nat := (cells.getD (symbol / 64) (0, 0)).2 + symbol % 8

/-- Section 5: symbols 0 to 127 set the distance code to zero, reusing the last
distance, and carry no distance symbol. -/
def implicitDistance (symbol : Nat) : Bool := symbol < 128

/-- Section 7.2: the distance context of a command with copy length `len`. -/
def distanceContext (len : Nat) : Nat := if len ≤ 4 then len - 2 else 3

/-- Section 4, the sixteen short distance symbols: which past distance they
refer to (0 is the last distance, 1 the second-to-last, ...) and the offset
added to it. -/
def shortCodes : List (Nat × Int) := [
  (0, 0), (1, 0), (2, 0), (3, 0),   -- last .. fourth-to-last distance
  (0, -1), (0, 1), (0, -2), (0, 2), (0, -3), (0, 3),
  (1, -1), (1, 1), (1, -2), (1, 2), (1, -3), (1, 3)]

/-- Section 4: the ring of the four last distances at the start of the stream,
most recent first ("the last distance to 4", "the second-to-last to 11", ...). -/
def initialRing : List Nat := [4, 11, 15, 16]

/-! ## Consistency of the transcription -/

/-- Every printed range holds exactly `2 ^ extra` lengths. -/
theorem insertRows_width : ∀ r ∈ insertRows, r.hi + 1 = r.lo + 2 ^ r.extra := by decide

theorem copyRows_width : ∀ r ∈ copyRows, r.hi + 1 = r.lo + 2 ^ r.extra := by decide

/-- The ranges follow one another without gaps or overlaps. -/
theorem insertRows_contiguous :
    ∀ i < 23, (row insertRows i).hi + 1 = (row insertRows (i + 1)).lo := by decide

theorem copyRows_contiguous :
    ∀ i < 23, (row copyRows i).hi + 1 = (row copyRows (i + 1)).lo := by decide

theorem insertRows_length : insertRows.length = 24 := rfl
theorem copyRows_length : copyRows.length = 24 := rfl

/-- Every symbol names codes inside both tables. -/
theorem codes_lt : ∀ s < commandSymbols, insertCode s < 24 ∧ copyCode s < 24 := by decide +kernel

end Mbrotli.Rfc

end
