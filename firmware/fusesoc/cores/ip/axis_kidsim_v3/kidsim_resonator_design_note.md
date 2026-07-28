# KID / Qubit Resonator Emulator — Design Note

**IP:** `axis_kidsim_v3`  ·  **Modules:** `kidsim_top` → `kidsim` → (`dds_chirp`, `cmult`, `iir_iq` → `iir_1p1z`)
**Scope of this note:** what the emulated resonator *is* in physical terms, how the IIR / DDS register values map to resonator properties, what physical configuration the filter corresponds to, and how a mid-readout frequency jump behaves. Written to be dropped into the QICK Sphinx docs (MyST markdown, `dollarmath` for equations).

---

## 1. What the emulator does

Each lane simulates one resonator by **demodulating** the incoming stream with a DDS carrier, **filtering** the resulting complex baseband with a first-order (1-pole/1-zero) IIR, and **remodulating** back to RF:

```
din --[din_la = DDS_LATENCY]---------------------\
                                                  prod0 = din · e^{-jφ}   (CONJB=1, demod)
dds_chirp --> e^{jφ(t)} ---------------------------/
     |                                                   |
     |                                              iir_iq  (H(z), per I and Q)
     |                                                   |
     \--[dds_dout_la = 8]--> e^{jφ} -----------------> prod1 = iir · e^{+jφ}   (remod)
```

The IIR runs on the **demodulated** (baseband) signal, so its passband is centred at DC in the rotating frame. Remodulation shifts that passband back up to the carrier frequency $f_c$. The net effect from `din` to `prod1` is therefore a **band-pass resonator centred at the carrier**, with its shape set by the IIR coefficients.

The IIR itself (`iir_1p1z`) is Direct-Form I:

$$H(z) = G\,\frac{1 - C_0 z^{-1}}{1 - C_1 z^{-1}}$$

with $C_0, C_1, G$ signed $Q(B-1)$ in $[-1, +1)$ and a real pole at $z = C_1$. `iir_iq` applies this **independently** to the I and Q components with the same real coefficients, so in the rotating frame it is a complex-baseband filter with a **real** pole sitting at baseband DC.

**Key structural fact for everything below:** the resonant frequency is set by the *carrier* (`DDS_FREQ_REG`), **not** by the pole. The pole (`C1`) sets the linewidth; the zero (`C0`) sets the coupling; the gain (`G`) sets the overall scale. Switching "ground" ↔ "excited" is a change of `DDS_FREQ_REG`.

---

## 2. From baseband filter to band-pass resonator

Let the carrier phase be $\varphi[n]$ (for a CW tone, $\varphi[n] = \omega_c n$, $\omega_c = 2\pi f_c/f_s$). Demod multiplies by $e^{-j\varphi}$, the IIR applies $H(e^{j\omega})$ at baseband, remod multiplies by $e^{+j\varphi}$. For a CW carrier the composite response from input to output is a **frequency-shifted** copy of the baseband filter:

$$H_\text{bp}(e^{j\omega}) = H\!\left(e^{j(\omega - \omega_c)}\right)$$

So the low-pass $H$ (real pole near DC) becomes a band-pass centred at $\omega_c$. All the resonator physics is in $H$; the carrier only says *where* the resonance sits.

---

## 3. Scale factors — IIR/DDS registers → resonator properties

Let $f_s$ be the sample rate at the IIR, $N$ the DDS phase-accumulator width, and write the pole as $C_1 = 1 - \varepsilon$ with $\varepsilon \ll 1$ (high-Q regime).

| Resonator property | Expression | Set by |
|---|---|---|
| Resonant frequency | $f_0 = f_c = \dfrac{\text{DDS\_FREQ\_REG}}{2^{N}}\,f_s$ | `DDS_FREQ_REG` (carrier) |
| Field decay rate | $\kappa/2 = (1 - C_1)\,f_s$ | `C1` (pole) |
| Energy decay rate (loaded linewidth) | $\kappa = 2(1 - C_1)\,f_s$ | `C1` |
| FWHM (Hz) | $\dfrac{\kappa}{2\pi} = \dfrac{(1 - C_1)\,f_s}{\pi}$ | `C1` |
| Loaded quality factor | $Q_L = \dfrac{\pi f_0}{(1 - C_1)\,f_s}$ | `C1`, `DDS_FREQ_REG` |
| Ringdown time (field) | $\tau = \dfrac{1}{(1 - C_1)\,f_s}$ | `C1` |
| On-resonance response | $H(1) = G\,\dfrac{1 - C_0}{1 - C_1}$ | `G`, `C0`, `C1` |

