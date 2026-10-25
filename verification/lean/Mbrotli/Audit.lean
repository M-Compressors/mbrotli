import Mbrotli.DistanceRoundTrip
import Mbrotli.DistanceUniqueness
import Mbrotli.LengthRoundTrip
import Mbrotli.EncoderCommand
import Mbrotli.DecoderDistanceResolve

/-! # Axiom audit

The headline theorems may rely only on Lean's standard axioms. A `sorry`, a
`native_decide` or an unmodelled standard-library item would add an axiom to
these lists and fail the build.
-/

/-- info: 'mbrotli.distance_round_trip' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mbrotli.distance_round_trip

/--
info: 'mbrotli.large_distance_round_trip' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.large_distance_round_trip

/-- info: 'mbrotli.distance_code_unique' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mbrotli.distance_code_unique

/--
info: 'mbrotli.large_distance_code_unique' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.large_distance_code_unique

/-- info: 'mbrotli.length_round_trip' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mbrotli.length_round_trip

/--
info: 'mbrotli.length_code_unique' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.length_code_unique

/-- info: 'mbrotli.commands.spec' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms mbrotli.commands.spec

/--
info: 'mbrotli.command_round_trip' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.command_round_trip

/--
info: 'mbrotli.DistanceLayout.resolve.spec' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.DistanceLayout.resolve.spec

/--
info: 'mbrotli.validated_resolve' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.validated_resolve

/--
info: 'mbrotli.Cache.pop_push' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.Cache.pop_push

/--
info: 'mbrotli.Cache.default.spec' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms mbrotli.Cache.default.spec
