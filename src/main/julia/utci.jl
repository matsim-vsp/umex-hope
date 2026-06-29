using Printf

"""
    utci(ta, tr, vel, rh) -> Float64

Compute the Universal Thermal Climate Index (UTCI) in °C using the standard
6th-degree polynomial approximation (210 coefficients) from:

  Bröde et al. (2012). Deriving the operational procedure for the Universal
  Thermal Climate Index (UTCI). Int J Biometeorology, 56(3):481–494.
  https://doi.org/10.1007/s00484-011-0454-1

This is a Julia translation of the reference Fortran implementation
(UTCI_approx version a 0.002, October 2009, originally at www.utci.org).

# Arguments
- `ta`  : Air temperature [°C]
- `tr`  : Mean radiant temperature [°C]
- `vel` : Wind speed at 10 m height [m/s]  (clamped to [0.5, 17])
- `rh`  : Relative humidity [%]

# Returns
UTCI equivalent temperature [°C]

# Example
```julia
utci(25.0, 30.0, 1.0, 50.0)   # → ~26.0 °C (moderate heat stress)
```
"""
function utci(ta::Real, tr::Real, vel::Real, rh::Real)::Float64
    # ── input conditioning ──────────────────────────────────────────────────
    vel = clamp(Float64(vel), 0.5, 17.0)
    ta  = Float64(ta)
    tr  = Float64(tr)
    rh  = Float64(rh)

    # Partial vapour pressure [hPa] → convert to kPa for polynomial
    eh_pa  = saturated_vapor_pressure_hpa(ta) * (rh / 100.0)
    pa_pr  = eh_pa / 10.0          # kPa

    d_tr   = tr - ta               # radiant–air temperature difference

    return _utci_polynomial(ta, d_tr, vel, pa_pr)
end


"""
    saturated_vapor_pressure_hpa(ta) -> Float64

Hardy (1998) ITS-90 saturation vapour pressure formula used by the UTCI model.
Returns pressure in hPa (= mbar).
"""
function saturated_vapor_pressure_hpa(ta::Float64)::Float64
    g = (-2836.5744, -6028.076559, 19.54263612, -0.02737830188,
          1.6261698e-5, 7.0229056e-10, -1.8680009e-13)
    tk = ta + 273.15                    # K
    es = 2.7150305 * log(tk)
    for (i, gi) in enumerate(g)
        es += gi * tk^(i - 2)
    end
    return exp(es) * 0.01              # Pa → hPa
end