**Derivation of the linewidth.** The pole's impulse response is $\propto C_1^{\,n} = e^{n\ln C_1} \approx e^{-\varepsilon n}$ for $C_1 = 1-\varepsilon$. In continuous time ($t = n/f_s$) the field envelope decays as $e^{-\varepsilon f_s t} = e^{-\kappa t/2}$, giving $\kappa/2 = (1-C_1)f_s$. The power spectrum of a field decaying at $\kappa/2$ is a Lorentzian of FWHM $\kappa$ (rad/s), i.e. $(1-C_1)f_s/\pi$ in Hz, and $Q_L = \omega_0/\kappa$ follows.

> **Sanity check against the code.** The header notes numerical fidelity measured with `C0=0, C1=0, G=32767` (≈0.99997). That is the *pass-through* limit: pole at DC, no filtering, $H(1) = G(1-0)/(1-0) = G \approx 1$. The residual ~3 LSB error is the $G = 32767/32768 \ne 1$ offset plus IIR truncation and the two `cmult` round stages — consistent with the table.

---

## 4. What physical configuration this is

The 1-pole/1-zero shape is exactly the response of a **single-mode resonator in a notch / hanger geometry** (equivalently a reflection measurement). The standard hanger transmission is

$$S_{21}(\Delta) = 1 - \frac{\kappa_c/2}{j\Delta + \kappa/2}, \qquad \Delta = \omega - \omega_0,\ \ \kappa = \kappa_i + \kappa_c,$$

which is a bilinear (Möbius) function of frequency — precisely a 1-pole/1-zero rational form. Rearranging,

$$S_{21}(\Delta) = \frac{j\Delta + \kappa_i/2}{j\Delta + \kappa/2},$$

so on resonance $S_{21}(0) = \kappa_i/\kappa$ (notch depth) and far off resonance $S_{21} \to 1$. This is the readout topology used in cQED — so **the current IIR is already the right physical model**, not an approximation to be replaced.

Matching $H(z)$ to $S_{21}$ at baseband DC ($z=1$) gives a clean coupling interpretation:

| Filter quantity | Physical meaning |
|---|---|
| $1 - C_1$ | total (loaded) linewidth $\kappa = \kappa_i + \kappa_c$ |
| $1 - C_0$ | internal loss $\kappa_i$ |
| $C_0 - C_1$ | coupling $\kappa_c$ |
| $\dfrac{1-C_0}{1-C_1}$ | notch depth $\kappa_i/\kappa$ (1 = shallow/undercoupled, ½ = critical, →0 = deep/overcoupled) |
| $G$ | off-resonance baseline (set ≈ 1 for a passive notch) |

So today's `C0 = 0` means $\kappa_i = \kappa$ — i.e. **fully internally-limited, no external coupling contrast** (the "resonator" has no notch, it's just the pole). To get a realistic notch you set $C_0$ **near** $C_1$, with the small gap $C_0 - C_1$ encoding $\kappa_c$.

**Where a more realistic IIR would help** (candidates for v4, in priority order):
1. **Compute coefficients from physics, don't hand-tune.** Given target $\kappa_i, \kappa_c, \omega_0$, derive $C_0, C_1, G$ via a bilinear (or matched-z) transform of $S_{21}$. This makes the register values mean something and makes ground/excited a physics parameter set.
2. **Complex gain for Fano asymmetry.** Real resonators show an asymmetric, rotated notch (impedance mismatch / cable delay — the $a\,e^{j\phi}$ prefactor in the Khalil notch model). A real `G` cannot produce it; a complex gain (an I/Q rotation) can. There is already a `cmult` in the chain to fold this into.
3. **Warping is negligible.** Because the resonator bandwidth $\ll f_s$, bilinear frequency warping is not worth correcting; the real-pole-at-baseband-DC discretisation is fine.

---

