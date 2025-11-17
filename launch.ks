@LAZYGLOBAL OFF.
@CLOBBERBUILTINS OFF.

// Vain attempt to damp oscillations on long ships:
SET STEERINGMANAGER:PITCHTS TO 10.
SET STEERINGMANAGER:YAWTS TO 10.
SET STEERINGMANAGER:PITCHPID:KD TO 0.1.
SET STEERINGMANAGER:YAWPID:KD TO 0.1.

PARAMETER downrange IS 90.
PARAMETER desiredApKilo IS 80.

DECLARE LOCAL desiredAp IS desiredApKilo * 1000.
DECLARE LOCAL initialOrbitalVelocity IS VELOCITY:ORBIT:MAG. 
DECLARE LOCAL orbitalVelocity IS CREATEORBIT(0, 0, BODY:RADIUS + desiredAp, 0, 0, 0, 0, BODY):VELOCITY:ORBIT:MAG.

WAIT UNTIL SHIP:UNPACKED.

LOCK STEERING to HEADING(0, 90).
DECLARE LOCAL throttleOut IS 0.
LOCK THROTTLE TO throttleOut.

DECLARE LOCAL startTime IS TIME:SECONDS + 5.

// Questionable per-tick integration
DECLARE LOCAL expendedDeltaV IS 0.
DECLARE LOCAL gravityLosses IS 0.
DECLARE LOCAL steeringLosses IS 0.
DECLARE LOCAL dragLosses IS 0.

//DELETEPATH("launch.csv").
//LOG "t,altitude,accelTheta,dx,dy,ddx,ddy" TO "launch.csv".
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
    //LOG (TIME:SECONDS - startTime) + "," + SHIP:ALTITUDE + "," + accAng + "," +
    //    (COS(velAng) * vmag) + "," + (SIN(velAng) * vmag) + "," +
    //    (COS(accAng) * ddv) + "," + (SIN(accAng) * ddv) TO "launch.csv".
    SET lastTick TO TIME:SECONDS.
    RETURN TRUE.
}

// Until I can be bothered to wire up the analytical solution,
// drive the heading towards the right inclination.
DECLARE LOCAL headingPid IS PIDLOOP(2, 0, 0.05, -160, 160).

