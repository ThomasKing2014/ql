/**
 * Provides predicates for working with the internal logic of the `Guards`
 * library.
 */

import java
import semmle.code.java.controlflow.Guards
private import Preconditions
private import semmle.code.java.dataflow.SSA
private import semmle.code.java.dataflow.internal.BaseSSA
private import semmle.code.java.dataflow.NullGuards
private import semmle.code.java.dataflow.IntegerGuards

/**
 * Holds if the assumption that `g1` has been evaluated to `b1` implies that
 * `g2` has been evaluated to `b2`, that is, the evaluation of `g2` to `b2`
 * dominates the evaluation of `g1` to `b1`.
 *
 * Restricted to BaseSSA-based reasoning.
 */
predicate implies_v1(Guard g1, boolean b1, Guard g2, boolean b2) {
  g1.(ParExpr).getExpr() = g2 and
  b1 = b2 and
  (b1 = true or b1 = false)
  or
  g1.(AndBitwiseExpr).getAnOperand() = g2 and b1 = true and b2 = true
  or
  g1.(OrBitwiseExpr).getAnOperand() = g2 and b1 = false and b2 = false
  or
  g1.(AndLogicalExpr).getAnOperand() = g2 and b1 = true and b2 = true
  or
  g1.(OrLogicalExpr).getAnOperand() = g2 and b1 = false and b2 = false
  or
  g1.(LogNotExpr).getExpr() = g2 and
  b1 = b2.booleanNot() and
  (b1 = true or b1 = false)
  or
  exists(EqualityTest eqtest, boolean polarity, BooleanLiteral boollit |
    eqtest = g1 and
    eqtest.hasOperands(g2, boollit) and
    eqtest.polarity() = polarity and
    (b1 = true or b1 = false) and
    b2 = b1.booleanXor(polarity).booleanXor(boollit.getBooleanValue())
  )
  or
  exists(ConditionalExpr cond, boolean branch, BooleanLiteral boollit, boolean boolval |
    cond.getTrueExpr() = boollit and branch = true
    or
    cond.getFalseExpr() = boollit and branch = false
  |
    cond = g1 and
    boolval = boollit.getBooleanValue() and
    b1 = boolval.booleanNot() and
    (
      g2 = cond.getCondition() and b2 = branch.booleanNot()
      or
      g2 = cond.getTrueExpr() and b2 = b1
      or
      g2 = cond.getFalseExpr() and b2 = b1
    )
  )
  or
  g1.(DefaultCase).getSwitch().getAConstCase() = g2 and b1 = true and b2 = false
  or
  exists(MethodAccess check | check = g1 |
    conditionCheck(check, _) and
    g2 = check.getArgument(0) and
    (b1 = true or b1 = false) and
    b2 = b1
  )
  or
  exists(BaseSsaUpdate vbool |
    vbool.getAUse() = g1 and
    vbool.getDefiningExpr().(VariableAssign).getSource() = g2 and
    (b1 = true or b1 = false) and
    b2 = b1
  )
}

/**
 * Holds if the assumption that `g1` has been evaluated to `b1` implies that
 * `g2` has been evaluated to `b2`, that is, the evaluation of `g2` to `b2`
 * dominates the evaluation of `g1` to `b1`.
 *
 * Allows full use of SSA but is restricted to pre-RangeAnalysis reasoning.
 */
predicate implies_v2(Guard g1, boolean b1, Guard g2, boolean b2) {
  implies_v1(g1, b1, g2, b2)
  or
  exists(SsaExplicitUpdate vbool |
    vbool.getAUse() = g1 and
    vbool.getDefiningExpr().(VariableAssign).getSource() = g2 and
    (b1 = true or b1 = false) and
    b2 = b1
  )
  or
  exists(SsaVariable v, AbstractValue k |
    // If `v = g2 ? k : ...` or `v = g2 ? ... : k` then a guard
    // proving `v != k` ensures that `g2` evaluates to `b2`.
    conditionalAssignVal(v, g2, b2.booleanNot(), k) and
    guardImpliesNotEqual1(g1, b1, v, k)
  )
  or
  exists(SsaVariable v, Expr e, AbstractValue k |
    // If `v = g2 ? k : ...` and all other assignments to `v` are different from
    // `k` then a guard proving `v == k` ensures that `g2` evaluates to `b2`.
    uniqueValue(v, e, k) and
    guardImpliesEqual(g1, b1, v, k) and
    g2.directlyControls(e.getBasicBlock(), b2) and
    not g2.directlyControls(getBasicBlockOfGuard(g1), b2)
  )
}

/**
 * Holds if the assumption that `g1` has been evaluated to `b1` implies that
 * `g2` has been evaluated to `b2`, that is, the evaluation of `g2` to `b2`
 * dominates the evaluation of `g1` to `b1`.
 */
