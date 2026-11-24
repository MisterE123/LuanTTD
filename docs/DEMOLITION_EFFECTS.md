# Demolition feedback

After the worker accepts an area or a layer demolition, nearby players see
a brief flash, arcing chips, and warm dust which rises and drifts before
fading. Quotes, previews, rejected commands, and cancellations don't
play the effect. Large successful areas show up to three nearby bursts;
one stock OpenSFX explosion cue plays if that sound is installed.

The quick flare is inspired by the short-lived stock OpenTTD visual in
[effectvehicle.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/effectvehicle.cpp).
All particle textures are original, not copied from OpenTTD or OpenGFX.
The effect is cosmetic: no damage, persistence, collision, obstruction,
clearance, company costs, or world random draws are added or changed.
