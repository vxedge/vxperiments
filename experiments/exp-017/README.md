# exp-017: VSS scenarios on the signal plane

Four SDV scenarios on the COVESA VSS 6.0 metadata that kuksa-databroker 0.7.1 bundles, run on
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03)'s broker, then VSS 6.1 against the same broker
version, test-side.

```bash
podman build -t localhost/vxperiments/kv2:1 ../exp-015/tools/kv2
VXEDGE_BUILD=<vxedge>/target/debug ./run.sh     # needs a sudo timestamp, see run.sh
```

## Scenarios, on the vehicle

Each scenario has a function on `cabin1`, a sensor feed or an actuator provider, and a consumer
on `hpc1`, both on `adas`, through kv2 on `kuksa.val.v2` ([`scenarios.sh`](scenarios.sh)).

| Scenario | Signals |
|---|---|
| ADAS | `Vehicle.Speed`, `Vehicle.ADAS.ABS.IsEngaged`, `Vehicle.ADAS.CruiseControl.SpeedSet` and `.IsActive` |
| Body | `Vehicle.Cabin.Door.Row1.DriverSide.Window.Position`, `.IsLocked`, `.IsOpen` |
| EV | `Vehicle.Powertrain.TractionBattery.StateOfCharge.Current`, `.Charging.IsCharging`, `.Charging.ChargeLimit` |
| Cabin | `Vehicle.Cabin.HVAC.Station.Row1.Driver.Temperature` and `.AirDistribution` |

Each checks metadata (entry type, data type, unit, min, max, allowed values), a consumer receiving
what the function published, and actuation reaching the provider. `PASS` and `FAIL` lines also
check what `kuksa.val.v2` documents as `INVALID_ARGUMENT`: a value of the wrong type, outside
min/max, not in the allowed list, or an actuation of a sensor. `OBS` lines record what the
documentation does not say, such as writing an attribute or sending a `double` to a `float`.

## VSS 6.1, test-side

VSS 6.1 (2026-09-17) is not bundled in 0.7.1, or on upstream `main`. The signal plane's `config`
carries `listen` alone, so giving the vehicle's broker another file would need a vxedge change.
[`vss61.sh`](vss61.sh) starts throwaway rootless brokers instead, one on the bundled file and one
on the 6.1 release's `vss.json` mounted with `--vss`, both fetched by URL and checked by sha256.
It checks each broker lists exactly the signals and types in its file, then 6.1's changes.

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
