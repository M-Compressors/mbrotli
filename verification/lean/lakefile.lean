import Lake
open Lake DSL

-- The same commit as `AENEAS_RELEASE` in `scripts/extract_lean.py`: the
-- generated `Mbrotli/Code.lean` targets this version of the Aeneas library.
require aeneas from git
  "https://github.com/AeneasVerif/aeneas.git" @ "74aabd52f77001cf9eaad51b4f4b867a7dc6b111" / "backends/lean"

package «mbrotli-verification» where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target] lean_lib Mbrotli
