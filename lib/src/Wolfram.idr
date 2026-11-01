||| The whole wrapper library in one import: `import Wolfram`.
|||
||| The topic modules can still be imported one by one. Not included:
||| `Wolfram.Symbolic.Unsafe`, which is opt-in by design (it builds calls
||| that nothing checks).
module Wolfram

import public Data.Vect
import public Wolfram.FFI
import public Wolfram.List
import public Wolfram.LinAlg
import public Wolfram.Symbolic
import public Wolfram.Calculus
import public Wolfram.Data
import public Wolfram.ODE
import public Wolfram.Export
