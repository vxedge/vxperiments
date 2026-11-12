# exp-017: VSS scenarios on the signal plane

Four SDV scenarios on the COVESA VSS 6.0 metadata that kuksa-databroker 0.7.1 bundles, run on
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03)'s broker, then VSS 6.1 against the same broker
version, test-side.

## The package

This folder is the `vxp/1` package `vxedge/exp-017`, version 0.2.0 (`vxp.yaml`). Its catalogue
alias is `exp-017`. Like exp-015, it is a functional suite: `main.yaml`'s `checks` (vxedge 0.22.0)
run each case as a step and judge what the client prints.

| What | Where it was | Where it is |
|---|---|---|
| The vehicle | `../../vehicles/vx-vehicle-03` | `vehicle.yaml` and `parts.yaml`, as in exp-015 |
| The scenarios on the vehicle | `scenarios.sh` | `checks.steps` on `cabin1` and `hpc1`, and their cases |
| Throwaway brokers on a VSS file | `vss61.sh`, `podman run` with the file fetched by URL | steps `on: alone`, each given its file from `assets/` |
| A broker's list against its file | `compare.py` | `tools/compare.py`, run by the client image's Python, printing one JSON line |
| `PASS`, `FAIL` and `OBS` lines | the scripts | `checks.cases`; `OBS` lines are `observe` cases |

```bash
podman build -t localhost/vxperiments/kv2:1 tools/kv2
vxedge campaign start
vxedge results verdict --experiment . results/<campaign>
```

[`assets/`](assets) holds the three VSS files the scripts fetched, each with the sha256 they were
checked by. `tools/kv2` is exp-015's client, copied so the package stands alone.

## Scenarios, on the vehicle

Each scenario has a function on `cabin1`, a sensor feed or an actuator provider, and a consumer
on `hpc1`, both on `adas`, through kv2 on `kuksa.val.v2`.

| Scenario | Signals |
|---|---|
| ADAS | `Vehicle.Speed`, `Vehicle.ADAS.ABS.IsEngaged`, `Vehicle.ADAS.CruiseControl.SpeedSet` and `.IsActive` |
| Body | `Vehicle.Cabin.Door.Row1.DriverSide.Window.Position`, `.IsLocked`, `.IsOpen` |
| EV | `Vehicle.Powertrain.TractionBattery.StateOfCharge.Current`, `.Charging.IsCharging`, `.Charging.ChargeLimit` |
| Cabin | `Vehicle.Cabin.HVAC.Station.Row1.Driver.Temperature` and `.AirDistribution` |

Each checks metadata (entry type, data type, unit, min, max, allowed values), a consumer receiving
what the function published, and actuation reaching the provider. The judged cases also
check what `kuksa.val.v2` documents as `INVALID_ARGUMENT`: a value of the wrong type, outside
min/max, not in the allowed list, or an actuation of a sensor. `observe` cases record what the
documentation does not say, such as writing an attribute or sending a `double` to a `float`.

## VSS 6.1, test-side

VSS 6.1 (2026-09-17) is not bundled in 0.7.1, or on upstream `main`. The signal plane's `config`
carries `listen` alone, so giving the vehicle's broker another file would need a vxedge change. The
package starts throwaway brokers instead, each in a namespace of its own: one on the bundled file
and one on the 6.1 release's `vss.json` mounted with `--vss`. It checks each broker lists exactly
the signals and types in its file, then 6.1's changes.

Differences found by comparing the files, before any run:

- **The bundled 6.0 file is not the COVESA v6.0 release.** The release's `vss.json` has four
  `Vehicle.Powertrain.FuelSystem` signals the bundled `vss_release_6.0.json` lacks
  (`AfterRefuelingFuelEconomy`, `CumulativeFuelEconomy`, `DriveFuelEconomy`,
  `InstantantFuelEconomy`, spelled that way). The signals both files share have the same type,
  unit and range.
- **6.1 instances the electric motor.** The 14 `Vehicle.Powertrain.ElectricMotor.*` leaves move under
  instances (`Front`, `Rear`, ...). can-provider 0.5.1's newest mapping is `vss_6.0`, and it maps
  `ElectricMotor.Power`, `.Temperature` and `.Torque`, which 6.1 no longer has.
- **6.1 adds an `enum` key** to five `uint8` sensors, such as `Vehicle.Exterior.PrecipitationType`,
  with no min, max or allowed list. Whether the broker reads it is what the run records.
- 133 signals are added and 14 removed, no shared signal changes type, unit or range, and six
  units are new (`hPa`, `m/s`, `mm/h`, `ppb`, `ppm`, `ug/m^3`).

## What this does not show

- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.
- The scenarios are test clients standing in for functions. No plant model or vehicle application
  produces or uses the values.
- Nothing is timed.
