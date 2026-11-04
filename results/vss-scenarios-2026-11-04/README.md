# VSS scenarios on vx-vehicle-03, 2026-11-04

[`exp-017`](../../experiments/exp-017): four SDV scenarios on the VSS 6.0 metadata bundled in
kuksa-databroker 0.7.1, on [`vx-vehicle-03`](../../vehicles/vx-vehicle-03)'s signal plane, then
VSS 6.1 against throwaway 0.7.1 brokers, test-side. **This is the published run, from merged
`main`:** vxedge `8ad34b1`, vxperiments `a68aa8c`. The branch run before the merge,
[`vss-scenarios-2026-11-03`](../vss-scenarios-2026-11-03), gave the same results.

[`transcript.txt`](transcript.txt) is the whole run, with paths shortened to `vxperiments/`.
[`list-6.0.txt`](list-6.0.txt) and [`list-6.1.txt`](list-6.1.txt) are every signal each broker
listed, and [`vehicle-document.sha256`](vehicle-document.sha256) pins the workspace documents.

Databroker: `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd`.
VSS 6.1: the v6.1 release's `vss.json`, sha256 `bef9ad501b38edd60e7b903cb39ba5b8f0864a984595b3e901d6efa3f06bdb70`.

**30 checks passed, none failed.**

## Scenarios, on the vehicle

A function on `cabin1` and a consumer on `hpc1`, both on `adas`, over `kuksa.val.v2`.

| Scenario | Passed |
|---|---|
| ADAS | speed and ABS reached the consumer; cruise control set speed and on/off reached the provider; actuating a sensor and a string for a float were `INVALID_ARGUMENT` |
| Body | window position and lock reached the provider; window position 101 (max 100) was `INVALID_ARGUMENT` |
| EV | state of charge and charging published; 150 % was `INVALID_ARGUMENT` and left 80.5 in place; charge limit 90 reached the provider, 120 was `INVALID_ARGUMENT` |
| Cabin | HVAC temperature and air distribution reached the provider; `SIDEWAYS`, not in the allowed list, was `INVALID_ARGUMENT` |

Each scenario's metadata matched VSS 6.0: entry type, data type, unit, min, max and allowed values.

Observed, where the documentation does not say:

- Publishing a current value to an actuator (`...DriverSide.IsOpen`) and to an attribute (the VIN)
  was accepted.
- The type check is exact: a `double` for a `float` signal and an `int64` for an `int8` one were both
  `INVALID_ARGUMENT`.

## VSS 6.1, test-side

0.7.1 bundles VSS 6.0 and 5.1 only, and the signal plane's `config` carries `listen` alone, so 6.1
ran on throwaway rootless brokers, mounted with `--vss`.

| Check | Result |
|---|---|
| The bundled 6.0 file: broker against file | 1,263 signals, identical paths and types |
| 6.1 mounted as a separate file: broker against file | 1,382 signals, identical paths and types; started and stayed running |
| A signal added in 6.1 (`Vehicle.Cabin.AirQuality.CO2`) | published |
| A signal removed in 6.1 (`Vehicle.Powertrain.ElectricMotor.Power`) | `NOT_FOUND`; its 6.1 instance `ElectricMotor.Front.Power` exists |

Compatibility findings:

- **The bundled 6.0 file is not the COVESA v6.0 release.** The 0.7.1 broker serves 1,263 signals
  against the release's 1,267. It lacks four `Vehicle.Powertrain.FuelSystem` fuel-economy signals
  (`AfterRefuelingFuelEconomy`, `CumulativeFuelEconomy`, `DriveFuelEconomy`,
  `InstantantFuelEconomy`), which the release has. On the vehicle's broker the first two returned
  `NOT_FOUND`.
- **6.1's `enum` key is not enforced.** `Vehicle.Exterior.PrecipitationType` is `uint8` with an enum
  of 0 to 5 and no min, max or allowed list. The broker accepted both 2 and 200.
- **can-provider 0.5.1 does not start against a 6.1 broker.** Its newest mapping, `vss_6.0`, maps
  `ElectricMotor.Power`, `.Temperature` and `.Torque`, which 6.1 moves under instances. It logged
  `Signal ... is not registered` for each, then `Not all datapoints registered, exiting!`, and fed
  nothing, not even speed.

## What this does not show

- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.
- The scenarios' functions and consumers are test clients. No plant model or vehicle application
  produced or used the values.
- Nothing was timed.