// TUI render loop
DECLARE LOCAL currentStatus IS "".
DECLARE LOCAL lastScreenUpdate IS 0.
WHEN TIME:SECONDS - lastScreenUpdate > 0.5 THEN {
    CLEARSCREEN.
    PRINT currentStatus AT(0, 0).
    PRINT "Heading " + downrange + ", apoapsis " + desiredAp AT (0, 1).
    IF TIME:SECONDS - startTime > 0 {
        PRINT "T+" + FLOOR(TIME:SECONDS - startTime) AT (0, 2).
    } ELSE {
        PRINT "T" + FLOOR(TIME:SECONDS - startTime) AT (0, 2).
    }

    PRINT "ORBIT HEADING: " + ROUND(orbitalHeading(), 1) +
        " (" + ROUND(turnTo(orbitalHeading(), downrange), 1) + " error)" AT (0, 4).
    PRINT "ORBIT PITCH:   " + ROUND(orbitalPitch(), 1) AT (0, 5). 
    PRINT "AIR HEADING: " + ROUND(airHeading()) AT (0, 6).
    PRINT "AIR PITCH:   " + ROUND(airPitch(), 1) AT (0, 7).
    PRINT "VEL/ORB: " + ROUND(SHIP:VELOCITY:ORBIT:MAG) + "/" + ROUND(orbitalVelocity)
        + " (" + ROUND(SHIP:VELOCITY:ORBIT:MAG / orbitalVelocity * 100) + "%)" AT (0, 8).
    PRINT "AP: " + ROUND(SHIP:ORBIT:APOAPSIS)
        + " (" + ROUND(SHIP:ORBIT:APOAPSIS / desiredAp * 100)  + "%)" AT (0, 9).
    PRINT "PE: " + MAX(0, ROUND(SHIP:ORBIT:PERIAPSIS)) AT (0, 10).

    PRINT "DV SPENT:   " + ROUND(expendedDeltaV, 1) AT (0, 12).
    PRINT "G LOSS:     " + ROUND(gravityLosses, 1) AT (0, 13).
    PRINT "DRAG LOSS:  " + ROUND(dragLosses, 1) AT (0, 14).
    PRINT "STEER LOSS: " + ROUND(steeringLosses, 1) AT (0, 15).

    DECLARE LOCAL gMag IS CONSTANT:G * BODY:MASS / (BODY:RADIUS + SHIP:ALTITUDE) ^ 2.
    PRINT "G: " + ROUND(gMag, 2) AT (0, 17).
    PRINT "Q: " + ROUND(ADDONS:FAR:DYNPRES, 2) AT (0, 18).
    PRINT "MACH: " + ROUND(ADDONS:FAR:MACH, 2) AT (0, 19).
    PRINT "Drag: " +
        ROUND(-VDOT(SHIP:VELOCITY:SURFACE:NORMALIZED, ADDONS:FAR:AEROFORCE) / SHIP:MASS, 2) +
        " m/s^2" AT (0, 20).
    PRINT "AOA: " + ROUND(ABS(ADDONS:FAR:AOA), 2) AT (0, 21).
    PRINT "AOS: " + ROUND(ABS(ADDONS:FAR:AOS), 2) AT (0, 22).
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
LOCK STEERING to HEADING(MOD(downrange + 180, 360), 90).

WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG > 100.

// As soon as we get a little bit of speed, pitch over.
DECLARE LOCAL aimVector IS SHIP:UP.
LOCK STEERING TO aimVector. // Rotated in tick().

// Don't let dynamic pressure exceed 30 kPa, drag accumulates rapidly.
DECLARE LOCAL maxQPid is PIDLOOP(0.1, 0, 0.03, 0, 1).
SET maxQPid:SETPOINT to 30.

// Drive the throttle based on the desired ETA to apoapsis,
DECLARE LOCAL apogeePid is PIDLOOP(1, 0, 0.03, 0, 1).
SET apogeePid:SETPOINT TO desiredEta().

UNTIL SHIP:ORBIT:APOAPSIS >= desiredAp OR (SHIP:ALTITUDE >= 70000 AND throttleOut = 0) {
    SET currentStatus TO "Throttle for " + ROUND(desiredEta(), 1) + "s to apogee".
    SET apogeePid:SETPOINT TO desiredEta().
    IF airPitch() > 0 {
        SET throttleOut TO MIN(
            maxQPid:UPDATE(TIME:SECONDS, ADDONS:FAR:DYNPRES),
            apogeePid:UPDATE(TIME:SECONDS, SHIP:ORBIT:ETA:APOAPSIS)
        ).
    } ELSE {
        // Assume we're over the hump, circularize ASAP.
        SET throttleOut TO 1.
    }
    tick().
}

UNLOCK STEERING.
UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
SAS ON.
PRINT "Orbital insertion complete." AT (0, 0).
WAIT 0.

FUNCTION CLAMP {
    PARAMETER lo.
    PARAMETER hi.
    PARAMETER val.
    RETURN MAX(lo, MIN(hi, val)).
}

FUNCTION desiredEta {
    // Rapidly shallow out our ETA as we approach the target apoapsis.
    DECLARE LOCAL des IS 30 + 15 * (1 - SHIP:VELOCITY:ORBIT:MAG / orbitalVelocity).
    // Pad for SRBs so we don't have a bunch of idle time when they burn out.
    FOR e IN SHIP:ENGINES {
        IF e:IGNITION AND e:THROTTLELOCK {
            SET des TO des - 15.
            BREAK.
        }
    }
    RETURN des.
}

// From https://github.com/KSP-KOS/KSLib/blob/master/library/lib_navball.ks
FUNCTION pitchOf {
    PARAMETER hdg.
    RETURN VANG(hdg, BODY:POSITION) - 90.
}

FUNCTION airPitch {
    RETURN pitchOf(SHIP:VELOCITY:SURFACE).
}

FUNCTION orbitalPitch {
    RETURN pitchOf(SHIP:VELOCITY:ORBIT).
}

// ditto
FUNCTION headingOf {
    PARAMETER hdg.
    DECLARE LOCAL east IS VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
    DECLARE LOCAL tx IS VDOT(SHIP:NORTH:VECTOR, hdg).
    DECLARE LOCAL ty IS VDOT(east, hdg).
    DECLARE LOCAL ta IS ARCTAN2(ty, tx).
    IF ta < 0 {
        SET ta TO ta + 360.
    }
    RETURN ta.
}

FUNCTION airHeading {
    RETURN headingOf(SHIP:VELOCITY:SURFACE).
}

FUNCTION orbitalHeading {
    RETURN headingOf(SHIP:VELOCITY:ORBIT).
}

FUNCTION MODCIRCLE {
    PARAMETER ang.
    UNTIL ang >= 0 {
        SET ang to ANG + 360.
    }
    UNTIL ang < 360 {
        SET ang to ANG - 360.
    }
    RETURN ang.
}

FUNCTION turnTo {
    PARAMETER angFrom.
    PARAMETER angTo.
    DECLARE LOCAL turn IS angFrom - angTo.
    IF angFrom > 180 {
        SET turn TO turn - 360.
    }  ELSE IF angFrom < -180 {
        SET turn TO turn + 360.
    }
    RETURN turn.
}

FUNCTION blendHeading {
    // We our orbit to be going downrange towards our target compass heading,
    // pitching along our ballistic arc.
    // Buf it that heading's not 90 degrees, we have to rotate it after launch.
    // Trying to rotate the heading while keeping pitch constant is SKETCHY -
    // it creates constant yawing moments and sideslip that can make the ship depart.
    // Do so very carefully.
    DECLARE local desiredHeading IS HEADING(
        MODCIRCLE(orbitalHeading() - 2 * turnTo(orbitalHeading(), downrange)),
        CLAMP(5, 85, airPitch() + pitchTrim())
    ):FOREVECTOR.
    SET aimVector TO LOOKDIRUP(desiredHeading, BODY:POSITION).
}

FUNCTION pitchTrim {
    RETURN CLAMP(0, 10, (desiredEta() - SHIP:ORBIT:ETA:APOAPSIS)).
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
        SET throttleOut TO lastThrottle.
    }
}

FUNCTION tick {
    staging().
    blendHeading().
}