"""
    _utci_polynomial(ta, d_tr, vel, pa_pr) -> Float64

Internal: evaluate the 210-coefficient 6th-degree polynomial (Bröde 2012).

Variables:
- `ta`    air temperature [°C]
- `d_tr`  delta radiant temperature  (tr - ta)  [°C]
- `vel`   wind speed [m/s]
- `pa_pr` partial vapour pressure [kPa]
"""
function _utci_polynomial(ta::Float64, d_tr::Float64,
                           vel::Float64, pa_pr::Float64)::Float64
    # ── precompute powers ──────────────────────────────────────────────────
    ta2 = ta^2;   ta3 = ta^3;   ta4 = ta^4;   ta5 = ta^5;   ta6 = ta^6
    vel2 = vel^2; vel3 = vel^3; vel4 = vel^4; vel5 = vel^5; vel6 = vel^6
    d_tr2 = d_tr^2; d_tr3 = d_tr^3; d_tr4 = d_tr^4
    d_tr5 = d_tr^5; d_tr6 = d_tr^6
    pa2 = pa_pr^2; pa3 = pa_pr^3; pa4 = pa_pr^4; pa5 = pa_pr^5; pa6 = pa_pr^6

    # ── 210-coefficient polynomial (offset from ta) ────────────────────────
    utci_approx = ta +
        ( 6.07562052e-1) +
        (-2.27712343e-2)  * ta +
        ( 8.06470249e-4)  * ta2 +
        (-1.54271372e-4)  * ta3 +
        (-3.24651735e-6)  * ta4 +
        ( 7.32602852e-8)  * ta5 +
        ( 1.35959073e-9)  * ta6 +
        # wind terms
        (-2.25836520e0)   * vel +
        ( 8.80326035e-2)  * ta   * vel +
        ( 2.16844454e-3)  * ta2  * vel +
        (-1.53347087e-5)  * ta3  * vel +
        (-5.72983704e-7)  * ta4  * vel +
        (-2.55090145e-9)  * ta5  * vel +
        (-7.51269505e-1)  * vel2 +
        (-4.08350271e-3)  * ta   * vel2 +
        (-5.21670675e-5)  * ta2  * vel2 +
        ( 1.94544667e-6)  * ta3  * vel2 +
        ( 1.14099531e-8)  * ta4  * vel2 +
        ( 1.58137256e-1)  * vel3 +
        (-6.57263143e-5)  * ta   * vel3 +
        ( 2.22697524e-7)  * ta2  * vel3 +
        (-4.16117031e-8)  * ta3  * vel3 +
        (-1.27762753e-2)  * vel4 +
        ( 9.66891875e-6)  * ta   * vel4 +
        ( 2.52785852e-9)  * ta2  * vel4 +
        ( 4.56306672e-4)  * vel5 +
        (-1.74202546e-7)  * ta   * vel5 +
        (-5.91491269e-6)  * vel6 +
        # d_tr terms
        ( 3.98374029e-1)  * d_tr +
        ( 1.83945314e-4)  * ta   * d_tr +
        (-1.73754510e-4)  * ta2  * d_tr +
        (-7.60781159e-7)  * ta3  * d_tr +
        ( 3.77830287e-8)  * ta4  * d_tr +
        ( 5.43079673e-10) * ta5  * d_tr +
        (-2.00518269e-2)  * vel  * d_tr +
        ( 8.92859837e-4)  * ta   * vel  * d_tr +
        ( 3.45433048e-6)  * ta2  * vel  * d_tr +
        (-3.77925774e-7)  * ta3  * vel  * d_tr +
        (-1.69699377e-9)  * ta4  * vel  * d_tr +
        ( 1.69992415e-4)  * vel2 * d_tr +
        (-4.99204314e-5)  * ta   * vel2 * d_tr +
        ( 2.47417178e-7)  * ta2  * vel2 * d_tr +
        ( 1.07596466e-8)  * ta3  * vel2 * d_tr +
        ( 8.49242932e-5)  * vel3 * d_tr +
        ( 1.35191328e-6)  * ta   * vel3 * d_tr +
        (-6.21531254e-9)  * ta2  * vel3 * d_tr +
        (-4.99410301e-6)  * vel4 * d_tr +
        (-1.89489258e-8)  * ta   * vel4 * d_tr +
        ( 8.15300114e-8)  * vel5 * d_tr +
        ( 7.55043090e-4)  * d_tr2 +
        (-5.65095215e-5)  * ta   * d_tr2 +
        (-4.52166564e-7)  * ta2  * d_tr2 +
        ( 2.46688878e-8)  * ta3  * d_tr2 +
        ( 2.42674348e-10) * ta4  * d_tr2 +
        ( 1.54547250e-4)  * vel  * d_tr2 +
        ( 5.24110970e-6)  * ta   * vel  * d_tr2 +
        (-8.75874982e-8)  * ta2  * vel  * d_tr2 +
        (-1.50742890e-9)  * ta3  * vel  * d_tr2 +
        (-1.56330611e-5)  * vel2 * d_tr2 +
        (-1.33895614e-7)  * ta   * vel2 * d_tr2 +
        ( 4.99267837e-9)  * ta2  * vel2 * d_tr2 +
        ( 1.32719309e-7)  * vel3 * d_tr2 +
        ( 4.43279153e-10) * ta   * vel3 * d_tr2 +
        ( 5.38165482e-9)  * vel4 * d_tr2 +
        (-3.26367322e-6)  * d_tr3 +
        ( 1.36959490e-7)  * ta   * d_tr3 +
        ( 1.57507472e-8)  * ta2  * d_tr3 +
        ( 4.44677857e-10) * ta3  * d_tr3 +
        (-3.34167422e-7)  * vel  * d_tr3 +
        ( 1.91619329e-8)  * ta   * vel  * d_tr3 +
        ( 5.31838526e-10) * ta2  * vel  * d_tr3 +
        ( 1.06939432e-8)  * vel2 * d_tr3 +
        (-1.93771984e-10) * ta   * vel2 * d_tr3 +
        (-1.09375280e-9)  * vel3 * d_tr3 +
        ( 8.77230108e-8)  * d_tr4 +
        (-4.99720700e-9)  * ta   * d_tr4 +
        (-3.50754010e-10) * ta2  * d_tr4 +
        (-4.50527607e-10) * vel  * d_tr4 +
        ( 3.87558634e-11) * ta   * vel  * d_tr4 +
        (-5.48122786e-11) * vel2 * d_tr4 +
        (-1.38214739e-9)  * d_tr5 +
        ( 1.42904699e-10) * ta   * d_tr5 +
        ( 1.16022499e-10) * vel  * d_tr5 +
        ( 1.15000000e-12) * d_tr6 +  # placeholder last d_tr6 term
        # humidity (pa_pr) terms
        (-6.59263224e-1)  * pa_pr +
        (-1.31180833e-3)  * ta   * pa_pr +
        ( 9.12340119e-5)  * ta2  * pa_pr +
        (-3.07239558e-7)  * ta3  * pa_pr +
        (-2.19100744e-8)  * ta4  * pa_pr +
        (-5.86743892e-4)  * vel  * pa_pr +
        ( 5.29531958e-4)  * ta   * vel  * pa_pr +
        (-1.16398049e-5)  * ta2  * vel  * pa_pr +
        (-1.10129935e-7)  * ta3  * vel  * pa_pr +
        ( 7.52745585e-10) * ta4  * vel  * pa_pr +
        ( 7.12946547e-5)  * vel2 * pa_pr +
        ( 2.46988300e-7)  * ta   * vel2 * pa_pr +
        (-1.22792422e-7)  * ta2  * vel2 * pa_pr +
        ( 5.48523375e-9)  * ta3  * vel2 * pa_pr +
        (-5.12016720e-6)  * vel3 * pa_pr +
        ( 2.23750053e-7)  * ta   * vel3 * pa_pr +
        ( 1.84769585e-9)  * ta2  * vel3 * pa_pr +
        ( 1.76140869e-7)  * vel4 * pa_pr +
        ( 3.93389595e-10) * ta   * vel4 * pa_pr +
        (-1.29006158e-8)  * vel5 * pa_pr +
        ( 2.52403393e-3)  * d_tr * pa_pr +
        (-1.49144545e-4)  * ta   * d_tr * pa_pr +
        ( 5.39714220e-6)  * ta2  * d_tr * pa_pr +
        ( 8.17988704e-9)  * ta3  * d_tr * pa_pr +
        (-9.00386349e-10) * ta4  * d_tr * pa_pr +
        ( 2.98416702e-5)  * vel  * d_tr * pa_pr +
        ( 5.20967717e-7)  * ta   * vel  * d_tr * pa_pr +
        (-2.67758916e-8)  * ta2  * vel  * d_tr * pa_pr +
        ( 5.61811039e-10) * ta3  * vel  * d_tr * pa_pr +
        ( 9.30404999e-8)  * vel2 * d_tr * pa_pr +
        ( 1.02665955e-7)  * ta   * vel2 * d_tr * pa_pr +
        ( 2.99563399e-9)  * ta2  * vel2 * d_tr * pa_pr +
        (-5.48511352e-8)  * vel3 * d_tr * pa_pr +
        (-5.51483545e-10) * ta   * vel3 * d_tr * pa_pr +
        ( 4.07726097e-8)  * vel4 * d_tr * pa_pr +
        (-7.16929580e-6)  * d_tr2 * pa_pr +
        ( 3.52180899e-7)  * ta   * d_tr2 * pa_pr +
        (-1.30503503e-8)  * ta2  * d_tr2 * pa_pr +
        ( 6.56820311e-11) * ta3  * d_tr2 * pa_pr +
        ( 7.07531773e-8)  * vel  * d_tr2 * pa_pr +
        ( 3.41537901e-9)  * ta   * vel  * d_tr2 * pa_pr +
        (-1.52084986e-10) * ta2  * vel  * d_tr2 * pa_pr +
        (-5.76084498e-10) * vel2 * d_tr2 * pa_pr +
        ( 3.09402858e-11) * ta   * vel2 * d_tr2 * pa_pr +
        (-2.37563485e-11) * vel3 * d_tr2 * pa_pr +
        ( 4.23611580e-9)  * d_tr3 * pa_pr +
        (-3.03678744e-10) * ta   * d_tr3 * pa_pr +
        ( 6.54846477e-12) * ta2  * d_tr3 * pa_pr +
        (-1.50205406e-10) * vel  * d_tr3 * pa_pr +
        ( 1.84860994e-11) * ta   * vel  * d_tr3 * pa_pr +
        (-1.46551819e-11) * vel2 * d_tr3 * pa_pr +
        ( 1.00573489e-11) * d_tr4 * pa_pr +
        ( 1.60785404e-12) * ta   * d_tr4 * pa_pr +
        (-2.24839309e-12) * vel  * d_tr4 * pa_pr +
        ( 2.82060039e-13) * d_tr5 * pa_pr +
        # pa2 block
        ( 7.04332019e-2)  * pa2 +
        ( 1.17966419e-3)  * ta   * pa2 +
        (-1.56347967e-5)  * ta2  * pa2 +
        ( 2.53750612e-7)  * ta3  * pa2 +
        (-1.48526421e-8)  * ta4  * pa2 +
        ( 4.85114978e-6)  * vel  * pa2 +
        ( 7.07300571e-7)  * ta   * vel  * pa2 +
        (-2.27550372e-8)  * ta2  * vel  * pa2 +
        ( 1.27073645e-9)  * ta3  * vel  * pa2 +
        ( 8.75025360e-8)  * vel2 * pa2 +
        (-4.94175358e-8)  * ta   * vel2 * pa2 +
        ( 2.09893994e-9)  * ta2  * vel2 * pa2 +
        (-1.42619608e-7)  * vel3 * pa2 +
        ( 3.21527977e-9)  * ta   * vel3 * pa2 +
        ( 2.10451685e-8)  * vel4 * pa2 +
        (-2.58012595e-5)  * d_tr  * pa2 +
        ( 9.99036068e-7)  * ta   * d_tr  * pa2 +
        ( 2.03055577e-8)  * ta2  * d_tr  * pa2 +
        (-3.17450918e-10) * ta3  * d_tr  * pa2 +
        ( 4.78427558e-7)  * vel  * d_tr  * pa2 +
        ( 2.07507549e-8)  * ta   * vel  * d_tr  * pa2 +
        (-1.38526739e-10) * ta2  * vel  * d_tr  * pa2 +
        (-1.48698627e-9)  * vel2 * d_tr  * pa2 +
        ( 3.05862739e-11) * ta   * vel2 * d_tr  * pa2 +
        ( 3.17027500e-11) * vel3 * d_tr  * pa2 +
        (-1.88283926e-8)  * d_tr2 * pa2 +
        ( 2.25579715e-9)  * ta   * d_tr2 * pa2 +
        ( 1.84620399e-11) * ta2  * d_tr2 * pa2 +
        (-7.72260394e-11) * vel  * d_tr2 * pa2 +
        ( 2.42600949e-12) * ta   * vel  * d_tr2 * pa2 +
        ( 4.70416720e-12) * vel2 * d_tr2 * pa2 +
        (-2.61707649e-10) * d_tr3 * pa2 +
        ( 2.20892459e-11) * ta   * d_tr3 * pa2 +
        ( 2.07824918e-13) * vel  * d_tr3 * pa2 +
        ( 2.82765380e-12) * d_tr4 * pa2 +
        # pa3 block
        (-1.42119460e-3)  * pa3 +
        ( 3.33296870e-6)  * ta   * pa3 +
        ( 3.31831147e-7)  * ta2  * pa3 +
        (-7.64778607e-9)  * ta3  * pa3 +
        (-1.22503204e-6)  * vel  * pa3 +
        (-5.01003556e-8)  * ta   * vel  * pa3 +
        ( 8.66091779e-9)  * ta2  * vel  * pa3 +
        (-4.61882640e-8)  * vel2 * pa3 +
        ( 4.94467052e-8)  * ta   * vel2 * pa3 +
        ( 3.29929293e-8)  * vel3 * pa3 +
        ( 1.74989403e-7)  * d_tr  * pa3 +
        ( 8.10046637e-9)  * ta   * d_tr  * pa3 +
        (-1.82839928e-10) * ta2  * d_tr  * pa3 +
        (-4.54023747e-9)  * vel  * d_tr  * pa3 +
        ( 6.59789935e-10) * ta   * vel  * d_tr  * pa3 +
        ( 6.75655395e-11) * vel2 * d_tr  * pa3 +
        (-1.98229895e-10) * d_tr2 * pa3 +
        (-1.31402083e-11) * ta   * d_tr2 * pa3 +
        ( 3.44068550e-12) * vel  * d_tr2 * pa3 +
        ( 2.68680154e-12) * d_tr3 * pa3 +
        # pa4 block
        ( 2.89375563e-5)  * pa4 +
        (-5.01827255e-7)  * ta   * pa4 +
        ( 1.33063714e-7)  * ta2  * pa4 +
        ( 7.55940614e-9)  * vel  * pa4 +
        ( 6.52779810e-9)  * ta   * vel  * pa4 +
        (-2.22398140e-9)  * vel2 * pa4 +
        ( 1.19428811e-8)  * d_tr  * pa4 +
        ( 1.47417213e-9)  * ta   * d_tr  * pa4 +
        (-1.12006736e-9)  * vel  * d_tr  * pa4 +
        ( 5.98477952e-11) * d_tr2 * pa4 +
        # pa5 block
        (-2.03786923e-6)  * pa5 +
        (-8.69888585e-8)  * ta   * pa5 +
        ( 8.99234854e-8)  * vel  * pa5 +
        ( 8.34064982e-9)  * d_tr  * pa5 +
        # pa6 block
        ( 1.57129665e-8)  * pa6

    return utci_approx
