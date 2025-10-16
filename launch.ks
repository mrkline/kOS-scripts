@LAZYGLOBAL OFF.
@CLOBBERBUILTINS OFF.

// Vain attempt to damp oscillations on long ships:
SET STEERINGMANAGER:PITCHTS TO 10.
SET STEERINGMANAGER:YAWTS TO 10.
SET STEERINGMANAGER:ROLLTS TO 5.
SET STEERINGMANAGER:PITCHPID:KD TO 0.1.
SET STEERINGMANAGER:YAWPID:KD TO 0.1.

PARAMETER downrange IS 90.
PARAMETER desiredApKilo IS 80.

DECLARE LOCAL desiredAp IS desiredApKilo * 1000.
DECLARE LOCAL headingOut IS 0.
DECLARE LOCAL orbitalVelocity TO CREATEORBIT(0, 0, BODY:RADIUS + desiredAp, 0, 0, 0, 0, BODY):VELOCITY:ORBIT:MAG.

WAIT UNTIL SHIP:UNPACKED.

DECLARE LOCAL currentStatus IS "".
DECLARE LOCAL lastScreenUpdate IS 0.
DECLARE LOCAL pitchOut IS 90.
LOCK STEERING to HEADING(headingOut, pitchOut).
DECLARE LOCAL throttleOut IS 0.
LOCK THROTTLE TO throttleOut.

DECLARE LOCAL startTime TO TIME:SECONDS + 5.
DECLARE LOCAL staritngDV TO SHIP:DELTAV:VACUUM.

// TUI render loop
WHEN TIME:SECONDS - lastScreenUpdate > 1 THEN {
    CLEARSCREEN.
    PRINT currentStatus AT(0, 0).
    PRINT "Heading " + downrange + ", apoapsis " + desiredAp AT (0, 1).
    IF TIME:SECONDS - startTime > 0 {
        PRINT "T+" + FLOOR(TIME:SECONDS - startTime) AT (0, 2).
    } ELSE {
        PRINT "T" + FLOOR(TIME:SECONDS - startTime) AT (0, 3).
    }

    PRINT "HEADING: " + ROUND(MOD(headingOut + 180, 360)) AT (0, 4).
    PRINT "PITCH: " + ROUND(180 - pitchOut, 2) AT (0, 5).
    PRINT "VEL/ORB: " + ROUND(SHIP:VELOCITY:ORBIT:MAG) + "/" + ROUND(orbitalVelocity)
        + " (" + ROUND(SHIP:VELOCITY:ORBIT:MAG / orbitalVelocity * 100) + "%)" AT (0, 6).
    PRINT "AP: " + ROUND(SHIP:ORBIT:APOAPSIS)
        + " (" + ROUND(SHIP:ORBIT:APOAPSIS / desiredAp * 100)  + "%)" AT (0, 7).
    PRINT "PE: " + MAX(0, ROUND(SHIP:ORBIT:PERIAPSIS)) AT (0, 8).

    PRINT "DV SPENT: " + ROUND(staritngDV - SHIP:DELTAV:VACUUM) AT (0, 10).
    SET lastScreenUpdate TO TIME:SECONDS.
    PRESERVE.
}

SET currentStatus TO "Countdown".
WAIT UNTIL TIME:SECONDS - startTime >= 0.
SET currentStatus TO "Ignition".
SET throttleOut TO 1.
STAGE.

DECLARE LOCAL tower IS SHIP:BOUNDS:SIZE:Z * 2.5.
WAIT UNTIL ALT:RADAR > tower.
SET currentStatus TO "Roll program".
SET headingOut TO MOD(downrange + 180, 360).

WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG > 100.
DECLARE LOCAL maxQPid is PIDLOOP(10, 3, 3, 0, 1).
SET maxQPid:SETPOINT to 0.25.
DECLARE LOCAL lastPressure IS SHIP:Q.

DECLARE LOCAL apogeePid is PIDLOOP(1, 0, 0, 0.01, 1).
SET apogeePid:SETPOINT TO desiredEta().

UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp {
    SET currentStatus TO "Throttle & Pitch for " + ROUND(desiredEta(), 1) + "s to apogee".
    tick().
    SET lastPressure to SHIP:Q.
    SET apogeePid:SETPOINT TO desiredEta().
    SET throttleOut TO MIN(
        maxQPid:UPDATE(TIME:SECONDS, SHIP:Q),
        apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS)
    ).
    DECLARE LOCAL pitchUpdate IS CLAMP(-30, 30, apogeePid:SETPOINT - SHIP:ORBIT:ETA:APOAPSIS).
    setPitch(pitchAboveHorizon() + pitchUpdate).
}

SET currentStatus TO "Orbital insertion complete.".

FUNCTION CLAMP {
    PARAMETER lo.
    PARAMETER hi.
    PARAMETER val.
    RETURN MAX(lo, MIN(hi, val)).
}

FUNCTION desiredEta {
    // Larger number is a steeper ascent.
    DECLARE LOCAL starting IS 45.
    RETURN starting * CLAMP(0, 1, (desiredAp - SHIP:ALTITUDE) / 20000).
}

FUNCTION setPitch {
    PARAMETER p.
    SET pitchOut TO CLAMP(100, 175, 180 - p).
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