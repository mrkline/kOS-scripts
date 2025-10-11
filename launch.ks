@LAZYGLOBAL OFF.
@CLOBBERBUILTINS OFF.

PARAMETER downrange IS 90.
PARAMETER desiredAp IS 80000.

DECLARE LOCAL headingOut IS MOD(downrange + 180, 360).

CLEARSCREEN.
WAIT UNTIL SHIP:UNPACKED.

DECLARE LOCAL throttleOut IS 0.
LOCK THROTTLE TO throttleOut.

PRINT "Heading " + downrange + ", apoapsis " + desiredAp.
PRINT "T-MINUS".
FROM {LOCAL countdown IS 5.} UNTIL countdown = 0 STEP {SET countdown TO countdown - 1.} DO {
    PRINT countdown.
    WAIT 1.
}
PRINT "Ignition".
SET throttleOut TO 1.
LOCK STEERING to HEADING(0, 90). // Hold attitude until we clear the tower.
STAGE.
WAIT 1.
PRINT "The clock is running!".

DECLARE LOCAL tower IS SHIP:BOUNDS:SIZE:Z * 2.
WAIT UNTIL ALT:RADAR > tower.
PRINT "Cleared the tower, starting roll program".
DECLARE LOCAL pitchOut IS 90.
LOCK STEERING to HEADING(headingOut, pitchOut).


WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG > 100.
SET pitchOut TO 100.
PRINT "Pitchback, throttling for Max Q".
DECLARE LOCAL maxQPid is PIDLOOP(10, 3, 3, 0, 1).
SET maxQPid:SETPOINT to 0.25.
DECLARE LOCAL lastPressure IS SHIP:Q.

// Would be nice to low-pass this, but assume we aren't buffeted by wind in Kerbal.
UNTIL (SHIP:VELOCITY:SURFACE:MAG > 300 AND SHIP:Q < lastPressure) {
    tick().
    SET throttleOut to maxQPid:UPDATE(TIME:SECONDS, SHIP:Q).
    SET lastPressure to SHIP:Q.
}

PRINT "Throttling to hold " + desiredEta() + "s to apogee".
DECLARE LOCAL apogeePid is PIDLOOP(1, 0, 0.05, 0.05, 1).
SET apogeePid:SETPOINT TO desiredEta().
DECLARE LOCAL lastEta IS 0.
UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp OR
      // When to give up and start pitching, see below. (Give a few seconds for staging.)
      (SHIP:ORBIT:ETA:APOAPSIS < lastEta AND SHIP:ORBIT:ETA:APOAPSIS < apogeePid:SETPOINT - 5) {
    tick().
    SET lastEta to SHIP:ORBIT:ETA:APOAPSIS.
    SET apogeePid:SETPOINT TO desiredEta().
    SET throttleOut TO MIN(
        maxQPid:UPDATE(TIME:SECONDS, SHIP:Q),
        apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS)
    ).
    // Follow the ballistic arc, holding a bit nose high so we don't shallow out our burn
    // and have the throttle drop to 0.
    SET pitchOut TO 180 - pitchAboveHorizon().
}

IF SHIP:ORBIT:ETA:APOAPSIS < lastEta AND SHIP:ORBIT:ETA:APOAPSIS < apogeePid:SETPOINT - 5 {
    PRINT "Insufficient initial burn, pitching for apogee".
    // Pitch up to 30 segerees above the horizon.
    // The LOCK "cooked" steering is already a PID loop, don't drive it with one.
    UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp {
        tick().
        SET apogeePid:SETPOINT TO desiredEta().
        SET throttleOut TO apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS).
        DECLARE LOCAL pitchUpdate IS CLAMP(0, 30, apogeePid:SETPOINT - SHIP:ORBIT:ETA:APOAPSIS).
        SET pitchOut TO 180 - (pitchAboveHorizon() + pitchUpdate).
    }
}

PRINT "Gravity turn complete".
SET pitchOut TO 180.
SET throttleOut TO 0.

WAIT UNTIL SHIP:ORBIT:ETA:APOAPSIS <= 1.
PRINT "Circularizing orbit".
SET throttleOut TO 1.
UNTIL (SHIP:ORBIT:APOAPSIS - SHIP:ORBIT:PERIAPSIS) < 1000 {
    tick().
}

PRINT "Orbital insertion complete.".
LOCK THROTTLE to 0.

FUNCTION CLAMP {
    PARAMETER lo.
    PARAMETER hi.
    PARAMETER val.
    RETURN MAX(lo, MIN(hi, val)).
}

// Reduce our ETA as we get closer to the desired altitude,
// but don't let it drop to 0 - then we over-shallow our climb.
FUNCTION desiredEta {
    // Larger number is a steeper ascent.
    DECLARE LOCAL starting IS 60.

    RETURN starting * CLAMP(0.5, 1, (desiredAp - SHIP:ALTITUDE) / 20000).
}

// From https://github.com/KSP-KOS/KSLib/blob/master/library/lib_navball.ks
FUNCTION pitchAboveHorizon {
    RETURN vang(SHIP:VELOCITY:SURFACE, BODY:POSITION) - 90.
}

FUNCTION staging {    
    DECLARE LOCAL shouldStage IS FALSE.
    IF SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT = 0 {
        SET shouldStage TO TRUE.
    }
    ELSE {
        FOR e IN SHIP:ENGINES {
            IF e:FLAMEOUT {
                SET shouldStage TO TRUE.
                BREAK.
            }
        }
    }
    IF shouldStage {
        PRINT "Staging".
        DECLARE LOCAL lastThrottle IS throttleOut.
        SET throttleOut TO 0.
        STAGE.
        WAIT 1.
        SET throttleOut TO lastThrottle.
    }
}

FUNCTION tick {
    staging().
}