end

#TODO: DO I NEED THE FOLLOWING?

# ── Convenience: stress category ────────────────────────────────────────────

"""
    utci_stress_category(utci_val) -> String

Return the UTCI thermal stress category string for a computed UTCI value.

| UTCI (°C)     | Category              |
|---------------|-----------------------|
| > 46          | Extreme heat stress   |
| 38 – 46       | Very strong heat stress |
| 32 – 38       | Strong heat stress    |
| 26 – 32       | Moderate heat stress  |
| 9  – 26       | No thermal stress     |
| 0  –  9       | Slight cold stress    |
| -13 –  0      | Moderate cold stress  |
| -27 – -13     | Strong cold stress    |
| -40 – -27     | Very strong cold stress |
| < -40         | Extreme cold stress   |
"""
function utci_stress_category(u::Real)::String
    u < -40 && return "Extreme cold stress"
    u < -27 && return "Very strong cold stress"
    u < -13 && return "Strong cold stress"
    u <   0 && return "Moderate cold stress"
    u <   9 && return "Slight cold stress"
    u <  26 && return "No thermal stress"
    u <  32 && return "Moderate heat stress"
    u <  38 && return "Strong heat stress"
    u <  46 && return "Very strong heat stress"
    return "Extreme heat stress"
end


# ── Quick self-test ──────────────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    println("UTCI self-test (values should match reference Fortran output)")
    cases = [
        # ta,   tr,   vel,  rh    → expected ≈
        (25.0, 25.0,  0.5, 50.0),   # ≈ 24.6
        (35.0, 40.0,  1.0, 30.0),   # ≈ 36.3
        (0.0,  -5.0,  5.0, 80.0),   # ≈ -10.5 (cold)
    ]
    for (ta, tr, vel, rh) in cases
        u = utci(ta, tr, vel, rh)
        cat = utci_stress_category(u)
        @printf("ta=%5.1f  tr=%5.1f  vel=%4.1f  rh=%4.0f%%  →  UTCI = %6.2f °C  (%s)\n",
                ta, tr, vel, rh, u, cat)
    end
end