cached
predicate implies_v3(Guard g1, boolean b1, Guard g2, boolean b2) {
  implies_v2(g1, b1, g2, b2)
  or
  exists(SsaVariable v, AbstractValue k |
    // If `v = g2 ? k : ...` or `v = g2 ? ... : k` then a guard
    // proving `v != k` ensures that `g2` evaluates to `b2`.
    conditionalAssignVal(v, g2, b2.booleanNot(), k) and
    guardImpliesNotEqual2(g1, b1, v, k)
  )
  or
  exists(SsaVariable v |
    conditionalAssign(v, g2, b2.booleanNot(), clearlyNotNullExpr()) and
    guardImpliesEqual(g1, b1, v, TAbsValNull())
  )
}

private newtype TAbstractValue =
  TAbsValNull() or
  TAbsValInt(int i) { exists(CompileTimeConstantExpr c | c.getIntValue() = i) } or
  TAbsValChar(string c) { exists(CharacterLiteral lit | lit.getValue() = c) } or
  TAbsValString(string s) { exists(StringLiteral lit | lit.getValue() = s) } or
  TAbsValEnum(EnumConstant c)

/** The value of a constant expression. */
abstract private class AbstractValue extends TAbstractValue {
  abstract string toString();

  /** Gets an expression whose value is this abstract value. */
  abstract Expr getExpr();
}

private class AbsValNull extends AbstractValue, TAbsValNull {
  override string toString() { result = "null" }

  override Expr getExpr() { result = alwaysNullExpr() }
}

private class AbsValInt extends AbstractValue, TAbsValInt {
  int i;

  AbsValInt() { this = TAbsValInt(i) }

  override string toString() { result = i.toString() }

  override Expr getExpr() { result.(CompileTimeConstantExpr).getIntValue() = i }
}

private class AbsValChar extends AbstractValue, TAbsValChar {
  string c;

  AbsValChar() { this = TAbsValChar(c) }

  override string toString() { result = c }

  override Expr getExpr() { result.(CharacterLiteral).getValue() = c }
}

private class AbsValString extends AbstractValue, TAbsValString {
  string s;

  AbsValString() { this = TAbsValString(s) }

  override string toString() { result = s }

  override Expr getExpr() { result.(CompileTimeConstantExpr).getStringValue() = s }
}

private class AbsValEnum extends AbstractValue, TAbsValEnum {
  EnumConstant c;

  AbsValEnum() { this = TAbsValEnum(c) }

  override string toString() { result = c.toString() }

  override Expr getExpr() { result = c.getAnAccess() }
}

/**
 * Holds if `v` can have a value that is not representable as an `AbstractValue`.
 */
private predicate hasPossibleUnknownValue(SsaVariable v) {
  exists(SsaVariable def | v.getAnUltimateDefinition() = def |
    def instanceof SsaImplicitUpdate
    or
    def instanceof SsaImplicitInit
    or
    exists(VariableUpdate upd | upd = def.(SsaExplicitUpdate).getDefiningExpr() |
      not exists(upd.(VariableAssign).getSource())
    )
    or
    exists(VariableAssign a, Expr e |
      a = def.(SsaExplicitUpdate).getDefiningExpr() and
      e = possibleValue(a.getSource()) and
      not exists(AbstractValue val | val.getExpr() = e)
    )
  )
}

/**
 * Gets a sub-expression of `e` whose value can flow to `e` through
 * `ConditionalExpr`s. Parentheses are also removed.
 */
private Expr possibleValue(Expr e) {
  result = possibleValue(e.(ParExpr).getExpr())
  or
  result = possibleValue(e.(ConditionalExpr).getTrueExpr())
  or
  result = possibleValue(e.(ConditionalExpr).getFalseExpr())
  or
  result = e and not e instanceof ParExpr and not e instanceof ConditionalExpr
}

/**
 * Gets an ultimate definition of `v` that is not itself a phi node. The
 * boolean `fromBackEdge` indicates whether the flow from `result` to `v` goes
 * through a back edge.
 */
SsaVariable getADefinition(SsaVariable v, boolean fromBackEdge) {
  result = v and not v instanceof SsaPhiNode and fromBackEdge = false
  or
  exists(SsaVariable inp, BasicBlock bb, boolean fbe |
    v.(SsaPhiNode).hasInputFromBlock(inp, bb) and
    result = getADefinition(inp, fbe) and
    (if v.getBasicBlock().bbDominates(bb) then fromBackEdge = true else fromBackEdge = fbe)
  )
}

/**
 * Holds if `e` equals `k` and may be assigned to `v`. The boolean
 * `fromBackEdge` indicates whether the flow from `e` to `v` goes through a
 * back edge.
 */
