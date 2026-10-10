module
import DartLang.SimpleTypes

/-!
# Tests of the run-time view of `SimpleType`
-/

namespace DartLang

example : RtSubChecker.check 0 SimpleType.Null SimpleType.ObjectQ = some (true, 0) := by
  decide

example : RtSubChecker.check 0 SimpleType.Null SimpleType.Object = some (false, 0) := by
  decide

example : RtSub SimpleType.Null SimpleType.ObjectQ true :=
  RtSubChecker.check_sound
    (by decide : RtSubChecker.check 0 SimpleType.Null SimpleType.ObjectQ = some (true, 0))

end DartLang
