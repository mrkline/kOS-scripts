@LAZYGLOBAL OFF.

PARAMETER downrange IS 90.
PARAMETER desiredAp IS 80000.

// Vain attempt to damp oscillations on long ships:
SET STEERINGMANAGER:PITCHTS TO 10.
SET STEERINGMANAGER:YAWTS TO 10.
SET STEERINGMANAGER:ROLLTS TO 5.
SET STEERINGMANAGER:PITCHPID:KI TO 0.05.
SET STEERINGMANAGER:YAWPID:KI TO 0.05.
SET STEERINGMANAGER:PITCHPID:KD TO 0.03.
SET STEERINGMANAGER:YAWPID:KD TO 0.03.

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
SET pitchOut TO 95.
PRINT "Pitchback, throttling for Max Q".
DECLARE LOCAL maxQPid is PIDLOOP(10, 3, 3, 0, 1).
SET maxQPid:SETPOINT to 0.30.
DECLARE LOCAL lastPressure IS SHIP:Q.

// Would be nice to low-pass this, but assume we aren't buffeted by wind in Kerbal.
UNTIL (SHIP:VELOCITY:SURFACE:MAG > 300 AND SHIP:Q < lastPressure) {
    tick().
    SET throttleOut to maxQPid:UPDATE(TIME:SECONDS, SHIP:Q).
    SET lastPressure to SHIP:Q.
}

// Larger number is a steeper ascent.
DECLARE LOCAL desiredEta IS 45.
// When do we want to give up on max throttle and start pitching?
DECLARE LOCAL desperateEta IS desiredEta * 2 / 3.

PRINT "Throttling to hold " + desiredEta + "s to apogee until 10k prior".
DECLARE LOCAL apogeePid is PIDLOOP(0.5, 0, 0.05, 0, 1).
SET apogeePid:SETPOINT TO desiredEta.
UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp OR (pitchAboveHorizon() < 1 AND throttleOut = 0) {
    // Reduce our ETA as we get closer to the desired altitude.
    DECLARE LOCAL etaScale IS SQRT(MIN(1.0, (desiredAp - SHIP:ALTITUDE) / 10000)).
    SET apogeePid:SETPOINT TO desiredEta * etaScale.
    tick().
    SET throttleOut TO apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS).
    // Follow the ballistic arc.
    SET pitchOut TO 180 - pitchAboveHorizon().
}
PRINT "Gravity turn complete, raising apoapsis to " + desiredAp.
LOCK THROTTLE to 1.
SET pitchOut to 180.
UNTIL (SHIP:ORBIT:APOAPSIS >= desiredAp) {
        tick().
        SET pitchOut TO 180 - pitchAboveHorizon().
}

PRINT "Orbital insertion complete.".
LOCK THROTTLE to 0.

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