## 5. Ground/excited switching and the stored field

The physically interesting question: *when the resonator frequency jumps mid-readout, there is stored energy with a definite phase — is it handled correctly?*

**Where the stored field lives.** The intracavity field envelope is the IIR feedback state. In each `iir_1p1z` it is `y1` (the saturated pole state `y1_r1a`/`y1_r1b`); the I and Q cores together hold the **complex** intracavity envelope, expressed in the frame rotating at the carrier.

**The jump mechanism.** A jump changes the carrier frequency (`dds_freq_r` → `pinc`). The pole `C1` is unchanged, so the linewidth $\kappa$ is preserved — correct: the cavity's loss rate doesn't change when its frequency does. Because the pole sits at baseband DC in *both* the old and new frames, the stored field's ringing frequency snaps to the new $\omega_0$ with no transient *in the frame*, the correct linear-resonator behaviour (the eigenfrequency is a cavity property and changes instantly; the field amplitude and phase are continuous).

**The three correctness conditions, now checked against the RTL:**

1. **DDS phase continuity — SATISFIED by construction.** `dds_phase_ctrl` emits the control word `{phase=0, pinc}` with `pinc = FREQ_REG − ramp(n)` and a *constant* phase-offset field of 0. The phase **accumulator lives inside the DDS IP** (`dds_phasegen_sincos_ow16_lat8`) and integrates the streamed `pinc`; changing `FREQ_REG` changes the *increment* (the slope), not the accumulated value, so the carrier phase is continuous across the change — the lab-frame field cannot teleport. The controller also advances its datapath only on `i_din_valid`, so bubbles hold the sequence rather than jumping it. *(One residual check: eyeball the DDS behavioural model to confirm the accumulator is free-running and never reloaded — the streaming-`pinc` / fixed-`POFF=0` control word is exactly the phase-continuous configuration, so this is expected.)*
2. **IIR state preserved — SATISFIED.** The `y1` pole registers reset only on `~i_rstn`. A config write (`WE`) latches only the coefficient/frequency registers; nothing in the write path clears the IIR datapath. State carries across the jump. *(Usage note: `WE` latches all registers together, so a frequency-only jump must rewrite `C0/C1/G` with their existing values to avoid perturbing the linewidth.)*
3. **No cancellation-breaking transient — the earlier concern was wrong.** Remod reuses the **identical carrier sample** that demod used: `dds_dout_la = dds_dout` delayed by exactly `prod0(4) + iir(4) = 8`, which is the pipeline latency between the two multipliers. So `prod1[t]` multiplies by `dds_dout[t−8]` and `iir_out[t]` was demodulated by `conj(dds_dout[t−8])` — the same sample — giving $e^{-j\varphi}e^{+j\varphi}=1$ **sample-for-sample, for any carrier trajectory including a step**. The `din_la = DDS_LATENCY = 10` tap likewise aligns each input sample with the frequency commanded when it entered. There is no spurious pipeline glitch at the jump.

**Verdict:** at the datapath level the emulator handles a mid-readout jump *physically correctly* — the stored field keeps its amplitude and phase, immediately rings at the new frequency, and decays at the unchanged $\kappa/2$, with the drive now at the new detuning building the new steady state. The one real transient is the physical one (old field ringing down while the new one builds), which is exactly what we want.

**The genuine v4 gap is the switching *mechanism*, not the datapath.** Neither existing path cleanly does a *triggered, persistent, phase-continuous* step between two resonant frequencies:
- The **chirp/trigger** path (`i_trigger` → `ramp_gen`) sweeps `pinc` for `N` steps and **settles back to `FREQ_REG`** — a sweep-and-return, not a persistent two-level switch.
- The **register write** of `DDS_FREQ_REG` is persistent but not time-deterministic (AXI + `WE` CDC latency; and `WE` is a software-pulsed bit crossing clock domains — the classic sim-passes / hardware-flakes hazard).

For ground↔excited "on demand, triggered from the tProc at a precomputed time," v4 wants a small **triggered frequency-select** (e.g. two latched `FREQ` values and a per-lane trigger that toggles which one drives `pinc`), keeping the accumulator free-running so the switch stays phase-continuous. This is the one new bit of RTL the jump actually needs.

---

