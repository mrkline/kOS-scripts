@LAZYGLOBAL OFF.
@CLOBBERBUILTINS OFF.

// Taken straight from the example, but it's a start.
DECLARE LOCAL nd IS NEXTNODE.

//print out node's basic parameters - ETA and deltaV
PRINT "Node in: " + ROUND(nd:ETA) + ", DeltaV: " + ROUND(nd:DELTAV:MAG).

//calculate ship's max acceleration
DECLARE LOCAL max_acc IS SHIP:MAXTHRUST / SHIP:MASS.

// Ignore the Tsiolkovsky rocket equation to assume burn time won't change as we expel mass.
// A decent approximation for now.
DECLARE LOCAL burn_duration IS nd:DELTAV:MAG / max_acc.
WAIT UNTIL nd:ETA <= (burn_duration / 2 + 60).
DECLARE LOCAL np IS nd:DELTAV. //points to node, don't care about the roll direction.
LOCK STEERING TO np.

DECLARE LOCAL tset IS 0.
LOCK THROTTLE TO tset.
WAIT UNTIL VANG(np, SHIP:FACING:VECTOR) < 0.25.
WAIT UNTIL nd:ETA <= (burn_duration / 2).

DECLARE LOCAL done IS False.
DECLARE LOCAL dv0 IS nd:DELTAV.
UNTIL done {
    // Recalculate current max_acceleration, as it changes while we burn through fuel
    SET max_acc TO SHIP:MAXTHRUST / SHIP:MASS.
    // Point back along our burn vector
    SET np TO nd:DELTAV.

    // We're done once our initial pointing direction and our current one diverge.
    IF VDOT(dv0, np) < 0.5 {
        LOCK THROTTLE TO 0.
        break.
    }

    // Throttle is 100% until there is less than a second of burn left.
    SET tset TO CLAMP(0.05, 1, SQRT(np:MAG / max_acc)).
}
print "End burn, remain dv " + round(nd:deltav:mag,1) + "m/s, vdot: " + round(vdot(dv0, nd:deltav),1).

FUNCTION CLAMP {
    PARAMETER lo.
    PARAMETER hi.
    PARAMETER val.
    RETURN MAX(lo, MIN(hi, val)).
}