private predicate possibleValue(SsaVariable v, boolean fromBackEdge, Expr e, AbstractValue k) {
  not hasPossibleUnknownValue(v) and
  exists(SsaExplicitUpdate def |
    def = getADefinition(v, fromBackEdge) and
    e = possibleValue(def.getDefiningExpr().(VariableAssign).getSource().getProperExpr()) and
    k.getExpr() = e
  )
}

/**
 * Holds if `e` equals `k` and may be assigned to `v` without going through
 * back edges, and all other possible ultimate definitions of `v` are different
 * from `k`. The trivial case where `v` is an `SsaExplicitUpdate` with `e` as
 * the only possible value is excluded.
 */
private predicate uniqueValue(SsaVariable v, Expr e, AbstractValue k) {
  possibleValue(v, false, e, k) and
  forex(Expr other, AbstractValue otherval | possibleValue(v, _, other, otherval) and other != e |
    otherval != k
  )
}

/**
 * Holds if `guard` evaluating to `branch` implies that `v` equals `k`.
 */
private predicate guardImpliesEqual(Guard guard, boolean branch, SsaVariable v, AbstractValue k) {
  guard.isEquality(v.getAUse(), k.getExpr(), branch)
}

private BasicBlock getBasicBlockOfGuard(Guard g) {
  result = g.(Expr).getControlFlowNode().getBasicBlock() or
  result = g.(SwitchCase).getSwitch().getExpr().getProperExpr().getControlFlowNode().getBasicBlock()
}

private ControlFlowNode getAGuardBranchSuccessor(Guard g, boolean branch) {
  result = g.(Expr).getControlFlowNode().(ConditionNode).getABranchSuccessor(branch)
  or
  result = g.(SwitchCase).getControlFlowNode() and branch = true
}

/**
 * Holds if `v` is conditionally assigned `e` under the condition that `guard` evaluates to `branch`.
 */
private predicate conditionalAssign(SsaVariable v, Guard guard, boolean branch, Expr e) {
  exists(ConditionalExpr c |
    v.(SsaExplicitUpdate).getDefiningExpr().(VariableAssign).getSource().getProperExpr() = c and
    guard = c.getCondition().getProperExpr()
  |
    branch = true and e = c.getTrueExpr().getProperExpr()
    or
    branch = false and e = c.getFalseExpr().getProperExpr()
  )
  or
  exists(SsaExplicitUpdate upd, SsaPhiNode phi |
    guard.directlyControls(upd.getBasicBlock(), branch) and
    upd.getDefiningExpr().(VariableAssign).getSource().getProperExpr() = e and
    phi = v and
    upd = phi.getAPhiInput() and
    getBasicBlockOfGuard(guard).bbStrictlyDominates(phi.getBasicBlock()) and
    not guard.directlyControls(phi.getBasicBlock(), branch) and
    forall(SsaVariable other | other != upd and other = phi.getAPhiInput() |
      guard.directlyControls(other.getBasicBlock(), branch.booleanNot())
      or
      other.getBasicBlock().bbDominates(getBasicBlockOfGuard(guard)) and
      not other.isLiveAtEndOfBlock(getAGuardBranchSuccessor(guard, branch))
    )
  )
}

/**
 * Holds if `v` is conditionally assigned `val` under the condition that `guard` evaluates to `branch`.
 */
private predicate conditionalAssignVal(SsaVariable v, Guard guard, boolean branch, AbstractValue val) {
  conditionalAssign(v, guard, branch, val.getExpr())
}

private predicate relevantEq(SsaVariable v, AbstractValue val) {
  conditionalAssignVal(v, _, _, val)
}

/**
 * Holds if the evaluation of `guard` to `branch` implies that `v` does not have the value `val`.
 */
private predicate guardImpliesNotEqual1(
  Guard guard, boolean branch, SsaVariable v, AbstractValue val
) {
  relevantEq(v, val) and
  (
    guard.isEquality(v.getAUse(), val.getExpr(), branch.booleanNot())
    or
    exists(AbstractValue val2 |
      guard.isEquality(v.getAUse(), val2.getExpr(), branch) and
      val != val2
    )
    or
    guard.(InstanceOfExpr).getExpr() = sameValue(v, _) and branch = true and val = TAbsValNull()
  )
}

/**
 * Holds if the evaluation of `guard` to `branch` implies that `v` does not have the value `val`.
 */
private predicate guardImpliesNotEqual2(
  Guard guard, boolean branch, SsaVariable v, AbstractValue val
) {
  relevantEq(v, val) and
  (
    guard = directNullGuard(v, branch, false) and val = TAbsValNull()
    or
    exists(int k |
      guard = integerGuard(v.getAUse(), branch, k, false) and
      val = TAbsValInt(k)
    )
  )
}