## 6. Latency reference (from the RTL)

| Path | Cycles | Source |
|---|---|---|
| DDS block | `DDS_LATENCY = 10` | `dds_phase_ctrl (2) + DDS IP (8)` |
| `din` alignment to carrier | `din_la = DDS_LATENCY = 10` | fixes chirp demod alignment |
| Carrier reuse demod→remod | `dds_dout_la = 8` | `prod0 (4) + iir (4)` — guarantees $e^{-j\varphi}e^{+j\varphi}=1$ |
| `kidsim` main path | `10 + 4 + 4 + 4 = 22` | DDS + prod0 + iir + prod1 |
| `kidsim_top` total | `24` | `punct (2) + KIDSIM_LAT (22)` |

Two independent timing constraints not to conflate (per the `kidsim` header): `dds_dout_la = 8` guarantees carrier cancellation for *any* input; `din_la = DDS_LATENCY` selects *which* input sample is demodulated at each instantaneous chirp frequency and only matters when the input varies in time.

---

## 7. Validation plan (what a demonstrating notebook should show)

A short QICK notebook (or xsim testbench) can turn the theory above into measured numbers:

1. **Linewidth / Q.** Sweep the probe across $f_0$, measure the transmitted magnitude, fit a Lorentzian, and check FWHM $= (1-C_1)f_s/\pi$ and $Q_L = \pi f_0/((1-C_1)f_s)$ against the table for a few `C1` values.
2. **Ringdown.** Drive on resonance to steady state, switch the drive off, fit the decay, and check $\tau = 1/((1-C_1)f_s)$.
3. **Notch depth vs coupling.** Set $C_0$ near $C_1$, sweep the gap $C_0 - C_1$, and confirm the on-resonance depth tracks $\kappa_i/\kappa = (1-C_0)/(1-C_1)$.
4. **The jump (the important one).** Reach steady state, jump `DDS_FREQ_REG` (ground→excited), and plot the lab-frame output through the transition. Confirm: field amplitude/phase continuous, new-frequency ringing, decay at the unchanged $\kappa/2$. This is also the test that surfaces condition (1)/(3) of §5 if the DDS is not phase-continuous.
5. **Fake T1.** Trigger the ground→excited jump from the tProc at a precomputed time and show the readout following the programmed decay.

**Characterization notes (measured in xsim):**
- The datapath advances **every clock**, not per input beat: the DDS IP free-runs its output valid, so `dds_valid` (hence `prod0`/IIR/`prod1`) is asserted every cycle regardless of how sparse `din_valid` is. The `iir_1p1z` bubble-gating is therefore moot under a running carrier. Consequence for the scale factors: the decay is $C_1$ **per clock**, so $\tau = 1/((1-C_1)f_s)$ is per-sample-at-$f_s$ exactly as in §3 — confirmed by a ringdown showing $|y_1|[n]=|y_1|[0]\,C_1^{n}$ per clock. (A test that streams sparse beats measures $C_1^{\text{gap}}$ per beat and looks wrong; drive contiguously.)
- A small **DC floor** sits under the ringdown: the two `cmult` stages use round-half-up (`ROUND=1`), whose $+\tfrac12$ LSB bias is integrated by the pole to $\approx \text{bias}/(1-C_1)$ (≈13 LSB at $C_1=0.9$). Harmless for the emulation, but measure the linewidth well above it.

---

## 8. Open items feeding v4

- Decide whether to keep hand-tuned `C0/C1/G` or add a **physics→coefficient** helper (bilinear transform from $\kappa_i,\kappa_c,\omega_0$). Recommended.
- Decide whether Fano asymmetry matters for the intended use; if so, add a **complex gain** stage.
- §5 conditions (1)–(3) are **resolved in RTL**: phase-continuous DDS, preserved IIR state, exact carrier cancellation through a step. The remaining jump work is the **triggered persistent frequency-select** (two latched `FREQ` values + per-lane trigger, accumulator kept free-running), and the residual DDS-model eyeball of condition (1). Lock the datapath behaviour with the jump test of §7.4.
- This note documents the **passive resonator**. The **active RF qubit emulator** (DDS LO + Bloch-state registers + demod-driven state rotation → Rabi) is a separate v4 datapath and gets its own note.
