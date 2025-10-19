@LAZYGLOBAL OFF.
@CLOBBERBUILTINS OFF.

// Vain attempt to damp oscillations on long ships:
SET STEERINGMANAGER:PITCHTS TO 8.
SET STEERINGMANAGER:YAWTS TO 8.
SET STEERINGMANAGER:PITCHPID:KD TO 0.1.
SET STEERINGMANAGER:YAWPID:KD TO 0.1.

PARAMETER downrange IS 90.
PARAMETER desiredApKilo IS 80.

DECLARE LOCAL desiredAp IS desiredApKilo * 1000.
DECLARE LOCAL headingOut IS 0.
DECLARE LOCAL initialOrbitalVelocity IS VELOCITY:ORBIT:MAG. 
DECLARE LOCAL orbitalVelocity IS CREATEORBIT(0, 0, BODY:RADIUS + desiredAp, 0, 0, 0, 0, BODY):VELOCITY:ORBIT:MAG.

WAIT UNTIL SHIP:UNPACKED.

DECLARE LOCAL pitchOut IS 90.
LOCK STEERING to HEADING(headingOut, pitchOut).
DECLARE LOCAL throttleOut IS 0.
LOCK THROTTLE TO throttleOut.

DECLARE LOCAL startTime IS TIME:SECONDS + 5.

// Questionable per-tick integration
DECLARE LOCAL expendedDeltaV IS 0.
DECLARE LOCAL gravityLosses IS 0.
DECLARE LOCAL steeringLosses IS 0.
DECLARE LOCAL dragLosses IS 0.

DELETEPATH("launch.csv").
LOG "t,altitude,accelTheta,dx,dy,ddx,ddy" TO "launch.csv".
DECLARE LOCAL lastTick IS 0.
WHEN TIME:SECONDS >= startTime AND TIME:SECONDS <> lastTick THEN {
    IF lastTick = 0 {
        SET lastTick TO TIME:SECONDS.
        RETURN TRUE.
    }
    DECLARE LOCAL dt IS TIME:SECONDS - lastTick.
    DECLARE LOCAL ddv IS SHIP:THRUST / SHIP:MASS.
    DECLARE LOCAL dv IS ddv * dt.
    DECLARE LOCAL gMag IS CONSTANT:G * BODY:MASS / (BODY:RADIUS + SHIP:ALTITUDE) ^ 2.
    DECLARE LOCAL g IS -BODY:POSITION:NORMALIZED * gMag.
    DECLARE LOCAL vel IS SHIP:VELOCITY:ORBIT.
    DECLARE LOCAL vHat IS vel:NORMALIZED.
    DECLARE LOCAL dir IS SHIP:FACING:FOREVECTOR.

    SET expendedDeltaV TO expendedDeltaV + dv.
    SET gravityLosses TO gravityLosses + VDOT(vHat, g) * dt.
    SET steeringLosses TO steeringLosses + dv * (1 - VDOT(vHat, dir:NORMALIZED)).
    SET dragLosses TO dragLosses -
        VDOT(SHIP:VELOCITY:SURFACE:NORMALIZED, ADDONS:FAR:AEROFORCE) / SHIP:MASS * dt.

    DECLARE LOCAL velAng IS vang(SHIP:VELOCITY:ORBIT, BODY:POSITION) - 90.
    DECLARE LOCAL accAng IS vang(dir, BODY:POSITION) - 90.
    DECLARE LOCAL vmag IS vel:MAG.
    LOG (TIME:SECONDS - startTime) + "," + SHIP:ALTITUDE + "," + accAng + "," +
        (COS(velAng) * vmag) + "," + (SIN(velAng) * vmag) + "," +
        (COS(accAng) * ddv) + "," + (SIN(accAng) * ddv) TO "launch.csv".
    SET lastTick TO TIME:SECONDS.
    RETURN TRUE.
}

// TUI render loop
DECLARE LOCAL currentStatus IS "".
DECLARE LOCAL lastScreenUpdate IS 0.
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

    PRINT "DV SPENT:   " + ROUND(expendedDeltaV, 1) AT (0, 10).
    PRINT "G LOSS:     " + ROUND(gravityLosses, 1) AT (0, 11).
    PRINT "DRAG LOSS:  " + ROUND(dragLosses, 1) AT (0, 12).
    PRINT "STEER LOSS: " + ROUND(steeringLosses, 1) AT (0, 13).

    DECLARE LOCAL gMag IS CONSTANT:G * BODY:MASS / (BODY:RADIUS + SHIP:ALTITUDE) ^ 2.
    PRINT "G: " + ROUND(gMag, 2) AT (0, 15).
    PRINT "Q: " + ROUND(ADDONS:FAR:DYNPRES, 2) AT (0, 16).
    PRINT "MACH: " + ROUND(ADDONS:FAR:MACH, 2) AT (0, 17).
    PRINT "Drag: " +
        ROUND(-VDOT(SHIP:VELOCITY:SURFACE:NORMALIZED, ADDONS:FAR:AEROFORCE) / SHIP:MASS, 2) +
        " m/s^2" AT (0, 18).
    PRINT "AOA: " + ROUND(ABS(ADDONS:FAR:AOA), 2) AT (0, 19).
    PRINT "AOS: " + ROUND(ABS(ADDONS:FAR:AOS), 2) AT (0, 20).
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
DECLARE LOCAL maxQPid is PIDLOOP(0.1, 0.03, 0.03, 0, 1).
SET maxQPid:SETPOINT to 40.

DECLARE LOCAL apogeePid is PIDLOOP(1, 0, 0, 0, 1).
SET apogeePid:SETPOINT TO desiredEta().

UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp {
    SET currentStatus TO "Throttle for " + ROUND(desiredEta(), 1) + "s to apogee".
    tick().
    SET apogeePid:SETPOINT TO desiredEta().
    IF pitchAboveHorizon() > 0 {
        SET throttleOut TO MIN(
            maxQPid:UPDATE(TIME:SECONDS, ADDONS:FAR:DYNPRES),
            apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS)
        ).
        setPitch(pitchAboveHorizon()).
    } ELSE {
        // Assume we're over the hump, circularize ASAP.
        SET throttleOut TO 1.
        set pitchOut TO 170.
    }
}

SET throttleOut TO 0.
SET currentStatus TO "Orbital insertion complete.".

FUNCTION CLAMP {
    PARAMETER lo.
    PARAMETER hi.
    PARAMETER val.
    RETURN MAX(lo, MIN(hi, val)).
}

FUNCTION desiredEta {
    // Rapidly shallow out our ETA as we approach the target apoapsis.
    RETURN 30 + 20 * (1 - SHIP:VELOCITY:ORBIT:MAG / orbitalVelocity).
}

FUNCTION setPitch {
    PARAMETER p.
    SET pitchOut TO CLAMP(95, 175, 180 - p).
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