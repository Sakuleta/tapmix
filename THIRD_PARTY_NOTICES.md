# Third-party notices

Tapmix supports importing the parametric filter format used by **AutoEQ**.

## AutoEQ

- Project: https://github.com/jaakkopasanen/AutoEq
- Author: Jaakko Pasanen
- License: MIT

Tapmix does not bundle AutoEQ measurement data or source code. It reads a
`ParametricEQ.txt` file that the user exports from AutoEQ (or Equalizer APO)
and converts the `PK`, `LSC` and `HSC` filters into its own biquad chain.

The MIT license of AutoEQ is reproduced at the link above. If you redistribute
AutoEQ data with Tapmix, keep AutoEQ's copyright and license notice with that
data.

## Sparkle

- Project: https://github.com/sparkle-project/Sparkle
- License: MIT (see the framework's `Resources` folder)

Tapmix embeds `Sparkle.framework` for signed, on-demand application updates.
The framework is added as a Swift Package binary target and copied into
`Tapmix.app/Contents/Frameworks` at build time.
